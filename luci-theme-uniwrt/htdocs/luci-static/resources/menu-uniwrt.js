'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	__init__: function() {
		ui.menu.load().then(L.bind(this.render, this));
	},

	/* stroke-based 24x24 icon paths keyed by top-level dispatcher node name */
	icons: {
		status:    '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>',
		system:    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09a1.65 1.65 0 00-1-1.51 1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09a1.65 1.65 0 001.51-1 1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z"/>',
		network:   '<circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/>',
		services:  '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
		vpn:       '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0110 0v4"/>',
		nas:       '<line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.45-6.89A2 2 0 0016.76 4H7.24a2 2 0 00-1.79 1.11z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/>',
		storage:   '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>',
		docker:    '<path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/>',
		wireless:  '<path d="M5 12.55a11 11 0 0114 0"/><path d="M1.42 9a16 16 0 0121.16 0"/><path d="M8.53 16.11a6 6 0 016.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/>',
		firewall:  '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
		dhcp:      '<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 7V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v2"/>',
		routing:   '<circle cx="6" cy="19" r="3"/><circle cx="18" cy="5" r="3"/><path d="M6 16V8a4 4 0 014-4h4"/><path d="M18 8v8a4 4 0 01-4 4h-4"/>',
		statistics:'<path d="M3 3v18h18"/><rect x="7" y="12" width="3" height="6"/><rect x="12" y="8" width="3" height="10"/><rect x="17" y="5" width="3" height="13"/>',
		logout:    '<path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
		'uniwrt-netmap': '<circle cx="12" cy="5" r="2.5"/><circle cx="5" cy="19" r="2.5"/><circle cx="19" cy="19" r="2.5"/><path d="M12 7.5v4.5M12 12l-5.4 4.8M12 12l5.4 4.8"/>',
		uniwrt:    '<polyline points="3 9 9 9 9 3"/><polyline points="21 15 15 15 15 21"/><line x1="9" y1="9" x2="3" y2="3"/><line x1="21" y1="21" x2="15" y2="15"/>',
		_default:  '<circle cx="12" cy="12" r="9"/><line x1="12" y1="8" x2="12" y2="13"/><line x1="12" y1="16" x2="12.01" y2="16"/>'
	},

	/* fuzzy match: exact name, else first key that the name contains / contained-by */
	iconKey: function(name) {
		if (this.icons[name]) return name;
		name = String(name || '').toLowerCase();
		var keys = ['status','system','network','services','wireless','firewall','routing',
		            'statistics','vpn','storage','nas','docker','dhcp','overview','logout'];
		for (var i = 0; i < keys.length; i++)
			if (name.indexOf(keys[i]) >= 0) return keys[i];
		if (name.indexOf('uniwrt') >= 0) return 'uniwrt';
		return '_default';
	},

	getIcon: function(name) {
		var path = this.icons[this.iconKey(name)] || this.icons._default;
		var markup = '<svg xmlns="http://www.w3.org/2000/svg" class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + path + '</svg>';
		var doc = new DOMParser().parseFromString(markup, 'image/svg+xml');
		return document.importNode(doc.documentElement, true);
	},

	/* let the browser handle Ctrl/Cmd/Shift/Alt and non-primary clicks
	   (open in new tab/window) instead of animating a same-tab navigation */
	plainClick: function(ev) {
		return ev.button === 0 && !ev.ctrlKey && !ev.metaKey && !ev.shiftKey && !ev.altKey;
	},

	render: function(tree) {
		var nav = document.getElementById('u-rail-nav');
		if (!nav) return;
		nav.innerHTML = '';

		/* On real devices the loaded tree's root wraps everything in a single
		   'admin' node, so getChildren(root) returns just ['admin'] and the
		   category switcher never populated (top.length > 1 was false). Descend
		   into 'admin' so the actual categories (Status/System/Network/...)
		   become the modes; keep the base for links and active-path checks. */
		var base = (tree && tree.children && tree.children.admin) ? 'admin' : '';
		var root = base ? tree.children.admin : tree;
		var idx  = base ? 1 : 0;   /* category position within requestpath */
		var top  = ui.menu.getChildren(root);

		/* Expanded sidebar keeps the ORIGINAL single accordion tree: all
		   categories listed, the active one opening its sub-items inline.
		   (The category switcher below is populated too, but it is only
		   DISPLAYED while the rail is collapsed — as the icon column.) */
		if (base) {
			this.renderSidebar(nav, root, base);
		} else {
			for (var i = 0; i < top.length; i++) {
				var active = (L.env.requestpath.length > idx) ? top[i].name == L.env.requestpath[idx] : i == 0;
				if (active) this.renderSidebar(nav, top[i], top[i].name);
			}
		}

		/* category icon column (visible only when the rail is collapsed) */
		if (top.length > 1) this.renderModes(top, base, idx);

		/* page title in the topbar */
		this.renderTitle(tree);

		/* third-level tab menu into the sticky sub-nav */
		if (L.env.dispatchpath.length >= 3) {
			var node = tree, url = '';
			for (var j = 0; j < 3 && node; j++) {
				node = node.children[L.env.dispatchpath[j]];
				url = url + (url ? '/' : '') + L.env.dispatchpath[j];
			}
			if (node) this.renderSubnav(node, url);
		}
	},

	renderTitle: function(tree) {
		var el = document.getElementById('u-top-title');
		if (!el) return;
		var node = tree, title = '';
		for (var i = 0; i < L.env.dispatchpath.length && node; i++) {
			node = node.children[L.env.dispatchpath[i]];
			if (node && node.title) title = node.title;
		}
		el.textContent = title ? _(title) : '';
	},

	renderModes: function(top, base, idx) {
		var box = document.getElementById('u-rail-modes');
		if (!box) return;
		box.innerHTML = '';
		/* The Overview entry is always registered server-side; its visibility is
		   controlled live here from the current setting (data-uniwrt-overview),
		   because LuCI bakes menu uci-depends into its cached index and would not
		   react to the toggle until the cache is cleared. */
		var hideOverview = document.documentElement.getAttribute('data-uniwrt-overview') === '0';
		for (var i = 0; i < top.length; i++) {
			var c = top[i];
			if (hideOverview && c.name === 'uniwrt-overview') continue;
			var active = (L.env.requestpath.length > (idx || 0)) ? c.name == L.env.requestpath[idx || 0] : i == 0;
			var a = E('a', {
				'class': 'u-mode-tab' + (active ? ' active' : ''),
				'href': base ? L.url(base, c.name) : L.url(c.name),
				'data-name': c.name,
				'title': _(c.title)
			}, [ E('span', { 'class': 'u-mode-label' }, [ _(c.title) ]) ]);
			a.insertBefore(this.getIcon(c.name), a.firstChild);
			box.appendChild(a);
		}
	},

	/* Menu entries another installed theme adds for itself (CleanX's Network
	   Map and System -> CleanX Theme) belong to that theme and only matter
	   while it is active. Leave them out at every level, so UniWRT shows one
	   Network Map and its own settings page; CleanX does the same for
	   UniWRT's entries. */
	visibleChildren: function(tree) {
		return ui.menu.getChildren(tree).filter(function(c) { return !/^cleanx(-|$)/.test(c.name); });
	},

	renderSidebar: function(container, tree, url) {
		var children = this.visibleChildren(tree);
		if (!children.length) return;
		var group = E('div', { 'class': 'u-nav-group' });
		var self = this;

		var hideOverview = document.documentElement.getAttribute('data-uniwrt-overview') === '0';
		/* "Expand all menu sections" setting: every category starts open;
		   otherwise only the one holding the current page */
		var expandAll = document.documentElement.getAttribute('data-uniwrt-menu') === 'expanded';
		if (expandAll) group.classList.add('u-all-open');
		for (var i = 0; i < children.length; i++) {
			var child = children[i];
			if (hideOverview && child.name === 'uniwrt-overview') continue;
			var subs = this.visibleChildren(child);
			var hasSubs = subs.length > 0;
			var current = L.env.dispatchpath[1] == child.name;
			var open = current || (expandAll && hasSubs);
			var linkUrl = hasSubs ? L.url(url, child.name, subs[0].name) : L.url(url, child.name);

			var item = E('a', {
				'class': 'u-nav-item' + (open ? ' open' : '') + (current ? ' current' : ''),
				'href': linkUrl,
				'data-name': child.name
			}, [ E('span', { 'class': 'u-nav-label' }, [ _(child.title) ]) ]);
			item.insertBefore(this.getIcon(child.name), item.firstChild);

			if (hasSubs)
				item.appendChild(E('svg', { 'class': 'u-nav-arrow', 'viewBox': '0 0 24 24', 'fill': 'none', 'stroke': 'currentColor', 'stroke-width': '2.4' },
					[ E('polyline', { 'points': '9 18 15 12 9 6' }) ]));

			group.appendChild(item);

			if (hasSubs) {
				var sub = E('div', { 'class': 'u-nav-sub' + (open ? ' open' : '') });
				var slider = E('span', { 'class': 'u-nav-slider' });
				sub.appendChild(slider);

				for (var j = 0; j < subs.length; j++) {
					var s = subs[j];
					var subActive = current && L.env.dispatchpath[2] == s.name;
					var subItem = E('a', {
						'class': 'u-nav-item' + (subActive ? ' active' : ''),
						'href': L.url(url, child.name, s.name)
					}, [ E('span', { 'class': 'u-nav-label' }, [ _(s.title) ]) ]);

					(function(el, sl) {
						el.addEventListener('click', function(ev) {
							if (!self.plainClick(ev)) return;
							ev.preventDefault();
							var prev = el.parentNode.querySelector('.u-nav-item.active');
							if (prev) prev.classList.remove('active');
							el.classList.add('active');
							sl.style.top = el.offsetTop + 'px';
							sl.style.height = el.offsetHeight + 'px';
							sl.style.opacity = '1';
							document.body.classList.add('page-leaving');
							setTimeout(function() { window.location.href = el.href; }, 170);
						});
					})(subItem, slider);

					sub.appendChild(subItem);
				}

				(function(sm, sl) {
					requestAnimationFrame(function() {
						var a = sm.querySelector('.u-nav-item.active');
						if (!a) return;
						sl.style.transition = 'none';
						sl.style.top = a.offsetTop + 'px';
						sl.style.height = a.offsetHeight + 'px';
						sl.style.opacity = '1';
						requestAnimationFrame(function() { sl.style.transition = ''; });
					});
				})(sub, slider);

				group.appendChild(sub);

				(function(navItem, subEl) {
					navItem.addEventListener('click', function(ev) {
						ev.preventDefault();
						var isOpen = subEl.classList.toggle('open');
						navItem.classList.toggle('open', isOpen);
					});
				})(item, sub);
			}
		}
		container.appendChild(group);
	},

	renderSubnav: function(tree, url) {
		var bar = document.getElementById('u-subnav');
		if (!bar) return;
		var children = this.visibleChildren(tree);
		if (!children.length) return;

		bar.innerHTML = '';
		var slider = E('span', { 'class': 'u-subnav-slider' });
		bar.appendChild(slider);

		for (var i = 0; i < children.length; i++) {
			var c = children[i];
			var active = L.env.dispatchpath[3] == c.name;
			bar.appendChild(E('a', {
				'class': 'u-subnav-tab' + (active ? ' active' : ''),
				'href': L.url(url, c.name),
				'data-tree': '1'
			}, [ _(c.title) ]));
		}

		bar.classList.add('active');
		document.body.classList.add('u-has-subnav');

		var self = this;
		var tabs = bar.querySelectorAll('.u-subnav-tab');
		for (var k = 0; k < tabs.length; k++) {
			(function(tab) {
				tab.addEventListener('click', function(ev) {
					if (!self.plainClick(ev)) return;
					ev.preventDefault();
					var prev = bar.querySelector('.u-subnav-tab.active');
					if (prev) prev.classList.remove('active');
					tab.classList.add('active');
					slider.style.left = tab.offsetLeft + 'px';
					slider.style.width = tab.offsetWidth + 'px';
					slider.style.opacity = '1';
					document.body.classList.add('page-leaving');
					var href = tab.href;
					setTimeout(function() { window.location.href = href; }, 160);
				});
			})(tabs[k]);
		}

		requestAnimationFrame(function() {
			var a = bar.querySelector('.u-subnav-tab.active');
			if (!a) return;
			slider.style.transition = 'none';
			slider.style.left = a.offsetLeft + 'px';
			slider.style.width = a.offsetWidth + 'px';
			slider.style.opacity = '1';
			requestAnimationFrame(function() { slider.style.transition = ''; });
		});
	}
});
