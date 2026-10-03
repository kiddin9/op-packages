'use strict';
'require baseclass';
'require ui';

/*
 * luci-theme-shadcnui — menu-shadcnui.js
 *
 * Drop-in replacement for menu-bootstrap / menu-argon. Loads the menu tree via
 * ui.menu.load() and renders it into the sidebar shell that header.ut prepared:
 *
 *   #shadcn-sidebar
 *     .sidebar-header   — brand (rendered server-side)
 *     #shadcn-mainmenu  — primary nav (we fill this)
 *     #shadcn-modemenu  — secondary "mode" tabs (we fill this when there are >1)
 *   #shadcn-topbar
 *     #shadcn-breadcrumb — current path (we fill this)
 *   #tabmenu              — page-local sub-tabs (we fill this when active)
 *
 * The menu has 3 conceptual layers:
 *   level 0  — modes  (Status / System / Network / Services / ...)
 *              In bootstrap these go into #modemenu; in our layout we only
 *              switch the sidebar's main pane based on the active mode.
 *   level 1  — sections of the active mode  (e.g. under "System": System /
 *              Administration / Software / Startup / ...)
 *   level 2  — leaves; clicking them dispatches a view
 *   level 3+ — page-local sub-tabs, rendered into #tabmenu by tabmenu code.
 *
 * Layout:
 *   - The first mode's children become collapsible sections in the sidebar.
 *   - Other modes are listed at the bottom of the sidebar (#shadcn-modemenu)
 *     as small chips so the user can switch.
 */

/* --------------- Lucide icon paths by section/page name --------------- */
var ICONS = {
	/* Top-level modes (activeMode children = these section.names) */
	'status':      'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
	'system':      'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065zM15 12a3 3 0 11-6 0 3 3 0 016 0z',
	'services':    'M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01',
	'network':     'M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064',
	'tools':       'M11 4a2 2 0 114 0v1a1 1 0 001 1h3a1 1 0 011 1v3a1 1 0 01-1 1h-1a2 2 0 100 4h1a1 1 0 011 1v3a1 1 0 01-1 1h-3a1 1 0 01-1-1v-1a2 2 0 10-4 0v1a1 1 0 01-1 1H7a1 1 0 01-1-1v-3a1 1 0 00-1-1H4a2 2 0 110-4h1a1 1 0 001-1V7a1 1 0 011-1h3a1 1 0 001-1V4z',
	'logout':      'M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1',

	/* Status submenu items */
	'overview':    'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
	'routes':      'M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7',
	'firewall':    'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
	'iptables':    'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
	'nftables':    'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
	'realtime':    'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
	'processes':   'M4 6h16M4 10h16M4 14h16M4 18h16',
	'logs':        'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
	'syslog':      'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
	'bandwidth':   'M13 7h8m0 0v8m0-8l-8 8-4-4-6 6',
	'mwan3':       'M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',

	/* System submenu */
	'admin':       'M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z',
	'software':    'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4',
	'packages':    'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4',
	'startup':     'M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664zM21 12a9 9 0 11-18 0 9 9 0 0118 0z',
	'crontab':     'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z',
	'leds':        'M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z',
	'flash':       'M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12',
	'reboot':      'M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15',
	'poweroff':    'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636',

	/* Network submenu */
	'interfaces':  'M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
	'wireless':    'M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0',
	'dhcp':        'M9 3H5a2 2 0 00-2 2v4m6-6h10a2 2 0 012 2v4M9 3v18m0 0h10a2 2 0 002-2V9M9 21H5a2 2 0 01-2-2V9m0 0h18',
	'hosts':       'M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10',
	'diagnostics': 'M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z',
	'switch':      'M8 7h12m0 0l-4-4m4 4l-4 4m0 5H4m0 0l4 4m-4-4l4-4',

	/* Services submenu */
	'upnp':        'M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9',
	'vpn':         'M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z',
	'ddns':        'M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9',
	'sqm':         'M13 10V3L4 14h7v7l9-11h-7z',
	'statistics':  'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
	'nlbw':        'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
	'amneziawg':   'M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z',
	'wireguard':   'M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z',
	'aria2':       'M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4',
	'samba':       'M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z',
	'docker':      'M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z',
	'ttyd':        'M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
	'picoclaw':    'M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z',

	/* Fallback */
	'_chevron':    'M9 18l6-6-6-6',
	'_default':    'M4 6h16M4 12h16M4 18h16'
};

