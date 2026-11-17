'use strict';
'require baseclass';
'require fs';
'require ui';

/*
 * System -> Software (luci-app-package-manager): an "Upgrade all" button on
 * the Updates tab. Loaded only on that page.
 *
 * It runs the page's own helper without package names
 * (`package-manager-call upgrade`, i.e. `apk upgrade`), the same command and
 * permission LuCI already uses for single-package upgrades — nothing new runs
 * as root. Offered only with apk (OpenWrt 25.12+): with opkg, upgrading every
 * package is the case OpenWrt warns can break a router.
 */

var HELPER = '/usr/libexec/package-manager-call';

function q(sel) { return document.querySelector(sel); }

return baseclass.extend({
	__init__: function() {
		/* the feature list loads asynchronously: ask for it rather than
		   reading it before it has arrived */
		var self = this;
		L.resolveDefault(L.probeSystemFeatures(), {}).then(function(features) {
			if ((features || {}).apk)
				self.waitForPage();
		});
	},

	/* the page renders asynchronously; wait (max ~20 s) for its controls */
	waitForPage: function() {
		var self = this, tries = 0;
		(function find() {
			var upd = q('#view button[data-command="update"]'),
			    tabs = q('#view .cbi-tabmenu.mode'),
			    table = q('#view #packages');
			if (upd && tabs && table)
				return self.setup(upd, tabs, table);
			if (++tries < 100)
				window.setTimeout(find, 200);
		})();
	},

	setup: function(upd, tabs, table) {
		var self = this;
		this.btn = E('button', {
			'class': 'btn cbi-button-action',
			'style': 'display:none',
			'click': ui.createHandlerFn(this, 'confirm')
		}, [ _('Upgrade all…') ]);
		upd.parentNode.insertBefore(this.btn, upd.nextSibling);
		upd.parentNode.insertBefore(document.createTextNode(' '), this.btn);

		var queued = false, sync = function() {
			if (queued) return;
			queued = true;
			window.requestAnimationFrame(function() { queued = false; self.sync(); });
		};
		new MutationObserver(sync).observe(table, { childList: true, subtree: true });
		tabs.addEventListener('click', sync);
		sync();
	},

	/* number of upgradable packages, or 0 when the Updates tab isn't showing any */
	count: function() {
		var tab = q('#view .cbi-tabmenu.mode li.cbi-tab');
		if (!tab || tab.getAttribute('data-mode') !== 'updates')
			return 0;
		var shown = document.querySelectorAll('#packages [data-action="upgrade"]').length;
		if (!shown)
			return 0;
		/* the list is paged (100 per page); with no filter, the pager has the total */
		var filter = q('#view input[name="filter"]'),
		    pager = q('#view .controls > .pager .text'),
		    m = (!filter || !filter.value) && pager ? pager.textContent.match(/(\d+)\D*$/) : null;
		return m ? Math.max(shown, +m[1]) : shown;
	},

	sync: function() {
		var n = this.count(), filtered = !!(q('#view input[name="filter"]') || {}).value;
		this.btn.style.display = n ? '' : 'none';
		this.btn.firstChild.data = (n && !filtered) ? _('Upgrade all (%d)…').format(n) : _('Upgrade all…');
		this.n = filtered ? null : n;
	},

	confirm: function() {
		var self = this;
		ui.showModal(_('Upgrade all packages'), [
			E('p', {}, this.n
				? _('This upgrades all %d packages listed under Updates, using <em>apk upgrade</em>.').format(this.n)
				: _('This upgrades every installed package that has a newer version, using <em>apk upgrade</em>.')),
			E('p', {}, _('Run <em>Update lists…</em> first so the newest versions are known. Upgrading many packages at once can take a few minutes; keep this page open until it finishes. Installing a new firmware image (for example with Attended Sysupgrade) is still the most reliable way to update the whole system.')),
			E('p', {}, E('a', { 'href': 'https://openwrt.org/meta/infobox/upgrade_packages_warning', 'target': '_blank', 'rel': 'noreferrer' },
				_('OpenWrt’s notes on upgrading packages'))),
			E('div', { 'class': 'button-row' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Cancel') ]), ' ',
				E('button', { 'class': 'btn cbi-button-positive', 'click': function() { self.run(); } }, [ _('Upgrade all') ])
			])
		]);
	},

	run: function() {
		var dlg = ui.showModal(_('Upgrading all packages'), [
			E('p', { 'class': 'spinning' }, _('Waiting for <em>apk upgrade</em> to complete…'))
		]);
		var done = function(nodes) {
			while (dlg.lastChild) dlg.removeChild(dlg.lastChild);
			nodes.forEach(function(n) { if (n) dlg.appendChild(n); });
			dlg.appendChild(E('div', { 'class': 'button-row' }, E('button', { 'class': 'btn', 'click': function() {
				if (ui.menu && ui.menu.flushCache) ui.menu.flushCache();
				ui.hideModal();
				window.location.reload();   /* the page reloads its package lists */
			} }, [ _('Dismiss') ])));
		};

		return fs.exec_direct(HELPER, [ 'upgrade' ], 'json').then(function(res) {
			res = res || {};
			done([
				res.pkmcmd ? E('pre', {}, [ res.pkmcmd ]) : null,
				res.stdout ? E('pre', {}, [ res.stdout ]) : null,
				res.stderr ? E('h5', {}, [ _('Errors') ]) : null,
				res.stderr ? E('pre', { 'class': 'errors' }, [ res.stderr ]) : null,
				E('p', {}, res.code === 0 ? _('All packages were upgraded.')
					: _('<em>apk upgrade</em> failed with code <code>%d</code>.').format((res.code & 0xff) || -1))
			]);
		}).catch(function(err) {
			done([ E('p', {}, _('Unable to run <em>apk upgrade</em>: %s').format(err)) ]);
		});
	}
});
