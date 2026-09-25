'use strict';
'require baseclass';
'require dom';

/* A hex editor, in about two hundred lines.
 *
 * WHY NOT THE STOCK ONE. luci-app-filemanager ships 40,660 bytes of HexEditor: ASCII, hex and
 * RegExp search, a settings panel for its own padding, and a `<style>` element injected into the
 * document — which outlives the page that added it and repaints the next one. Half of that is the
 * search. This is the other half: look at the bytes, change them, save them.
 *
 * VIRTUAL SCROLLING IS NOT AN OPTIMISATION HERE, it is the only way the thing works. At 16 bytes a
 * line a 1 MB file is 65,536 lines; building them costs seconds and holding them costs a phone its
 * tab. What exists instead is a spacer of the full height and a window of the lines actually on
 * screen, redrawn on scroll.
 *
 * THE FILE IS NOT A STRING. It arrives as a Blob through cgi-io (`fs.read_direct`, which is what
 * this page already uses to download) and lives as a Uint8Array; nothing here decodes it, because
 * the whole point is the bytes that are not text. The caller reads them back with `value()`. */

/* E() WITH THE MARKUP SINK CLOSED: a primitive last argument becomes a text node, never
 * innerHTML. The reasoning, and the stand proof, are on the same shim in browser.js. */
function E() {
	const args = Array.prototype.slice.call(arguments);
	const last = args.length - 1;
	if (last >= 1 && args[last] != null && typeof args[last] !== 'object' && typeof args[last] !== 'function')
		args[last] = [ args[last] ];
	return window.E.apply(null, args);
}

/* ---- fill(), THE SAME SINK ONE DOOR ALONG -----------------------------------------------------
 *
 * `E()` IS ONLY ONE OF dom.append's CALLERS, and the shim above therefore closes only one of the
 * doors. `dom.content(node, children)` empties the node and hands the children to that same
 * function, so its string branch is the same `node.innerHTML = ${children}` — reached without
 * `E()` ever being called, and invisible to a shim that wraps E's last argument.
 *
 * A FUNCTION IS THE SINK AT ONE REMOVE. dom.append does
 *
 *     else if (typeof(children) === 'function') { return this.append(node, children(node)); }
 *
 * — it CALLS what it is given and recurses on the result, so `fill(node, () => entry.name)` would
 * land a file name on innerHTML just as a bare string does. Both are normalised here.
 *
 * Nothing in this module passes either shape today. This is what keeps it that way, in the shape
 * the E() shim already established: one function, not a rule to be remembered at every call site.
 * Anything that is not an array and not a node becomes a ONE-ELEMENT ARRAY — the branch that builds
 * text nodes — and `[ null ]` appends nothing, exactly as a bare `null` did.
 *
 * `dom.content` is called HERE AND NOWHERE ELSE in this module, the way `window.E` is reached only
 * inside the shim above. tools/dom-sinks.mjs holds both. */
function fill(node, children) {
	return dom.content(node, (Array.isArray(children) || dom.elem(children)) ? children : [ children ]);
}

const ROW = 16;			/* bytes per line — the width every hex dump has had since od(1) */
const OVERSCAN = 6;		/* lines drawn above and below the window, so a fast scroll has cover */

const HEX = [];
for (let i = 0; i < 256; i++) HEX.push(i.toString(16).padStart(2, '0'));

/* A byte is printable if it is a printable ASCII character; everything else is a dot, the way every
 * hex dump does it. Latin-1 would be prettier and a lie: the file has no encoding. */
function ascii(b) {
	return (b >= 0x20 && b < 0x7f) ? String.fromCharCode(b) : '.';
}

/* The text column of the line that starts at `start`. */
function textOf(data, start) {
	let s = '';
	for (let i = 0; i < ROW && start + i < data.length; i++) s += ascii(data[start + i]);
	return s;
}

