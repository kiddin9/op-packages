'use strict';
'require baseclass';
'require ui';
'require poll';
'require 7dollar.common as td';
'require 7dollar.tidy as tidy';

/*
 * Navigation for the 7Dollar theme.
 * Native LuCI pages are regrouped into seven plain-language sections;
 * anything unknown falls back to "Apps" so third-party plugins always show up.
 */

const T = td.T, icon = td.icon, esc = td.esc;
const mqPhone = window.matchMedia('(max-width:760px)');

return baseclass.extend({
	__init__() {
		td.loadMenu().then(L.bind(this.render, this));
		this.bindKeys();
		this.bindMode();
		this.bindVisibility();
	},

	/* Every LuCI page refreshes through one shared poll loop; stop it while the tab is hidden so a
	 * forgotten tab costs the router nothing. Coming back restarts it, which refreshes at once. */
	bindVisibility() {
		let paused = false;
		document.addEventListener('visibilitychange', () => {
			if (document.hidden) {
				if (poll.active()) { poll.stop(); paused = true; }
			}
			else if (paused) {
				paused = false;
				poll.start();
			}
		});
	},

	render(tree) {
		const pages = td.flatten(tree);
		const groups = td.grouped(pages);
		const here = L.env.dispatchpath.join('/');
		let current = null;

		pages.forEach(p => {
			if ((here == p.path || here.indexOf(p.path + '/') == 0) && (!current || p.path.length > current.path.length))
				current = p;
		});

		this.pages = pages;
		this.groups = groups;
		this.current = current;

		this.renderNav(groups, current);
		this.renderPills(groups, current);

		if (current)
			this.renderTabs(current.node, current.path, current.path.split('/').length);

		const btn = document.getElementById('td-search');
		if (btn) btn.addEventListener('click', () => this.openSearch());
	},

	href(group) {
		const first = group.list[0];
		return L.url(first.path);
	},

	renderNav(groups, current) {
		const nav = document.getElementById('td-nav');
		if (!nav) return;

		nav.innerHTML = groups.map((g, i) => {
			const on = current && current.group == g.id;
			const short = g.short ? `<span class="lbl has-short">${esc(g.label)}</span><span class="short">${esc(g.short)}</span>`
			                      : `<span class="lbl">${esc(g.label)}</span>`;
			return `<a href="${this.href(g)}" data-g="${g.id}" title="${esc(g.label)}" class="${on ? 'on' : ''}${g.mob === false ? ' mob-hide' : ''}" style="animation-delay:${i * 25}ms">${icon(g.icon)}${short}</a>`;
		}).join('');

		const sys = nav.querySelector('[data-g="system"]');
		if (sys)
			sys.addEventListener('click', ev => {
				if (!mqPhone.matches) return;
				ev.preventDefault();
				this.openSheet();
			});
	},

	renderPills(groups, current) {
		const box = document.getElementById('td-pills');
		if (!box || !current) return;

		const g = groups.find(x => x.id == current.group);
		let items = [];

		if (g.id == 'apps') {
			if (current.path == 'admin/apps') return;
			const all = g.list.find(p => p.path == 'admin/apps');
			if (all)
				box.innerHTML = `<a class="back" href="${L.url(all.path)}">${icon('chev')}${esc(all.title)}</a>`;
			box.innerHTML += `<a class="on" href="${L.url(current.path)}">${esc(current.title)}</a>`;
			return;
		}

		items = g.list;
		if (items.length < 2) return;

		/* everyday pages first; the rest wait behind "More" unless one of them is open */
		const pill = (p, cls) => `<a href="${L.url(p.path)}" class="${p === current ? 'on' : cls || ''}">${esc(p.title)}</a>`;
		const rest = items.filter(p => g.pages.indexOf(p.path) < 0);
		const fold = rest.length > 1 && rest.indexOf(current) < 0;
		box.innerHTML = (fold ? items.filter(p => rest.indexOf(p) < 0) : items).map(p => pill(p)).join('')
			+ (fold ? `<a href="#" role="button" class="fold">${esc(T('更多', 'More'))}${icon('chev')}</a>` : '');
		if (fold)
			box.lastChild.addEventListener('click', ev => {
				ev.preventDefault();
				ev.currentTarget.outerHTML = rest.map(p => pill(p, 'td-in')).join('');
				edge();
			});
		const on = box.querySelector('.on');
		if (on && on.scrollIntoView) box.scrollLeft = Math.max(0, on.offsetLeft - 40);

		const edge = () => {
			box.classList.toggle('scrolls', box.scrollWidth > box.clientWidth + 2);
			box.classList.toggle('end', box.scrollLeft + box.clientWidth >= box.scrollWidth - 2);
		};
		box.addEventListener('scroll', edge, { passive: true });
		window.addEventListener('resize', edge);
		edge();
	},

	renderTabs(node, url, level) {
		const container = document.getElementById('tabmenu');
		const children = ui.menu.getChildren(node);

		if (!container || !children.length) return;

		const ul = E('ul', { 'class': 'tabs' });
		let active = null;

		children.forEach(child => {
			const isActive = (L.env.dispatchpath[level] == child.name);
			ul.appendChild(E('li', { 'class': 'tabmenu-item-%s%s'.format(child.name, isActive ? ' active' : '') }, [
				E('a', { 'href': L.url(url, child.name) }, [ _(child.title) ])
			]));
			if (isActive) active = child;
		});

		container.appendChild(ul);
		container.style.display = '';

		if (active)
			this.renderTabs(td.realNode(node, active), url + '/' + active.name, level + 1);
	},

	/* ---------- search (⌘K) ---------- */

	entries() {
		if (this._entries) return this._entries;
		const out = [];
		(this.groups || []).forEach(g => g.list.forEach(p => {
			out.push({ path: p.path, title: p.title, group: g.label, icon: g.icon, en: p.node.title || '' });
			ui.menu.getChildren(p.node).forEach(c => out.push({
				path: p.path + '/' + c.name, title: p.title + ' · ' + _(c.title), group: g.label, icon: g.icon, en: c.title || ''
			}));
		}));
		return (this._entries = out);
	},

	openSearch() {
		if (document.querySelector('.td-pop:not(.td-out)')) return;

		const pop = td.html(`<div class="td-pop" role="dialog" aria-modal="true">
			<div class="td-pop-box">
				<label class="td-pop-in">${icon('search')}<input type="search" placeholder="${esc(T('搜索功能或设置，例如“端口转发”', 'Search pages and settings'))}" autocomplete="off"><kbd>Esc</kbd></label>
				<div class="td-pop-list"></div>
			</div></div>`);
		document.body.appendChild(pop);

		const input = pop.querySelector('input'), list = pop.querySelector('.td-pop-list');
		const all = this.entries();
		let sel = 0, shown = [];

		const draw = () => {
			const q = input.value.trim().toLowerCase();
			shown = !q ? all.filter(e => e.path.split('/').length <= 3).slice(0, 40)
			           : all.filter(e => (e.title + ' ' + e.en + ' ' + e.group + ' ' + e.path).toLowerCase().indexOf(q) > -1).slice(0, 40);
			sel = Math.min(sel, Math.max(0, shown.length - 1));
			list.innerHTML = shown.length ? shown.map((e, i) =>
				`<a href="${L.url(e.path)}" class="${i == sel ? 'on' : ''}" data-i="${i}">${icon(e.icon)}<span>${esc(e.title)}</span><small>${esc(e.group)}</small></a>`).join('')
				: `<div class="td-pop-empty">${esc(T('没有找到相关功能', 'Nothing found'))}</div>`;
			const on = list.querySelector('.on');
			if (on) on.scrollIntoView({ block: 'nearest' });
		};

		const close = () => td.leave(pop);

		input.addEventListener('input', () => { sel = 0; draw() });
		input.addEventListener('keydown', ev => {
			if (ev.key == 'ArrowDown') { sel = Math.min(sel + 1, shown.length - 1); draw(); ev.preventDefault() }
			else if (ev.key == 'ArrowUp') { sel = Math.max(sel - 1, 0); draw(); ev.preventDefault() }
			else if (ev.key == 'Enter' && shown[sel]) { location.href = L.url(shown[sel].path) }
			else if (ev.key == 'Escape') close();
		});
		list.addEventListener('mousemove', ev => {
			const a = ev.target.closest('a[data-i]');
			if (a && +a.dataset.i != sel) { sel = +a.dataset.i; list.querySelectorAll('a').forEach(x => x.classList.toggle('on', x === a)) }
		});
		pop.addEventListener('click', ev => { if (ev.target === pop) close() });

		draw();
		input.focus();
	},

	/* ---------- phone: "More" sheet ---------- */

	openSheet() {
		if (document.querySelector('.td-pop:not(.td-out)')) return;

		const rest = (this.groups || []).filter(g => g.mob === false || g.id == 'system');
		const body = rest.map(g => `<div class="grp">${esc(g.label)}</div>` +
			g.list.map(p => `<a href="${L.url(p.path)}" class="${this.current === p ? 'on' : ''}">${icon(g.id == 'apps' ? td.appIcon(p.path) : g.icon)}<span>${esc(p.title)}</span></a>`).join('')).join('');

		const pop = td.html(`<div class="td-pop" role="dialog" aria-modal="true"><div class="td-pop-box">
			<div class="td-pop-list">${body}</div>
			<div class="td-sheet-tools">
				<button class="btn" type="button" data-act="search">${icon('search')}${esc(T('搜索', 'Search'))}</button>
				<button class="btn" type="button" data-act="mode">${icon('moon')}${esc(T('深浅色', 'Theme'))}</button>
				<a class="btn" href="${L.url('admin/logout')}">${icon('logout')}${esc(T('退出', 'Log out'))}</a>
			</div></div></div>`);

		document.body.appendChild(pop);
		pop.addEventListener('click', ev => {
			const b = ev.target.closest('[data-act]');
			if (ev.target === pop) td.leave(pop);
			else if (b && b.dataset.act == 'search') { pop.remove(); this.openSearch() }
			else if (b && b.dataset.act == 'mode') this.toggleMode();
		});
	},

	/* ---------- keyboard & dark mode ---------- */

	bindKeys() {
		const kbd = document.querySelector('.td-search kbd');
		if (kbd && !/Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent)) kbd.textContent = 'Ctrl K';

		document.addEventListener('keydown', ev => {
			const typing = /^(INPUT|TEXTAREA|SELECT)$/.test((ev.target || {}).tagName || '') || (ev.target || {}).isContentEditable;
			if ((ev.key == 'k' || ev.key == 'K') && (ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); this.openSearch() }
			else if (ev.key == '/' && !typing && !document.body.classList.contains('modal-overlay-active')) { ev.preventDefault(); this.openSearch() }
		});
	},

	bindMode() {
		const btn = document.getElementById('td-mode');
		const sync = () => {
			if (!btn) return;
			const dark = document.documentElement.getAttribute('data-theme') == 'dark';
			btn.innerHTML = icon(dark ? 'sun' : 'moon');
			btn.title = dark ? T('切换到浅色', 'Light mode') : T('切换到深色', 'Dark mode');
		};

		if (btn) btn.addEventListener('click', () => this.toggleMode());
		document.addEventListener('td-look', sync);
		matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
			if (document.documentElement.getAttribute('data-mode') == 'auto')
				td.applyLook({ palette: document.documentElement.getAttribute('data-palette'), mode: 'auto' });
		});
		sync();
	},

	toggleMode() {
		const r = document.documentElement;
		const mode = r.getAttribute('data-theme') == 'dark' ? 'light' : 'dark';
		td.applyLook({ palette: r.getAttribute('data-palette') || 'clay', mode: mode });
		td.saveSettings({ mode: mode }).catch(() => {});
	}
});
