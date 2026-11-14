'use strict';
'require view';
'require ui';
'require 7dollar.common as td';

/* Every plugin page the router has, as tiles. The theme depends on none of them. */

const T = td.T, icon = td.icon, esc = td.esc;

return view.extend({
	load() {
		if (!td.active) {
			location.replace(L.url('admin/services'));
			return new Promise(() => {});
		}
		return td.loadMenu();
	},

	render(tree) {
		const pages = td.flatten(tree).filter(p => p.group == 'apps' && p.path != 'admin/apps');
		const CAT = { services: T('服务', 'Service'), vpn: 'VPN', nas: T('存储', 'Storage'), docker: T('容器', 'Container'), statistics: T('统计', 'Statistics') };

		const tiles = pages.map((p, i) => {
			const cat = CAT[p.path.split('/')[1]] || T('插件', 'Plugin');
			return `<a class="td-app-t" href="${L.url(p.path)}" style="animation-delay:${Math.min(i, 10) * 30}ms"><div class="td-av">${icon(td.appIcon(p.path))}</div><div><b>${esc(p.title)}</b><small>${esc(cat)}</small></div></a>`;
		}).join('');

		const add = td.software(tree);

		return td.html(`<div class="td-appsview">
			<div class="td-head"><div>
				<p class="td-eyebrow">${esc(T('应用', 'Apps'))}</p>
				<h1 class="td-serif">${esc(T('已安装的应用', 'Installed apps'))}</h1>
				<p class="td-sub">${esc(pages.length ? T(`共 ${pages.length} 个`, `${pages.length} installed`)
				                                     : T('还没有安装插件。', 'No plugins installed yet.'))}</p>
			</div></div>
			<div class="td-apps">${tiles}
				${add ? `<a class="td-app-t add" href="${L.url('admin/' + add)}"><div class="td-av">${icon('plus')}</div><div><b style="color:var(--ink-2)">${esc(T('安装更多应用', 'Get more apps'))}</b><small>${esc(T('前往软件包', 'Open Software'))}</small></div></a>` : ''}
			</div>
		</div>`);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