function makeSvg(name, cls) {
	var d = ICONS[name] || ICONS['_default'];
	var NS = 'http://www.w3.org/2000/svg';
	var svg = document.createElementNS(NS, 'svg');
	svg.setAttribute('class', cls || 'icon');
	svg.setAttribute('viewBox', '0 0 24 24');  /* camelCase — required for SVG */
	svg.setAttribute('fill', 'none');
	svg.setAttribute('stroke', 'currentColor');
	svg.setAttribute('stroke-width', '1.75');
	svg.setAttribute('stroke-linecap', 'round');
	svg.setAttribute('stroke-linejoin', 'round');
	svg.setAttribute('aria-hidden', 'true');
	var path = document.createElementNS(NS, 'path');
	path.setAttribute('d', d);
	svg.appendChild(path);
	return svg;
}

return baseclass.extend({

	__init__: function () {
		ui.menu.load().then(L.bind(this.render, this));
	},

	render: function (tree) {
		/* LuCI's handleSave/handleApply look for #maincontent to find forms.
		   Wrap the rendered #view inside a #maincontent div if not present. */
		if (!document.getElementById('maincontent')) {
			var view = document.getElementById('view');
			if (view) {
				var mc = document.createElement('div');
				mc.id = 'maincontent';
				view.parentNode.insertBefore(mc, view);
				mc.appendChild(view);
			}
		}

		this.renderModeSwitcher(tree);
		this.renderSidebarForActiveMode(tree);
		this.renderBreadcrumb(tree);
		this.renderTabMenu(tree);
		this.fixApplyDropdown();
	},

	/* Fix LuCI's apply dropdown */
	fixApplyDropdown: function () {},

	/* --------------- Mode switcher (top-level) --------------- */

	renderModeSwitcher: function (tree) {
		var container = document.querySelector('#shadcn-modemenu');
		if (!container) return;

		var children = ui.menu.getChildren(tree);
		if (children.length <= 1) return;

		var requestpath = L.env.requestpath || [];
		var activeName  = requestpath.length ? requestpath[0] : (children[0] && children[0].name);

		container.innerHTML = '';
		children.forEach(function (child) {
			var isActive = (child.name === activeName);
			var a = E('a', {
				'class': 'mode-chip' + (isActive ? ' active' : ''),
				'href':  L.url(child.name)
			}, [ _(child.title) ]);
			container.appendChild(a);
		});
	},

	/* --------------- Sidebar nav for the active mode --------------- */

	renderSidebarForActiveMode: function (tree) {
		var container = document.querySelector('#shadcn-mainmenu');
		if (!container) return;

		var topChildren = ui.menu.getChildren(tree);
		if (topChildren.length === 0) return;

		var requestpath = L.env.requestpath || [];
		var dispatchpath = L.env.dispatchpath || [];

		// Pick the active mode (or first if no path).
		var activeMode = null;
		if (requestpath.length) {
			for (var i = 0; i < topChildren.length; i++) {
				if (topChildren[i].name === requestpath[0]) {
					activeMode = topChildren[i];
					break;
				}
			}
		}
		if (!activeMode) activeMode = topChildren[0];

		container.innerHTML = '';

		var sections = ui.menu.getChildren(activeMode);
		var self = this;

		console.log('[shadcnui] activeMode.name:', activeMode.name);
		sections.forEach(function (section) {
			console.log('[shadcnui] section.name:', section.name, 'title:', section.title);
			var sectionUrl = activeMode.name + '/' + section.name;
			var leaves = ui.menu.getChildren(section);
			var isActiveSection = (dispatchpath[1] === section.name);

			if (leaves.length > 0) {
				// Collapsible section
				var div = E('div', {
					'class': 'sidebar-section',
					'data-open': isActiveSection ? 'true' : 'false'
				});

				var btn = E('button', {
					'class': 'sidebar-toggle' + (isActiveSection ? ' active' : ''),
					'type':  'button',
					'click': ui.createHandlerFn(self, 'handleSectionToggle')
				}, [
					makeSvg(section.name, 'icon'),
					E('span', {}, [ _(section.title) ]),
					makeSvg('_chevron', 'chevron')
				]);

				var childrenWrap = E('div', { 'class': 'sidebar-children' });
				leaves.forEach(function (leaf) {
					var leafUrl = sectionUrl + '/' + leaf.name;
					var isActiveLeaf = (dispatchpath[1] === section.name && dispatchpath[2] === leaf.name);
					var a = E('a', {
						'class': 'sidebar-link' + (isActiveLeaf ? ' active' : ''),
						'href':  L.url(leafUrl)
					}, [ E('span', {}, [ _(leaf.title) ]) ]);
					childrenWrap.appendChild(a);
				});

				div.appendChild(btn);
				div.appendChild(childrenWrap);
				container.appendChild(div);
			}
			else {
				// Direct link
				var a = E('a', {
					'class': 'sidebar-link sidebar-link-top' + (isActiveSection ? ' active' : ''),
					'href':  L.url(sectionUrl)
				}, [
					makeSvg(section.name, 'icon'),
					E('span', {}, [ _(section.title) ])
				]);
				container.appendChild(a);
			}
		});
	},

	handleSectionToggle: function (ev) {
		var btn = ev.currentTarget;
		var section = btn.closest('.sidebar-section');
		if (!section) return;
		var open = section.getAttribute('data-open') === 'true';
		section.setAttribute('data-open', open ? 'false' : 'true');
		ev.preventDefault();
		ev.stopPropagation();
	},

	/* --------------- Breadcrumb in the topbar --------------- */

	renderBreadcrumb: function (tree) {
		var container = document.querySelector('#shadcn-breadcrumb');
		if (!container) return;

		var dispatchpath = L.env.dispatchpath || [];
		if (dispatchpath.length === 0) return;

		var node = tree;
		var crumbs = [];
		var url = '';

		for (var i = 0; i < dispatchpath.length && node; i++) {
			var seg = dispatchpath[i];
			node = node.children && node.children[seg];
			if (!node) break;
			url = url + (url ? '/' : '') + seg;
			crumbs.push({ title: node.title, url: url });
		}

		container.innerHTML = '';
		crumbs.forEach(function (c, idx) {
			if (idx > 0) container.appendChild(E('span', { 'class': 'crumb-sep' }, [ '/' ]));
			if (idx === crumbs.length - 1) {
				container.appendChild(E('span', { 'class': 'crumb-current' }, [ _(c.title) ]));
			} else {
				container.appendChild(E('a', { 'href': L.url(c.url) }, [ _(c.title) ]));
			}
		});
	},

	/* --------------- Page-local sub-tabs in #tabmenu --------------- */

	renderTabMenu: function (tree) {
		var container = document.querySelector('#tabmenu');
		if (!container) return;

		var dispatchpath = L.env.dispatchpath || [];
		if (dispatchpath.length < 3) return;

		var node = tree;
		var url  = '';
		for (var i = 0; i < 3 && node; i++) {
			node = node.children && node.children[dispatchpath[i]];
			url  = url + (url ? '/' : '') + dispatchpath[i];
		}
		if (!node) return;

		this._renderTabLevel(node, url, 0, container);
	},

	_renderTabLevel: function (node, url, level, container) {
		var children = ui.menu.getChildren(node);
		if (children.length === 0) return;

		var ul = E('ul', { 'class': 'cbi-tabmenu' });
		var activeNode = null;

		var dispatchpath = L.env.dispatchpath || [];
		children.forEach(function (child) {
			var isActive = (dispatchpath[3 + level] === child.name);
			var li = E('li', { 'class': isActive ? 'cbi-tab' : 'cbi-tab-disabled' }, [
				E('a', { 'href': L.url(url, child.name) }, [ _(child.title) ])
			]);
			ul.appendChild(li);
			if (isActive) activeNode = child;
		});

		container.appendChild(ul);
		container.style.display = '';

		if (activeNode) {
			this._renderTabLevel(activeNode, url + '/' + activeNode.name, level + 1, container);
		}
	}

});
