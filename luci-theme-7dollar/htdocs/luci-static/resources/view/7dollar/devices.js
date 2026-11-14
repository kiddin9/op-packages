'use strict';
'require view';
'require poll';
'require 7dollar.common as td';

/* All devices: online (Wi-Fi + wired) and recently seen DHCP clients. The summary tiles filter the list. */

const T = td.T, icon = td.icon, esc = td.esc;
const VIEWS = [
	[ 'on', T('在线', 'Online'), c => c.online ],
	[ 'wifi', 'Wi‑Fi', c => c.online && c.conn == 'wifi' ],
	[ 'wired', T('有线', 'Wired'), c => c.online && c.conn != 'wifi', T('局域网', 'LAN') ],   // a side router sees the whole LAN here
	[ 'off', T('最近连接过', 'Recently seen'), c => !c.online ]
];

return view.extend({
	load() {
		if (!td.active) {
			location.replace(L.url('admin/status/overview'));
			return new Promise(() => {});
		}
		return td.clients();
	},

	render(list) {
		const root = td.html(`<div class="td-devices">
			<div class="td-head"><div>
				<p class="td-eyebrow">${esc(T('设备', 'Devices'))}</p>
				<h1 class="td-serif">${esc(T('谁在用网络', 'Who is online'))}</h1>
				<p class="td-sub" id="td-dsum">&nbsp;</p>
			</div>
			<a class="btn" href="${L.url('admin/network/dhcp')}">${icon('lock')}${esc(T('给设备固定 IP', 'Reserve an IP'))}</a></div>
			<div class="td-stats" id="td-dstats">${VIEWS.map(([ k, n ]) => `<button type="button" class="td-stat" data-v="${k}"><small>${esc(n)}</small><b>0</b></button>`).join('')}</div>
			<section class="td-card"><div class="td-devlist" id="td-dlist"></div></section>
		</div>`);

		this.root = root;
		this.view = 'on';
		root.querySelector('#td-dstats').addEventListener('click', ev => {
			const b = ev.target.closest('[data-v]');
			if (b) { this.view = b.dataset.v; this.paint(this.list); }
		});
		this.paint(list);
		poll.add(() => td.clients().then(l => this.paint(l)), 5);
		return root;
	},

	row(c) {
		const meta = [];
		if (c.ip) meta.push(`<span>${esc(c.ip)}</span>`);
		meta.push(`<span>${esc(c.mac)}</span>`);

		let sub;
		if (!c.online) sub = c.expires > 0 ? T('租约剩余 ', 'Lease ') + td.duration(c.expires) : T('离线', 'Offline');
		else if (c.conn == 'wifi') {
			const [ s ] = td.signal(c.signal);
			sub = `Wi‑Fi ${td.bandName(c.band)} · ${s}${c.signal ? ` (${c.signal} dBm)` : ''}`;
			if (c.link) meta.unshift(`<span><b>${Math.round(c.link)} Mbps</b></span>`);
			if (c.since) meta.push(`<span>${esc(T('已连接 ', 'Connected ') + td.duration(c.since))}</span>`);
		}
		else sub = td.connName(c);

		return `<div class="td-dev"><div class="td-av">${icon(c.kind)}</div><div class="nm"><b>${esc(c.display)}</b><small>${esc(sub)}</small></div><div class="meta">${meta.join('')}</div></div>`;
	},

	paint(list) {
		this.list = list;
		const on = list.filter(c => c.online);
		const $ = id => this.root.querySelector('#' + id);

		$('td-dsum').textContent = on.length
			? T(`现在有 ${on.length} 台设备在线。名字来自设备自己上报的主机名。`, `${on.length} device${on.length == 1 ? '' : 's'} online right now.`)
			: T('现在没有设备在线。', 'No devices online right now.');

		let rows = [];
		const lan = list.some(c => c.conn == 'lan');
		VIEWS.forEach(([ k, n, match, alt ]) => {
			const b = $('td-dstats').querySelector(`[data-v="${k}"]`), sel = list.filter(match);
			b.firstChild.textContent = lan && alt || n;
			b.lastChild.textContent = sel.length;
			b.hidden = lan && k == 'wifi' && !sel.length;   // no Wi-Fi of our own to count
			b.setAttribute('aria-pressed', k == this.view);
			if (k == this.view) rows = sel;
		});
		const box = $('td-dlist'), html = rows.length ? rows.map(c => this.row(c)).join('') : `<div class="td-empty-row">${esc(T('这里暂时没有设备', 'No devices here'))}</div>`;
		if (box._html !== html) box.innerHTML = box._html = html;   // every 5 s, but the DOM only moves when something changed
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
