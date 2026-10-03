'use strict';

'require baseclass';
'require ui';

'require podman.model.Model as Model';
'require podman.ui as podmanUI';

const PodRPC = {
	inspect: Model.declareRPC({
		object: 'podman',
		method: 'pod_inspect',
		params: ['name']
	}),

	start: Model.declareRPC({
		object: 'podman',
		method: 'pod_start',
		params: ['name']
	}),

	stop: Model.declareRPC({
		object: 'podman',
		method: 'pod_stop',
		params: ['name']
	}),

	kill: Model.declareRPCSilent({
		object: 'podman',
		method: 'pod_kill',
		params: ['name', 'signal']
	}),

	restart: Model.declareRPC({
		object: 'podman',
		method: 'pod_restart',
		params: ['name']
	}),

	pause: Model.declareRPC({
		object: 'podman',
		method: 'pod_pause',
		params: ['name']
	}),

	unpause: Model.declareRPC({
		object: 'podman',
		method: 'pod_unpause',
		params: ['name']
	}),

	remove: Model.declareRPC({
		object: 'podman',
		method: 'pod_remove',
		params: ['name', 'force']
	}),
};

const Pod = Model.base.extend({
	__name__: 'Podman.Model.Pod',

	getID() {
		return this.Id;
	},

	getName() {
		return this.Name || this.Id || _('Unknown');
	},

	getStatus() {
		return this.Status || this.State || '';
	},

	getStatusBadge() {
		const status = this.getStatus();
		const cssClass = status.toLowerCase();
		return E('div', { class: `badge ${cssClass}` }, [ status ]);
	},

	getCreatedAt() {
		return this.Created;
	},

	getInfraId() {
		return this.InfraId || this.InfraContainerID;
	},

	getNetworks() {
		return this.Networks || [];
	},

	getLabels() {
		return this.Labels || {};
	},

	getContainers() {
		return this.Containers || [];
	},

	isRunning() {
		return this.getStatus() === 'Running';
	},

	isPaused() {
		return this.getStatus() === 'Paused';
	},

	isStopped() {
		const state = this.getStatus();
		return state === 'Stopped' || state === 'Exited' || state === 'Created' || state === 'Dead';
	},

	async inspect() {
		return PodRPC.inspect(this.getName());
	},

	async start() {
		return PodRPC.start(this.getName());
	},

	async stop() {
		const result = await PodRPC.stop(this.getName());
		if (result?.Id) return result;

		try {
			return await PodRPC.kill(this.getName(), 'SIGKILL');
		} catch (err) {
			const msg = String(err?.message || err);
			if (msg.includes('no running containers')) return result;
			ui.hideModal();
			podmanUI.alert(msg, 'error');
			throw err;
		}
	},

	async restart() {
		return PodRPC.restart(this.getName());
	},

	async pause() {
		return PodRPC.pause(this.getName());
	},

	async unpause() {
		return PodRPC.unpause(this.getName());
	},

	async remove(force) {
		return PodRPC.remove(this.getName(), force ?? true);
	},

	streamTop(onChunk, delay) {
		const params = new URLSearchParams({ delay: String(delay || 2) });
		const url = L.url('admin/podman/stream/pod_top', this.getName()) + '?' + params;
		return this._stream(
			() => url,
			(data) => { if (!data.raw && !data.Error) onChunk(data); }
		);
	},

	streamStats(onChunk) {
		const url = L.url('admin/podman/stream/pod_stats', this.getName());
		return this._stream(
			() => url,
			(data) => {
				if (!Array.isArray(data)) return;
				onChunk(data);
			}
		);
	},

	getDetailLink(label) {
		return E('a', { href: L.url('admin/podman/pod', this.getID()) }, label || this.getName());
	},
});

return baseclass.extend({
	__name__: 'Podman.Model.Pod',
	getSingleton(data) {
		return Pod.extend(data).instantiate([]);
	},
});
