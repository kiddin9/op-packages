'use strict';
'require dom';
'require view';
'require fs';
'require ui';

const localFile = '/etc/banip/banip.allowlist';
const maxSize = 100000;

function resetScroll() {
	document.querySelector('.main-right')?.scrollTo(0, 0);
}

function parseSections(rawText) {
	const lines = (rawText || '').split('\n');
	let currentSection = 'user'; // 'system' or 'user'
	const systemItems = [];
	const userItems = [];

	lines.forEach(function (line) {
		const trimmed = line.trim();
		if (!trimmed) return;

		if (trimmed.startsWith('### --- SYSTEM') || trimmed.startsWith('### --- AUTO GENERATED')) {
			currentSection = 'system';
			return;
		}
		if (trimmed.startsWith('### --- USER') || trimmed.startsWith('### --- CUSTOM')) {
			currentSection = 'user';
			return;
		}

		if (trimmed.startsWith('#')) return;

		let val = trimmed;
		let cmt = '';
		const cmtIdx = trimmed.indexOf('#');
		if (cmtIdx >= 0) {
			val = trimmed.substring(0, cmtIdx).trim();
			cmt = trimmed.substring(cmtIdx + 1).trim();
		}

		if (!val) return;

		const entry = { value: val, comment: cmt };
		if (currentSection === 'system') {
			systemItems.push(entry);
		} else {
			userItems.push(entry);
		}
	});

	return { systemItems: systemItems, userItems: userItems };
}

function serializeAll(systemItems, userItems) {
	const output = [];
	if (systemItems && systemItems.length > 0) {
		output.push('### --- SYSTEM / AUTO GENERATED RULES ---');
		systemItems.forEach(function (item) {
			output.push(item.comment ? `${item.value} # ${item.comment}` : `${item.value} # System auto-rule`);
		});
		output.push('');
	}
	output.push('### --- USER CUSTOM RULES ---');
	if (userItems && userItems.length > 0) {
		userItems.forEach(function (item) {
			output.push(item.comment ? `${item.value} # ${item.comment}` : item.value);
		});
	}
	output.push('');
	return output.join('\n');
}

