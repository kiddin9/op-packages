/* SPDX-License-Identifier: Apache-2.0 */
(function() {
	'use strict';

	function translate(message) {
		var russian = {
			'Table': 'Таблица', 'Actions': 'Действия',
			'Ping destination': 'Адрес для пинга',
			'Traceroute destination': 'Адрес для трассировки',
			'DNS destination': 'Адрес для DNS-запроса'
		};
		return /^ru(?:-|$)/i.test(document.documentElement.lang) && russian[message] ||
			(typeof window._ === 'function' ? window._(message) : message);
	}

	function cells(row) {
		return Array.from(row.children).filter(function(cell) {
			return cell.matches('td, th, .td, .th');
		});
	}

	function prepareTable(table) {
		var rows = Array.from(table.querySelectorAll('tr, .tr')).filter(function(row) {
			return row.closest('.table') === table;
		});
		var heading = rows.find(function(row) {
			return row.matches('.table-titles, .cbi-section-table-titles') ||
				cells(row).some(function(cell) { return cell.matches('th, .th'); });
		});
		var labels = heading ? cells(heading).map(function(cell) { return cell.textContent.trim(); }) : [];
		var diagnostics = /(?:^|-)admin-network-diagnostics$/.test(document.body.getAttribute('data-page') || '');

		if (diagnostics) {
			table.classList.add('rmm-diagnostics');
			var destinations = [ 'Ping destination', 'Traceroute destination', 'DNS destination' ];
			rows.forEach(function(row) {
				cells(row).forEach(function(cell, index) {
					var input = cell.querySelector('input[type="text"]');
					if (!input || index >= destinations.length || cell.querySelector('.rmm-diag-label'))
						return;
					var label = document.createElement('label');
					label.className = 'rmm-diag-label';
					label.textContent = translate(destinations[index]);
					if (!input.id)
						input.id = 'rmm-diag-destination-' + index;
					label.htmlFor = input.id;
					cell.insertBefore(label, input);
				});
			});
			return;
		}

		if (heading) {
			table.classList.add('rmm-records');
			heading.classList.add('rmm-table-head');
			rows.forEach(function(row) {
				if (row === heading || row.matches('.cbi-section-table-descr, .placeholder'))
					return;
				var values = cells(row);
				if (values.length !== labels.length || values.some(function(cell) {
					return Number(cell.getAttribute('colspan') || 1) > 1;
				}))
					return;
				row.classList.add('rmm-record-row');
				values.forEach(function(cell, index) {
					// Own label attribute leaves LuCI's data-title and widget hooks intact.
					var label = cell.getAttribute('data-title') || labels[index];
					if (!label && cell.matches('.cbi-section-actions'))
						label = translate('Actions');
					if (cell.getAttribute('data-rmm-label') !== label)
						cell.setAttribute('data-rmm-label', label);
				});
			});
		}
		else if (rows.length && rows.every(function(row) { return cells(row).length === 2; })) {
			table.classList.add('rmm-key-values');
		}

		else if (rows.length && rows.every(function(row) { return cells(row).length >= 3 && !cells(row).some(function(cell) { return Number(cell.getAttribute('colspan') || 1) > 1; }); })) {
			// Native interface/Wi-Fi summaries have no column heading.
			table.classList.add('rmm-status-table');
		}

		// Form widgets need visible overflow for their native dropdowns and tooltips.
		// Only read-only tables get a local scroll wrapper; nodes/events are retained.
		if (table.querySelector('input, select, textarea, .cbi-dropdown, .cbi-tooltip-container'))
			return;
		if (!table.parentElement.classList.contains('rmm-table-scroll')) {
			var wrapper = document.createElement('div');
			wrapper.className = 'rmm-table-scroll';
			wrapper.setAttribute('role', 'region');
			wrapper.setAttribute('aria-label', translate('Table'));
			wrapper.tabIndex = 0;
			table.parentElement.insertBefore(wrapper, table);
			wrapper.appendChild(table);
		}
	}

	function positionDropdowns() {
		var width = document.documentElement.clientWidth || window.innerWidth;
		var height = window.innerHeight;
		var reserved = parseFloat(window.getComputedStyle(document.body).paddingBottom) || 0;
		document.querySelectorAll('.cbi-dropdown[open]').forEach(function(dropdown) {
			var list = dropdown.querySelector(':scope > ul.dropdown');
			if (!list) return;
			var anchor = dropdown.getBoundingClientRect();
			var panelWidth = Math.min(Math.max(anchor.width, list.scrollWidth), Math.max(0, width - 24));
			var below = Math.max(0, height - reserved - anchor.bottom - 12);
			var above = Math.max(0, anchor.top - 12);
			var useAbove = below < Math.min(list.scrollHeight, 180) && above > below;
			var available = useAbove ? above : below;
			var panelHeight = Math.min(list.scrollHeight, available);
			dropdown.style.setProperty('--rmm-dropdown-left', Math.max(12, Math.min(anchor.left, width - panelWidth - 12)) + 'px');
			dropdown.style.setProperty('--rmm-dropdown-top', (useAbove ? anchor.top - panelHeight : anchor.bottom) + 'px');
			dropdown.style.setProperty('--rmm-dropdown-width', panelWidth + 'px');
			dropdown.style.setProperty('--rmm-dropdown-height', available + 'px');
			list.classList.add('rmm-dropdown-panel');
		});
	}

	function init() {
		var scheduled = false;
		var previousFocus = document.activeElement;
		var modalWasOpen = false;

		function refresh() {
			scheduled = false;
			document.querySelectorAll('#view .table, #modal_overlay .table').forEach(prepareTable);
			positionDropdowns();
			var overlay = document.getElementById('modal_overlay');
			var modal = overlay && overlay.querySelector('.modal:not(.login)');
			var open = !!modal && document.body.classList.contains('modal-overlay-active');
			if (open) {
				modal.setAttribute('role', 'dialog');
				modal.setAttribute('aria-modal', 'true');
				var title = modal.querySelector('h4');
				if (title) {
					if (!title.id) title.id = 'rmm-dialog-title';
					modal.setAttribute('aria-labelledby', title.id);
				}
			}
			if (modalWasOpen && !open && previousFocus && previousFocus.isConnected &&
				(overlay?.contains(document.activeElement) || document.activeElement === document.body))
				previousFocus.focus();
			modalWasOpen = open;
		}

		function schedule() {
			if (!scheduled) {
				scheduled = true;
				window.requestAnimationFrame(refresh);
			}
		}

		document.addEventListener('focusin', function(event) {
			if (!document.body.classList.contains('modal-overlay-active'))
				previousFocus = event.target;
		});
		document.addEventListener('keydown', function(event) {
			if (event.key !== 'Tab' || !document.body.classList.contains('modal-overlay-active'))
				return;
			var overlay = document.getElementById('modal_overlay');
			var modal = overlay && overlay.querySelector('.modal:not(.login)');
			if (!modal) return;
			var controls = Array.from(modal.querySelectorAll('a[href], button, input:not([type="hidden"]), select, textarea, [tabindex]')).filter(function(control) {
				return !control.disabled && control.tabIndex >= 0 && control.getClientRects().length;
			});
			if (!controls.length) return;
			var index = controls.indexOf(document.activeElement);
			if (index < 0 || (event.shiftKey ? index === 0 : index === controls.length - 1)) {
				event.preventDefault();
				controls[event.shiftKey ? controls.length - 1 : 0].focus();
			}
		});
		new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true, characterData: true });
		new MutationObserver(schedule).observe(document.body, { attributes: true, attributeFilter: [ 'class' ] });
		new MutationObserver(schedule).observe(document.body, { attributes: true, subtree: true, attributeFilter: [ 'open' ] });
		window.addEventListener('resize', schedule);
		window.addEventListener('scroll', schedule, { capture: true, passive: true });
		refresh();
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init, { once: true });
	else
		init();
})();
