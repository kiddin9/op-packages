'use strict';
'require view';
'require fs';
'require ui';
'require dom';

const localFile = '/etc/banip/banip.blocklist';
const maxSize = 100000;

const resetScroll = () => {
	document.body.scrollTop = document.documentElement.scrollTop = 0;
};

/* Regex definitions for validation */
const ipv4Regex = /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
const cidrRegex = /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\/([0-9]|[12][0-9]|3[0-2]))$/;
const ipv6Regex = /^([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}(\/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]))?$|^::1$|^([0-9a-fA-F]{1,4}:){1,7}:(\/([0-9]|[1-9][0-9]|1[0-1][0-9]|12[0-8]))?$/;
const macRegex = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
const domainRegex = /^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/;
const macIpBindingRegex = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\s+((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;

function isValidRule(token) {
	return macRegex.test(token) || cidrRegex.test(token) || ipv4Regex.test(token) ||
		macIpBindingRegex.test(token) || ipv6Regex.test(token) || domainRegex.test(token);
}

function parseBlocklist(text) {
	const lines = (text || '').split('\n');
	const items = [];
	lines.forEach(function (raw, idx) {
		const line = raw.trim();
		if (!line || line.startsWith('#')) return;
		const parts = line.split(/\s+#\s*(.*)$/);
		const main = parts[0].trim();
		const comment = parts[1] ? parts[1].trim() : '';
		items.push({ id: idx, value: main, comment: comment, raw: line });
	});
	return items;
}

function serializeBlocklist(items) {
	return items.map(function (item) {
		return item.comment ? `${item.value} # ${item.comment}` : item.value;
	}).join('\n') + '\n';
}

return view.extend({
	rawContent: '',
	isRawMode: false,
	items: [],

	load: function () {
		return L.resolveDefault(fs.stat(localFile), null)
			.then(function (stat) {
				if (!stat) {
					return fs.write(localFile, "").then(() => [{ size: 0 }, ""]);
				}
				return Promise.all([
					Promise.resolve(stat),
					L.resolveDefault(fs.read_direct(localFile), "")
				]);
			});
	},

	render: function (blocklist) {
		const size = blocklist[0] ? blocklist[0].size : 0;
		this.rawContent = blocklist[1] != null ? blocklist[1] : '';
		const tooBig = size >= maxSize;
		const self = this;

		this.items = parseBlocklist(this.rawContent);

		if (tooBig) {
			resetScroll();
			ui.addNotification(null, E('p', _('The blocklist is too big, raw editor mode enforced.')), 'error');
			this.isRawMode = true;
		}

		const mainContainer = E('div', { 'class': 'cbi-map' });

		function syncAndRebuild() {
			self.rawContent = serializeBlocklist(self.items);
			renderContainer();
		}

		/*
			1. Unified Blocklist Table (Pure OpenWrt Native)
		*/
		function renderTable() {
			const rows = self.items.map(function (item, index) {
				return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((index % 2) ? 2 : 1) }, [
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important; font-family: monospace;' }, [item.value]),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important;' }, [item.comment || '-']),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: right !important;' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-remove',
							'title': _('Delete and unblock this rule'),
							'click': function () {
								self.items.splice(index, 1);
								syncAndRebuild();
							}
						}, [_('Delete')])
					])
				]);
			});

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Blocklist Entries')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr cbi-section-table-titles' }, [
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 45%; text-align: left !important;' }, [_('Blocked Address / Domain / Network')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 40%; text-align: left !important;' }, [_('Comment / Source')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 15%; text-align: right !important;' }, [_('Action')])
						]),
						E('tbody', {}, rows.length ? rows : [
							E('tr', { 'class': 'tr cbi-section-table-row' }, [
								E('td', { 'colspan': 3, 'class': 'td cbi-section-table-cell', 'style': 'text-align: center !important; color: #888; padding: 2em;' },
									[_('Currently no blocked entries. Add one below.')])
							])
						])
					])
				])
			]);
		}

		/*
			2. Quick Add Bar (Pure OpenWrt Native)
		*/
		function renderQuickAdd() {
			const valInput = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'placeholder': _('e.g. 198.51.100.1, 203.0.113.0/24, or malicious-site.com')
			});

			const commentInput = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'placeholder': _('Optional comment (e.g. Malicious Bot)')
			});

			function doAdd() {
				const val = valInput.value.trim();
				const cmt = commentInput.value.trim();
				if (!val) {
					ui.addNotification(null, E('p', _('Please specify a valid IP, CIDR, Domain or MAC address.')), 'warning');
					valInput.focus();
					return;
				}
				if (/[\s#]/.test(val)) {
					ui.addNotification(null, E('p', _('Format invalid: "%s" is not a valid address without spaces.').format(val)), 'error');
					return;
				}

				self.items.unshift({ id: Date.now(), value: val, comment: cmt, raw: val });
				valInput.value = '';
				commentInput.value = '';
				syncAndRebuild();
				ui.addNotification(null, E('p', _('Added blocklist entry "%s".').format(val)), 'info');
			}

			valInput.addEventListener('keydown', function (ev) {
				if (ev.key === 'Enter') doAdd();
			});
			commentInput.addEventListener('keydown', function (ev) {
				if (ev.key === 'Enter') doAdd();
			});

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Quick Add Block Rule')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr cbi-section-table-titles' }, [
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 45%; text-align: left !important;' }, [_('Address or Domain')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 40%; text-align: left !important;' }, [_('Comment / Source')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 15%; text-align: right !important;' }, [_('Action')])
						]),
						E('tr', { 'class': 'tr cbi-section-table-row' }, [
							E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important;' }, [valInput]),
							E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important;' }, [commentInput]),
							E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: right !important;' }, [
								E('button', {
									'class': 'btn cbi-button cbi-button-add',
									'click': doAdd
								}, [_('Add Rule')])
							])
						])
					])
				])
			]);
		}

		/*
			3. Raw Textarea Editor
		*/
		function renderRawEditor() {
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Raw Text Editor')),
				E('div', { 'class': 'cbi-section-descr' }, [
					_('One record per line. Supports IPv4, IPv6, CIDR, MAC, Domain and comments starting with "#".')
				]),
				E('div', { 'class': 'cbi-section-node' }, [
					E('textarea', {
						'id': 'blocklist-raw-textarea',
						'class': 'cbi-input-textarea',
						'style': 'width: 100%; height: 480px; font-family: monospace; resize: vertical;',
						'spellcheck': 'false',
						'wrap': 'off',
						'input': function () {
							self.rawContent = this.value;
						}
					}, [self.rawContent || ''])
				])
			]);
		}

		/*
			Assemble Container
		*/
		function renderContainer() {
			dom.content(mainContainer, [
				E('h2', { 'name': 'content' }, [_('SecBox Blocklist')]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('Manage locally blocked IP addresses, CIDR ranges, MAC addresses or domains.')
				]),
				E('div', { 'style': 'margin-bottom: 1em; text-align: right;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-neutral',
						'click': function () {
							if (self.isRawMode) {
								self.items = parseBlocklist(self.rawContent);
								self.isRawMode = false;
							} else {
								self.rawContent = serializeBlocklist(self.items);
								self.isRawMode = true;
							}
							renderContainer();
						}
					}, [self.isRawMode ? _('Switch to Table View') : _('Switch to Raw Text Editor')])
				]),
				self.isRawMode
					? renderRawEditor()
					: E('div', {}, [
						renderQuickAdd(),
						renderTable()
					])
			]);
		}

		renderContainer();
		return mainContainer;
	},

	handleSaveApply: function (ev, mode) {
		return this.handleSave(ev).then(function () {
			ui.showIndicator('banip-action', _('Reloading SecBox service...'));
			return fs.exec_direct('/etc/init.d/banip', ['reload'])
				.then(function () {
					ui.hideIndicator('banip-action');
					ui.addNotification(null, E('p', _('Blocklist saved and SecBox service reloaded successfully!')), 'info');
				})
				.catch(function (e) {
					ui.hideIndicator('banip-action');
					ui.addNotification(null, E('p', _('Saved blocklist, but failed to reload SecBox: %s').format(e.message)), 'warning');
				});
		});
	},

	handleSave: function (ev) {
		const rawEl = document.getElementById('blocklist-raw-textarea');
		if (rawEl) {
			this.rawContent = rawEl.value;
		} else {
			this.rawContent = serializeBlocklist(this.items);
		}

		return fs.write(localFile, this.rawContent || '')
			.then(function () {
				ui.addNotification(null, E('p', _('Blocklist changes saved.')), 'info');
			})
			.catch(function (e) {
				ui.addNotification(null, E('p', _('Unable to save changes: %s').format(e.message)), 'error');
			});
	},

	handleReset: null
});