return view.extend({
	rawContent: '',
	isRawMode: false,
	systemItems: [],
	userItems: [],

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

	render: function (allowlist) {
		const size = allowlist[0] ? allowlist[0].size : 0;
		this.rawContent = allowlist[1] != null ? allowlist[1] : '';
		const tooBig = size >= maxSize;
		const self = this;

		const parsed = parseSections(this.rawContent);
		this.systemItems = parsed.systemItems;
		this.userItems = parsed.userItems;

		if (tooBig) {
			resetScroll();
			ui.addNotification(null, E('p', _('The allowlist is too big, raw editor mode enforced.')), 'error');
			this.isRawMode = true;
		}

		const mainContainer = E('div', { 'class': 'cbi-map' });

		function syncAndRebuild() {
			self.rawContent = serializeAll(self.systemItems, self.userItems);
			renderContainer();
		}

		/*
			1. Render System / Auto Generated Table (Pure OpenWrt Native)
		*/
		function renderSystemTable() {
			if (!self.systemItems || self.systemItems.length === 0) {
				return '';
			}

			const boxes = self.systemItems.map(function (item) {
				return E('div', {
					'style': 'display: flex; align-items: center; justify-content: space-between; padding: .55em .85em; background: rgba(0, 0, 0, 0.025); border: 1px solid var(--cbi-border-color, #e5e7eb); border-radius: 6px;'
				}, [
					E('span', { 'style': 'font-family: monospace; font-weight: bold; font-size: .98em;' }, [item.value]),
					E('span', { 'style': 'font-size: .88em; color: #64748b; margin-left: .8em; white-space: nowrap;' }, [
						item.comment || _('Auto detected by SecBox / protected')
					])
				]);
			});

			return E('div', { 'class': 'cbi-section' }, [
				E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: .4em;' }, [
					E('h3', { 'style': 'margin: 0;' }, [_('System Auto-Protected Rules')]),
					E('span', { 'style': 'font-size: .88em; color: #64748b;' }, [_('Auto detected by SecBox / protected')])
				]),
				E('div', { 'class': 'cbi-section-node', 'style': 'padding: .85em; background: var(--cbi-section-bg, #fff); border: 1px solid var(--cbi-border-color, #e5e7eb); border-radius: 6px;' }, [
					E('div', {
						'style': 'display: grid; grid-template-columns: repeat(auto-fit, minmax(min(20em, 100%), 1fr)); gap: .6em .8em;'
					}, boxes)
				])
			]);
		}

		/*
			2. Render User Custom Rules Table (Pure OpenWrt Native)
		*/
		function renderUserTable() {
			const rows = self.userItems.map(function (item, index) {
				return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((index % 2) ? 2 : 1) }, [
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important; font-family: monospace;' }, [item.value]),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important;' }, [item.comment || '-']),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'text-align: right !important;' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-remove',
							'title': _('Delete this custom rule'),
							'click': function () {
								self.userItems.splice(index, 1);
								syncAndRebuild();
							}
						}, [_('Delete')])
					])
				]);
			});

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('User Custom Rules')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr cbi-section-table-titles' }, [
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 45%; text-align: left !important;' }, [_('Address / Domain / Network')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 40%; text-align: left !important;' }, [_('Comment')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 15%; text-align: right !important;' }, [_('Action')])
						]),
						E('tbody', {}, rows.length ? rows : [
							E('tr', { 'class': 'tr cbi-section-table-row' }, [
								E('td', { 'colspan': 3, 'class': 'td cbi-section-table-cell', 'style': 'text-align: center !important; color: #888; padding: 1.5em;' },
									[_('No custom allowlist entries yet. Add one below.')])
							])
						])
					])
				])
			]);
		}

		/*
			3. Quick Add Section (Pure OpenWrt Native)
		*/
		function renderQuickAdd() {
			const valInput = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'placeholder': _('e.g. 192.168.1.100, 10.0.0.0/24, or example.com')
			});

			const commentInput = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'style': 'width: 100%;',
				'placeholder': _('Optional comment (e.g. Office NAS)')
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

				self.userItems.unshift({ value: val, comment: cmt });
				valInput.value = '';
				commentInput.value = '';
				syncAndRebuild();
				ui.addNotification(null, E('p', _('Added custom rule "%s".').format(val)), 'info');
			}

			valInput.addEventListener('keydown', function (ev) {
				if (ev.key === 'Enter') doAdd();
			});
			commentInput.addEventListener('keydown', function (ev) {
				if (ev.key === 'Enter') doAdd();
			});

			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Add User Custom Rule')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr cbi-section-table-titles' }, [
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 45%; text-align: left !important;' }, [_('Address or Domain')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 40%; text-align: left !important;' }, [_('Comment / Note')]),
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
			4. Raw Textarea Editor
		*/
		function renderRawEditor() {
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Raw Text Editor')),
				E('div', { 'class': 'cbi-section-descr' }, [
					_('One record per line. Supports IPv4, IPv6, CIDR, MAC, Domain and comments starting with "#".')
				]),
				E('div', { 'class': 'cbi-section-node' }, [
					E('textarea', {
						'id': 'allowlist-raw-textarea',
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
			Assemble the whole view
		*/
		function renderContainer() {
			dom.content(mainContainer, [
				E('h2', { 'name': 'content' }, [_('SecBox Allowlist')]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('Manage trusted local devices, subnets and domains that will never be blocked by SecBox.')
				]),
				E('div', { 'style': 'margin-bottom: 1em; text-align: right;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-neutral',
						'click': function () {
							if (self.isRawMode) {
								const parsed = parseSections(self.rawContent);
								self.systemItems = parsed.systemItems;
								self.userItems = parsed.userItems;
								self.isRawMode = false;
							} else {
								self.rawContent = serializeAll(self.systemItems, self.userItems);
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
						renderUserTable(),
						renderSystemTable()
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
					ui.addNotification(null, E('p', _('Allowlist saved and SecBox service reloaded successfully!')), 'info');
				})
				.catch(function (e) {
					ui.hideIndicator('banip-action');
					ui.addNotification(null, E('p', _('Saved allowlist, but failed to reload SecBox: %s').format(e.message)), 'warning');
				});
		});
	},

	handleSave: function (ev) {
		const rawEl = document.getElementById('allowlist-raw-textarea');
		if (rawEl) {
			this.rawContent = rawEl.value;
		} else {
			this.rawContent = serializeAll(this.systemItems, this.userItems);
		}

		return fs.write(localFile, this.rawContent || '')
			.then(function () {
				ui.addNotification(null, E('p', _('Allowlist changes saved.')), 'info');
			})
			.catch(function (e) {
				ui.addNotification(null, E('p', _('Unable to save changes: %s').format(e.message)), 'error');
			});
	},

	handleReset: null
});