return baseclass.extend({
	/* `container` is emptied and filled. Returns a handle whose `value()` is the bytes. */
	open(container, bytes) {
		const data = new Uint8Array(bytes);
		const lines = Math.max(1, Math.ceil(data.length / ROW));
		let caret = 0;			/* byte the caret is on */
		let nibble = 0;			/* 0 = the high half of that byte is next, 1 = the low half */
		let first = -1;			/* first line currently drawn, so a scroll that moves nothing redraws nothing */

		const layer = E('div', { class: 'fsf-hex-layer' });
		const spacer = E('div', { class: 'fsf-hex-spacer' }, layer);
		const view = E('div', { class: 'fsf-hex', tabindex: '0' }, spacer);

		/* MEASURED, NOT ASSUMED. The line height is whatever the theme's monospace stack gives at
		 * this size, and a guess would drift a pixel per line — 65,536 lines of drift. One line is
		 * rendered off-screen to ask. */
		const probe = E('div', { class: 'fsf-hex-line' }, E('span', { class: 'fsf-hex-off' }, '00000000'));
		view.appendChild(probe);
		const LH = probe.getBoundingClientRect().height || 18;
		probe.remove();

		spacer.style.height = (lines * LH) + 'px';

		const line = (n) => {
			const start = n * ROW;
			const cells = [];
			for (let i = 0; i < ROW; i++) {
				const at = start + i;
				const has = at < data.length;
				cells.push(E('span', {
					class: 'fsf-hex-b' + (at === caret ? ' fsf-hex-at' : ''),
					'data-at': has ? String(at) : null,
				}, has ? HEX[data[at]] : '  '));
			}
			return E('div', { class: 'fsf-hex-line' }, [
				E('span', { class: 'fsf-hex-off' }, (start).toString(16).padStart(8, '0')),
				E('span', { class: 'fsf-hex-bytes' }, cells),
				E('span', { class: 'fsf-hex-text' }, textOf(data, start)),
			]);
		};

		const draw = (force) => {
			const top = Math.max(0, Math.floor(view.scrollTop / LH) - OVERSCAN);
			if (!force && top === first) return;
			first = top;
			const count = Math.ceil(view.clientHeight / LH) + (OVERSCAN * 2);
			const out = [];
			for (let n = top; n < Math.min(lines, top + count); n++) out.push(line(n));
			layer.style.transform = 'translateY(' + (top * LH) + 'px)';
			fill(layer, out);
		};

		/* The caret is a class on one cell, so moving it redraws nothing but the two cells involved
		 * — until it leaves the window, which is the only time the lines are rebuilt. */
		const paint = () => {
			const old = layer.querySelector('.fsf-hex-at');
			if (old) old.classList.remove('fsf-hex-at');
			const now = layer.querySelector('[data-at="' + caret + '"]');
			if (now) { now.classList.add('fsf-hex-at'); return; }
			/* out of view: scroll it back in, which redraws */
			const target = Math.floor(caret / ROW);
			view.scrollTop = (target - Math.floor(view.clientHeight / LH / 2)) * LH;
			draw(true);
			const el = layer.querySelector('[data-at="' + caret + '"]');
			if (el) el.classList.add('fsf-hex-at');
		};

		const move = (to) => {
			caret = Math.max(0, Math.min(data.length - 1, to));
			nibble = 0;
			paint();
		};

		view.addEventListener('scroll', () => draw(false));
		view.addEventListener('click', (ev) => {
			const cell = ev.target.closest('[data-at]');
			if (cell) move(+cell.getAttribute('data-at'));
		});

		view.addEventListener('keydown', (ev) => {
			const perScreen = Math.max(1, Math.floor(view.clientHeight / LH) - 1) * ROW;
			/* A null prototype: the key is `ev.key`, which this page does not choose, and an
			 * inherited `constructor` would pass the `!= null` test below and move the caret by a
			 * function — NaN, and a caret that cannot be moved back. */
			const keys = Object.assign(Object.create(null), {
				ArrowLeft: -1, ArrowRight: 1, ArrowUp: -ROW, ArrowDown: ROW,
				PageUp: -perScreen, PageDown: perScreen,
			});
			if (keys[ev.key] != null) { ev.preventDefault(); return move(caret + keys[ev.key]); }
			if (ev.key === 'Home') { ev.preventDefault(); return move(ev.ctrlKey ? 0 : caret - (caret % ROW)); }
			if (ev.key === 'End') { ev.preventDefault(); return move(ev.ctrlKey ? data.length - 1 : caret - (caret % ROW) + ROW - 1); }

			/* TYPING IS NIBBLE BY NIBBLE, which is how every hex editor takes input: the first digit
			 * replaces the high half and leaves the caret where it is, the second replaces the low
			 * half and moves on. Anything else — a modifier, a letter past f — is not ours. */
			if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
			const d = parseInt(ev.key, 16);
			if (ev.key.length !== 1 || isNaN(d)) return;
			ev.preventDefault();
			data[caret] = nibble
				? ((data[caret] & 0xf0) | d)
				: ((data[caret] & 0x0f) | (d << 4));
			const cell = layer.querySelector('[data-at="' + caret + '"]');
			if (cell) {
				cell.textContent = HEX[data[caret]];
				cell.classList.add('fsf-hex-edited');
				/* the text column of that line, rebuilt for the one character that changed */
				cell.closest('.fsf-hex-line').querySelector('.fsf-hex-text').textContent = textOf(data, caret - (caret % ROW));
			}
			if (nibble) { nibble = 0; if (caret + 1 < data.length) move(caret + 1); }
			else nibble = 1;
		});

		fill(container, view);
		draw(true);
		view.focus();

		return { value: () => data };
	},

	/* base64 for the ubus `file write`, in chunks small enough for `String.fromCharCode` not to
	 * blow the argument list. */
	base64(bytes, from, to) {
		let s = '';
		for (let i = from; i < to; i += 4096)
			s += String.fromCharCode.apply(null, bytes.subarray(i, Math.min(to, i + 4096)));
		return btoa(s);
	},
});
