'use strict';
/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2025-2026 Lucas Albers <lucas.b.albers@gmail.com> */

'require baseclass';

function createBatch() {
	const batch = {};
	batch.promise = new Promise(function (resolve) {
		batch.resolve = resolve;
	});
	return batch;
}

/* Own request serialization and scheduling. The runner owns result application
 * and must check its epoch before applying asynchronous results. Adapters supply
 * poll.add/remove, visibility.add/remove, isHidden, run, and initialCadence. */
function createCoordinator(options) {
	const { poll, visibility, isHidden, run, initialCadence } = options;
	if (!Number.isFinite(initialCadence) || initialCadence <= 0)
		throw new TypeError('initialCadence must be a positive number');

	let epoch = 0;
	let cadenceSec = initialCadence;
	let active = null;
	let pending = null;
	let started = false;
	let registered = false;
	let disposed = false;
	let hidden = isHidden();

	function removePoll() {
		if (!registered) return;
		poll.remove(requestPoll);
		registered = false;
	}

	function addPoll() {
		if (!started || registered || disposed || isHidden()) return;
		poll.add(requestPoll, cadenceSec);
		registered = true;
	}

	function finish(batch, value) {
		/* Disposal detaches the batch; its eventual completion has no effect. */
		if (active !== batch) return;
		active = null;
		batch.resolve(value);
		if (pending && !isHidden()) startPending();
	}

	function startPending() {
		const batch = pending;
		pending = null;
		/* Claim ownership before invoking user code, including synchronous runs. */
		active = batch;
		let result;
		try {
			result = Promise.resolve(run(epoch));
		} catch (e) {
			result = Promise.reject(e);
		}
		result.then(
			function (value) {
				finish(batch, value);
			},
			function () {
				/* A failed runner must still release callers and the queued batch. */
				finish(batch);
			}
		);
	}

	function requestPoll() {
		if (disposed || isHidden()) return Promise.resolve();
		/* All callers waiting for the follow-up share one promise. Read the
		 * latest view preferences only when that batch starts. */
		if (!pending) pending = createBatch();
		const promise = pending.promise;
		if (!active) startPending();
		return promise;
	}

	function setCadence(sec) {
		if (disposed) return;
		const next = Number.isFinite(sec) && sec > 0 ? sec : initialCadence;
		if (next === cadenceSec) return;
		cadenceSec = next;
		removePoll();
		addPoll();
	}

	function onVisibilityChange() {
		if (disposed || hidden === isHidden()) return;
		hidden = isHidden();
		epoch++;
		if (hidden) {
			removePoll();
			return;
		}
		if (options.onVisible) options.onVisible();
		addPoll();
		/* A stale request may still be on the wire. Catch up only after it
		 * settles, retaining any refresh requested before the tab was hidden. */
		requestPoll();
	}

	function startPolling() {
		if (disposed || started) return;
		started = true;
		hidden = isHidden();
		visibility.add(onVisibilityChange);
		addPoll();
	}

	function dispose() {
		if (disposed) return;
		disposed = true;
		epoch++;
		removePoll();
		if (started) visibility.remove(onVisibilityChange);
		/* Terminal for this view: settle callers without waiting for the RPC.
		 * Retain the invalidated epoch so late view work remains stale. */
		if (active) active.resolve();
		if (pending) pending.resolve();
		active = null;
		pending = null;
	}

	return {
		requestPoll: requestPoll,
		startPolling: startPolling,
		setCadence: setCadence,
		dispose: dispose,
		getState: function () {
			return {
				epoch: epoch,
				cadenceSec: cadenceSec,
				inFlight: active !== null,
				queued: pending !== null,
				disposed: disposed
			};
		}
	};
}

return baseclass.extend({
	create: createCoordinator
});
