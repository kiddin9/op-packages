'use strict';

'require dom';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.utils as podmanUtil';

return podmanView.tabContent.extend({
	tab: 'stats',
	pod: null,

	render(pod) {
		this.pod = pod;

		if (!this.pod.isRunning()) {
			return this.warningContent(_('Pod is not running'));
		}

		this.containerNames = this.buildContainerNameMap();
		this.tableContent = E('div', { class: 'stats-table-content' }, []);

		return this.renderTabContent('', [ this.tableContent ]);
	},

	onTabActive() {
		if (!this.pod || !this.pod.isRunning() || this.statsStream) return;

		this.statsStream = this.pod.streamStats((reports) => {
			this.updateStats(reports);
		});
	},

	onTabInactive() {
		if (!this.statsStream) return;

		this.statsStream.stop();
		this.statsStream = null;
	},

	buildContainerNameMap() {
		const map = {};
		for (const c of (this.pod.getContainers() || [])) {
			if (c?.Id) map[c.Id] = c.Name;
		}
		return map;
	},

	updateStats(reports) {
		if (!Array.isArray(reports)) return;

		const table = new podmanUI.Table();
		const headers = [
			_('Container'),
			_('CID'),
			_('CPU %'),
			_('Memory'),
			_('Memory %'),
			_('Net I/O'),
			_('Block I/O'),
			_('PIDs'),
		];
		const columnWidth = `width: ${100 / headers.length}%;`;
		headers.forEach((h) => table.addHeader(h, { style: columnWidth }));

		for (const r of reports) {
			const cid = r.CID || '';
			const name = this.containerNames[cid] || r.Name || '-';
			table.addRow([
				{ inner: name },
				{ inner: podmanUtil.truncate(cid, 12) },
				{ inner: r.CPU || '-' },
				{ inner: r.MemUsage || '-' },
				{ inner: r.Mem || '-' },
				{ inner: r.NetIO || '-' },
				{ inner: r.BlockIO || '-' },
				{ inner: r.PIDS || '-' },
			]);
		}

		dom.content(this.tableContent, table.render());
	},
});
