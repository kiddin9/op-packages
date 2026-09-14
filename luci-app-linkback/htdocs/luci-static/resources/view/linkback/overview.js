'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

var callGetStatus = rpc.declare({
	object: 'luci.linkback',
	method: 'get_status'
});

var callManageService = rpc.declare({
	object: 'luci.linkback',
	method: 'manage_service',
	params: [ 'action' ]
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	injectStyle: function() {
		if (document.getElementById('linkback_status_style'))
			return;

		var css = [
			'.linkback-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:middle}',
			'.linkback-dot-green{background-color:#4CAF50;box-shadow:0 0 6px #4CAF50}',
			'.linkback-dot-red{background-color:#f44336;box-shadow:0 0 6px #f44336}',
			'.linkback-dot-grey{background-color:#9e9e9e}',
			'.linkback-indicator{display:inline-flex;align-items:center;padding:4px 10px;border-radius:12px;font-size:11px;font-weight:bold;background-color:rgba(0,0,0,.05)}',
			'.linkback-badge{display:inline-block;padding:4px 8px;border-radius:4px;font-size:11px;font-weight:bold;color:#fff;text-align:center}',
			'.linkback-badge-active{background-color:#4CAF50}',
			'.linkback-badge-standby{background-color:#2196F3}',
			'.linkback-badge-faulted{background-color:#f44336}'
		].join('');

		document.head.appendChild(E('style', { id: 'linkback_status_style' }, css));
	},

	load: function() {
		return callGetStatus();
	},

	render: function(status) {
		this.injectStyle();

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LinkBack 链路守护') + ' - ' + _('Overview')),
			E('div', { 'class': 'cbi-map-descr' }, _('Real-time health state, priority mapping, and service control for Multi-WAN default routing metrics.'))
		]);

		// --- Service Status Section (Aligned with lucky style) ---
		var stateText = _('Collecting...');
		var stateColor = '#999';

		if (status && status.links && status.links.length > 0) {
			stateText = _('Running');
			stateColor = 'green';
		} else {
			stateText = _('Stopped');
			stateColor = 'red';
		}

		var isRunning = (status && status.links && status.links.length > 0);

		var statusSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('Service Status')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Running State')),
						E('td', { 'class': 'td left' }, [
							E('span', {
								id: 'linkback-service-state',
								style: 'font-weight:bold; color:' + stateColor + '; margin-right:15px;'
							}, stateText),
							E('button', {
								id: 'linkback-restart-btn',
								'class': 'btn cbi-button cbi-button-apply',
								style: 'display:' + (isRunning ? 'inline-block' : 'none') + ';',
								click: ui.createHandlerFn(this, 'handleServiceAction', 'restart')
							}, _('Restart'))
						])
					])
				])
			])
		]);
		container.appendChild(statusSection);

		// --- Link Status Section (Aligned with lucky style) ---
		var linkSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('Link Status')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('div', { id: 'linkback-status-box' }, [
					E('p', { 'class': 'spinning' }, _('Loading real-time link status...'))
				])
			])
		]);
		container.appendChild(linkSection);

		// Initial render
		this.updateStatusView(status);

		// Start polling every 3 seconds
		poll.add(L.bind(function() {
			return callGetStatus().then(L.bind(function(res) {
				this.updateStatusView(res);
			}, this));
		}, this), 3);

		return container;
	},

	updateStatusView: function(status) {
		var box = document.getElementById('linkback-status-box');
		if (!box)
			return;

		// Update service state indicator
		var stateEl = document.getElementById('linkback-service-state');
		if (stateEl) {
			if (status && status.links && status.links.length > 0) {
				stateEl.textContent = _('Running');
				stateEl.style.color = 'green';
			} else {
				stateEl.textContent = _('Stopped');
				stateEl.style.color = 'red';
			}
		}

		var restartBtn = document.getElementById('linkback-restart-btn');
		if (restartBtn) {
			if (status && status.links && status.links.length > 0) {
				restartBtn.style.display = 'inline-block';
			} else {
				restartBtn.style.display = 'none';
			}
		}

		if (!status || !status.links || status.links.length === 0) {
			dom.content(box, [
				E('p', { style: 'color:#f44336; font-weight:bold; padding:20px;' },
					_('LinkBack daemon is not running or no links are configured. Please check Settings page.'))
			]);
			return;
		}

		var activeLink = status.active_link || 'none';

		// Create standard LuCI section table
		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th', 'style': 'text-align:center; width:5%;' }, '#'),
				E('th', { 'class': 'th', 'style': 'text-align:left;' }, _('Link Name')),
				E('th', { 'class': 'th', 'style': 'text-align:left;' }, _('Status')),
				E('th', { 'class': 'th', 'style': 'text-align:left;' }, _('Routing Attributes')),
				E('th', { 'class': 'th', 'style': 'text-align:left;' }, _('Latency Details'))
			])
		]);

		status.links.forEach(function(link, index) {
			var roleTitle = '';
			var roleClass = '';

			if (link.is_up && link.healthy) {
				if (link.name === activeLink) {
					roleTitle = _('Active');
					roleClass = 'linkback-badge-active';
				} else {
					roleTitle = _('Standby');
					roleClass = 'linkback-badge-standby';
				}
			} else {
				roleTitle = _('Faulted');
				roleClass = 'linkback-badge-faulted';
			}

			// Health check indicators
			var checkBadges = [];

			if (link.check_type === 'ping' && link.ping) {
				var dotClass = link.ping.ok ? 'linkback-dot-green' : 'linkback-dot-red';
				checkBadges.push(E('span', { 'class': 'linkback-indicator', 'style': 'margin-bottom:4px; margin-right:6px;' }, [
					E('span', { 'class': 'linkback-dot ' + dotClass }),
					'Ping: ' + (link.ping.ok ? link.ping.rtt + 'ms' : _('Failed'))
				]));
			}
			else if (link.check_type === 'dns' && link.dns) {
				var dotClass = link.dns.ok ? 'linkback-dot-green' : 'linkback-dot-red';
				checkBadges.push(E('span', { 'class': 'linkback-indicator', 'style': 'margin-bottom:4px; margin-right:6px;' }, [
					E('span', { 'class': 'linkback-dot ' + dotClass }),
					'DNS: ' + (link.dns.ok ? link.dns.rtt + 'ms' : _('Failed'))
				]));
			}
			else if (link.check_type === 'tcp' && link.tcp) {
				var dotClass = link.tcp.ok ? 'linkback-dot-green' : 'linkback-dot-red';
				checkBadges.push(E('span', { 'class': 'linkback-indicator', 'style': 'margin-bottom:4px; margin-right:6px;' }, [
					E('span', { 'class': 'linkback-dot ' + dotClass }),
					'TCP: ' + (link.tcp.ok ? link.tcp.rtt + 'ms' : _('Failed'))
				]));
			}

			if (checkBadges.length === 0) {
				checkBadges.push(E('span', { 'style': 'color:#999;' }, '-'));
			}

			// Route and metric attributes
			var routeDetails = E('div', { 'style': 'font-size:12px; line-height:1.6;' }, [
				E('div', {}, [
					E('strong', {}, _('Gateway') + ': '),
					link.gateway || '-'
				]),
				E('div', {}, [
					E('strong', {}, _('Priority') + ': '),
					String(link.priority),
					' | ',
					E('strong', {}, _('Metric') + ': '),
					link.metric + ' → ' + link.current_metric
				])
			]);

			var row = E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'style': 'text-align:center; font-weight:bold; vertical-align:middle;' }, String(index + 1)),
				E('td', { 'class': 'td', 'style': 'font-weight:bold; vertical-align:middle;' }, [
					E('span', { 'style': 'font-size:14px;' }, link.name),
					link.device ? E('span', { 'style': 'font-size:11px; color:#666; margin-left:6px; background:#eee; padding:2px 4px; border-radius:3px;' }, link.device) : ''
				]),
				E('td', { 'class': 'td', 'style': 'vertical-align:middle;' }, [
					E('span', { 'class': 'linkback-badge ' + roleClass }, roleTitle)
				]),
				E('td', { 'class': 'td', 'style': 'vertical-align:middle;' }, routeDetails),
				E('td', { 'class': 'td', 'style': 'vertical-align:middle;' }, E('div', { 'style': 'display:flex; flex-wrap:wrap; align-items:center;' }, checkBadges))
			]);

			table.appendChild(row);
		});

		dom.content(box, [ table ]);
	},

	handleServiceAction: function(action) {
		ui.showModal(null, [
			E('p', { 'class': 'spinning' }, _('Executing service action: %s ...').format(action))
		]);

		return callManageService(action).then(function(res) {
			ui.hideModal();
			if (res && res.success) {
				ui.addNotification(null, E('p', _('Service action completed successfully.')), 'info');
			} else {
				ui.addNotification(null, E('p', _('Failed to execute service action.')), 'error');
			}
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('RPC error: %s').format(err.message)), 'error');
		});
	}
});
