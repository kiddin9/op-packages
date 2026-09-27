'use strict';
'require view';
'require fs';
'require ui';
'require overview-manager.shared as common';

var helper = '/usr/libexec/overview-manager';
var self = '00_overview-manager.js';

function installedFiles(text) {
	return (text || '').replace(/\r/g, '').split('\n').map(function(name) {
		return name.trim();
	}).filter(function(name) {
		return /\.js$/.test(name) && name !== self;
	}).sort(common.compareWidgets);
}

function fallbackTitle(name) {
	return name.replace(/^\d+_/, '').replace(/\.js$/, '').replace(/[-_]+/g, ' ')
		.replace(/(^|\s)(.)/g, function(match, space, letter) {
			return space + letter.toUpperCase();
		});
}

function widgetTitle(name) {
	var moduleName = 'view.status.include.' + name.replace(/\.js$/, '');
	return L.resolveDefault(L.require(moduleName), null).then(function(widget) {
		return widget && widget.title != null && widget.title !== '' ?
			String(widget.title) : fallbackTitle(name);
	});
}

function arrange(files, layout) {
	var known = {};
	files.forEach(function(name) { known[name] = true; });
	var order = [];
	layout.order.forEach(function(name) {
		if (known[name] && order.indexOf(name) < 0)
			order.push(name);
	});
	files.forEach(function(name) {
		if (order.indexOf(name) < 0)
			order.push(name);
	});
	return order;
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec(helper, [ 'files' ]), { stdout: '' }),
			L.resolveDefault(fs.exec(helper, [ 'layout' ]), { stdout: '' })
		]).then(function(data) {
			var files = installedFiles(data[0].stdout);
			var layout = common.parseLayout(data[1].stdout);
			return Promise.all(files.map(widgetTitle)).then(function(titles) {
				return arrange(files, layout).map(function(name) {
					var index = files.indexOf(name);
					return {
						name: name,
						title: titles[index],
						visible: layout.hidden.indexOf(name) < 0
					};
				});
			});
		});
	},

	render: function(items) {
		var list = E('div', { 'class': 'overview-manager-list' });
		var result = E('span', { 'class': 'overview-manager-result' });
		var saveButton;
		var dragging = null;

		function move(name, offset) {
			var index = items.findIndex(function(item) { return item.name === name; });
			var target = index + offset;
			if (index < 0 || target < 0 || target >= items.length)
				return;
			var item = items.splice(index, 1)[0];
			items.splice(target, 0, item);
			renderList();
		}

		function row(item, index) {
			var visible = E('input', {
				'type': 'checkbox',
				'checked': item.visible ? '' : null,
				'change': function(ev) {
					item.visible = ev.target.checked;
					renderList();
				}
			});
			return E('div', {
				'class': 'overview-manager-row' + (item.visible ? '' : ' hidden-widget'),
				'draggable': 'true',
				'data-widget': item.name,
				'dragstart': function(ev) {
					dragging = item.name;
					ev.currentTarget.classList.add('dragging');
					ev.dataTransfer.effectAllowed = 'move';
					ev.dataTransfer.setData('text/plain', item.name);
				},
				'dragend': function(ev) {
					dragging = null;
					ev.currentTarget.classList.remove('dragging');
					Array.prototype.forEach.call(
						list.querySelectorAll('.drag-over'),
						function(node) { node.classList.remove('drag-over'); });
				},
				'dragover': function(ev) {
					ev.preventDefault();
					ev.currentTarget.classList.add('drag-over');
					ev.dataTransfer.dropEffect = 'move';
				},
				'dragleave': function(ev) {
					ev.currentTarget.classList.remove('drag-over');
				},
				'drop': function(ev) {
					ev.preventDefault();
					var sourceName = dragging || ev.dataTransfer.getData('text/plain');
					var sourceIndex = items.findIndex(function(entry) {
						return entry.name === sourceName;
					});
					if (sourceIndex < 0 || sourceName === item.name)
						return;
					var after = ev.clientY > ev.currentTarget.getBoundingClientRect().top +
						ev.currentTarget.offsetHeight / 2;
					var moved = items.splice(sourceIndex, 1)[0];
					var targetIndex = items.findIndex(function(entry) {
						return entry.name === item.name;
					});
					items.splice(targetIndex + (after ? 1 : 0), 0, moved);
					renderList();
				}
			}, [
				E('span', {
					'class': 'overview-manager-handle',
					'title': _('Drag to reorder')
				}, [ '⠿' ]),
				E('span', {}, [
					E('span', { 'class': 'overview-manager-widget-title' }, [ item.title ]),
					E('span', { 'class': 'overview-manager-widget-file' }, [ item.name ])
				]),
				E('label', { 'class': 'overview-manager-switch' }, [
					visible,
					E('span', {}, [ _('Show') ])
				]),
				E('span', { 'class': 'overview-manager-order-buttons' }, [
					E('button', {
						'class': 'cbi-button',
						'type': 'button',
						'disabled': index === 0 ? '' : null,
						'title': _('Move up'),
						'click': function() { move(item.name, -1); }
					}, [ '↑' ]),
					E('button', {
						'class': 'cbi-button',
						'type': 'button',
						'disabled': index === items.length - 1 ? '' : null,
						'title': _('Move down'),
						'click': function() { move(item.name, 1); }
					}, [ '↓' ])
				])
			]);
		}

		function renderList() {
			list.replaceChildren.apply(list, items.map(row));
		}

		function save() {
			var order = items.map(function(item) { return item.name; }).join(',');
			var hidden = items.filter(function(item) {
				return !item.visible;
			}).map(function(item) {
				return item.name;
			}).join(',');

			saveButton.disabled = true;
			result.className = 'overview-manager-result';
			result.textContent = _('Saving…');
			return fs.exec(helper, [ 'save', order, hidden ]).then(function() {
				result.className = 'overview-manager-result good';
				result.textContent = _('Saved. Reload Overview to see the layout.');
			}).catch(function(error) {
				result.className = 'overview-manager-result bad';
				result.textContent = error.message || _('Unable to save the layout.');
			}).finally(function() {
				saveButton.disabled = false;
			});
		}

		function resetOrder() {
			items.sort(function(left, right) {
				return common.compareWidgets(left.name, right.name);
			});
			items.forEach(function(item) { item.visible = true; });
			result.className = 'overview-manager-result';
			result.textContent = _('Default order restored locally. Save to apply it.');
			renderList();
		}

		saveButton = E('button', {
			'class': 'cbi-button cbi-button-positive',
			'type': 'button',
			'click': save
		}, [ _('Save layout') ]);

		renderList();

		return E('div', { 'class': 'overview-manager-page' }, [
			common.styles(),
			E('div', { 'class': 'overview-manager-header' }, [
				E('div', {}, [
					E('h2', {}, [ 'Overview Manager' ]),
					E('p', { 'class': 'overview-manager-subtitle' }, [
						_('Change the order of widgets on Status → Overview and hide widgets you do not need.')
					])
				])
			]),
			E('section', { 'class': 'overview-manager-section' }, [
				E('div', { 'class': 'overview-manager-section-head' }, [
					E('div', {}, [
						E('h3', {}, [ _('Overview widgets') ]),
						E('p', {}, [
							_('Drag rows or use the arrow buttons. Newly installed widgets are appended in their normal filename order.')
						])
					])
				]),
				items.length ? list : E('p', { 'class': 'overview-manager-muted' }, [
					_('No Overview widgets were found.')
				]),
				E('div', { 'class': 'overview-manager-actions' }, [
					saveButton,
					E('button', {
						'class': 'cbi-button',
						'type': 'button',
						'click': resetOrder
					}, [ _('Restore defaults') ]),
					result
				]),
				E('div', { 'class': 'overview-manager-note' }, [
					_('OpenWrt 25.12 also has a browser-local Hide button. A widget hidden there remains hidden only in that browser, independently of this router-wide layout.')
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
