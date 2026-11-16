'use strict';

'require dom';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.utils as podmanUtil';

return podmanView.tabContent.extend({
	tab: 'stats',
	container: null,

	render(container) {
		this.container = container;

		if (!this.container.isRunning()) {
			return this.warningContent(_('Container is not running'));
		}

		return this.renderTabContent(_('Statistics'), [
			this.renderStatsTable(),
		]);
	},

	onTabActive() {
		if (!this.container || !this.container.isRunning() || this.statsStream) {
			return;
		}

		this.statsStream = this.container.streamStats((stats) => {
			this.updateStatsDisplay(stats);
		});
	},

	onTabInactive() {
		if (!this.statsStream) {
			return;
		}

		this.statsStream.stop();
		this.statsStream = null;
	},

	renderStatsTable() {
		const table = new podmanUI.TableList();

		table
			.addRow(_('CPU Usage'),    '-', { 'data-stat': 'cpu' })
			.addRow(_('Memory Usage'), '-', { 'data-stat': 'memory' })
			.addRow(_('Memory Limit'), '-', { 'data-stat': 'memory-limit' })
			.addRow(_('Memory %'),     '-', { 'data-stat': 'memory-percent' })
			.addRow(_('Network I/O'),  '-', { 'data-stat': 'network-io' })
			.addRow(_('Block I/O'),    '-', { 'data-stat': 'block-io' })
			.addRow(_('PIDs'),         '-', { 'data-stat': 'pids' })
		;

		return table.render();
	},

	updateStatsDisplay(stats) {
		if (!stats) return;

		if (!this.statElements) {
			this.statElements = {};
			for (const key of ['cpu', 'memory', 'memory-limit', 'memory-percent', 'network-io', 'block-io', 'pids']) {
				this.statElements[key] = document.querySelector(`[data-stat="${key}"] td:last-of-type`);
			}
		}

		const updates = [
			['cpu',            stats.CPU != null ? stats.CPU.toFixed(2) + '%' : '-'],
			['memory',         podmanUtil.format.bytes(stats.MemUsage) || '-'],
			['memory-limit',   podmanUtil.format.bytes(stats.MemLimit) || '-'],
			['memory-percent', stats.MemPerc != null ? stats.MemPerc.toFixed(2) + '%' : '-'],
			['network-io',     this._formatNetworkIO(stats.Network)],
			['block-io',       this._formatBlockIO(stats.BlockInput, stats.BlockOutput)],
			['pids',           stats.PIDs],
		];

		for (const [key, value] of updates) {
			if (this.statElements[key])
				dom.content(this.statElements[key], value);
		}
	},

	_formatNetworkIO(networks) {
		const parts = Object.keys(networks || {}).map((iface) => {
			const net = networks[iface];
			return `${iface}: ↓ ${podmanUtil.format.bytes(net.RxBytes)} / ↑ ${podmanUtil.format.bytes(net.TxBytes)}`;
		});

		if (parts.length === 0) return '-';

		return parts.reduce((nodes, part, i) => {
			if (i > 0) nodes.push(E('br'));
			nodes.push(part);
			return nodes;
		}, []);
	},

	_formatBlockIO(blockInput, blockOutput) {
		return _('Read: %s / Write: %s').format(
			podmanUtil.format.bytes(blockInput || 0),
			podmanUtil.format.bytes(blockOutput || 0)
		);
	}
});
