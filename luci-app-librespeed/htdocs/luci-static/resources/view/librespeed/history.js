'use strict';
'require view';
'require rpc';
'require ui';
'require librespeed.common as lscommon';

/* The alias comes from the require above; the repo eslint config only
 * knows the stock module names. */
/* global lscommon */

/* The chart wants every point in the range, but the table must not put
 * thousands of rows into the DOM: a 15-minute schedule kept for 30 days is
 * nearly 3000 measurements. Paging keeps the page responsive without a
 * second fetch, since the entries are in memory anyway. */
const pageSize = 50;

const callHistory = rpc.declare({
	object: 'librespeed',
	method: 'history',
	params: [ 'from', 'to', 'limit' ],
	expect: { '': {} }
});

return view.extend({
	entries: [],
	prevEntries: [],
	resolution: 'raw',
	group: 'speed',
	active: null,
	range: 86400,
	server: '',
	iface: '',
	page: 0,

	/* Which entries come back -- and at which resolution -- is the server's
	 * decision, so every range switch is a fetch rather than a client-side
	 * filter over one download. The previous window of the same length is
	 * fetched alongside, so the summary can say how this period compares. */
	fetch() {
		const now = Math.floor(Date.now() / 1000);
		/* Zero, not undefined: the rpcd argument is typed as an integer and a
		 * null would fail validation rather than mean "everything". */
		const from = this.range ? now - this.range : 0;

		return Promise.all([
			callHistory(from).catch(() => ({})),
			this.range
				? callHistory(now - 2 * this.range, now - this.range).catch(() => ({}))
				: Promise.resolve({})
		]).then(L.bind(function(data) {
			this.entries = Array.isArray(data[0].entries) ? data[0].entries : [];
			this.resolution = data[0].resolution || 'raw';
			this.prevEntries = Array.isArray(data[1].entries) ? data[1].entries : [];
			this.prevResolution = data[1].resolution || 'raw';
		}, this));
	},

	load() {
		/* Both series of a group start visible; the legend narrows it. */
		this.active = {
			speed: lscommon.GROUPS.speed.slice(),
			latency: lscommon.GROUPS.latency.slice()
		};
		return this.fetch();
	},

	/* The server/interface filters narrow the fetched range on the client;
	 * daily aggregates carry neither field, so there the filters offer only
	 * "All" and match everything. */
	applyFilters(entries) {
		return (entries || []).filter(e =>
			(!this.server || (e.server && e.server.name) == this.server) &&
			(!this.iface || e.interface == this.iface));
	},

	visible() {
		return this.applyFilters(this.entries);
	},

	filterSelect(title, values, current, onpick) {
		const sel = E('select', { 'class': 'cbi-input-select' },
			[ E('option', { 'value': '' }, [ _('All') ]) ].concat(
				values.map(v => E('option', { 'value': v }, [ v ]))));

		sel.value = values.indexOf(current) >= 0 ? current : '';
		sel.addEventListener('change', ui.createHandlerFn(this, function() {
			return onpick.call(this, sel.value);
		}));

		return E('label', {}, [
			E('span', { 'class': 'librespeed-muted' }, [ title + ' ' ]), sel ]);
	},

	/* The header above the chart doubles as the legend: per series a checkbox
	 * with its color, its average, and the change against the previous period
	 * -- one place to read the numbers and switch the lines, right where the
	 * eye already is. Below it, one sentence on how the period behaved. */
	renderSummary() {
		const entries = this.visible(),
		      prev = this.applyFilters(this.prevEntries),
		      act = this.active[this.group],
		      states = [];

		this.summaryNode.innerHTML = '';

		const row = E('div', { 'class': 'librespeed-cards' });

		lscommon.GROUPS[this.group].forEach(L.bind(function(k, ki) {
			const m = lscommon.METRICS.find(x => x[0] == k),
			      st = lscommon.seriesStats(entries, k),
			      ps = lscommon.seriesStats(prev, k),
			      on = act.indexOf(k) >= 0;

			let diff = ' ';

			/* Only comparable windows get compared: an average of raw samples
			 * against an average of daily aggregates is not the same number,
			 * and the two fetches may straddle the raw/archive boundary. */
			if (on && st && ps && ps.avg > 0 && this.prevResolution == this.resolution) {
				const pct = (st.avg - ps.avg) / ps.avg * 100;
				diff = '%s%d %% %s'.format(pct >= 0 ? '+' : '−',
					Math.abs(Math.round(pct)), _('vs previous period'));
			}

			/* The card is a label around a real checkbox, so it works from the
			 * keyboard exactly like the control it is; the dimming and the
			 * accent stripe say what is drawn. */
			const cb = E('input', { 'type': 'checkbox' });

			cb.checked = on;
			cb.addEventListener('change', L.bind(function() {
				if (cb.checked && act.indexOf(k) < 0)
					act.push(k);
				else if (!cb.checked) {
					if (act.length < 2) {
						cb.checked = true;
						return;
					}
					act.splice(act.indexOf(k), 1);
				}
				this.redraw();
			}, this));

			row.appendChild(E('label', {
				'class': 'librespeed-metric-card librespeed-accent-%d'.format(ki) +
					(on ? ' librespeed-metric-card-on' : ''),
				'title': on ? _('Hide this series') : _('Show this series')
			}, [
				E('div', { 'class': 'librespeed-muted librespeed-caps' },
					[ cb, ' ', m[1] ]),
				E('div', { 'class': 'librespeed-card-value' }, [
					st ? '%.1f'.format(st.avg) + ' ' + m[2] : '–',
					E('span', { 'class': 'librespeed-muted', 'style': 'font-size:.6em; font-weight:400' },
						[ ' ' + _('avg') ])
				]),
				E('div', { 'class': 'librespeed-muted', 'style': 'font-size:.85em' }, [ diff ])
			]));

			if (on && st) {
				const varPct = (st.max - st.min) / st.avg * 100,
				      offPct = (st.current - st.avg) / st.avg * 100;
				const bad = (k == 'ping_ms' || k == 'jitter_ms') ? offPct > 15 : offPct < -15;

				states.push([ m[1],
					bad ? _('declining') : (varPct > 30 ? _('highly variable') : _('stable')) ]);
			}
		}, this));

		this.summaryNode.appendChild(row);

		if (states.length) {
			const allStable = states.every(s => s[1] == _('stable'));
			this.summaryNode.appendChild(E('p', { 'class': 'librespeed-muted', 'style': 'margin:0 0 .25em' }, [
				allStable
					? _('Stable over the selected period.')
					: states.map(s => '%s: %s'.format(s[0], s[1])).join(' · ')
			]));
		}
	},

	redraw() {
		const entries = this.visible();

		/* Without data the empty state IS the page: everything that only
		 * makes sense with measurements -- cards, chart, table, export --
		 * stays out of the way entirely, and the one useful action is a
		 * button to go run a test. Filters that merely exclude everything
		 * get their own wording and no button: data exists, go widen them. */
		const noneAtAll = !this.entries.length;

		if (!entries.length) {
			this.emptyText.textContent = noneAtAll
				? _('Run a speed test to start building your connection history.')
				: _('No measurements match the current filters.');
			this.emptyStart.style.display = noneAtAll ? '' : 'none';
			this.emptyNode.style.display = '';
			this.dataNode.style.display = 'none';
			return;
		}

		this.emptyNode.style.display = 'none';
		this.dataNode.style.display = '';

		this.renderSummary();

		/* The legend lives in the summary header above; the chart itself has
		 * nothing below it that could be mistaken for table furniture. */
		const drew = lscommon.renderChart(this.chartNode, entries, {
			series: this.active[this.group],
			resolution: this.resolution,
			hover: true
		});

		/* Entries exist -- the empty state above handles the case where they
		 * do not -- so reaching here means this metric has no numbers. */
		if (!drew)
			this.chartNode.appendChild(E('p', { 'class': 'librespeed-muted' },
				[ _('No data for the selected metric.') ]));
		else if (this.resolution == '1d')
			this.chartNode.appendChild(E('p', { 'class': 'librespeed-muted' },
				[ _('Daily minimum, average and maximum.') ]));

		const num = v => (typeof v == 'number') ? v : -1;
		const fmtNum = (v, d) => (typeof v == 'number') ? v.toFixed(d) : '–';
		const when = e => {
			if (!e.timestamp)
				return '?';
			if (this.resolution == '1d' || e.timestamp.indexOf('T') < 0)
				return e.timestamp;
			const d = new Date(e.timestamp);
			/* A garbled timestamp shows as itself, never as "Invalid Date". */
			return isNaN(d.getTime()) ? e.timestamp : d.toLocaleString();
		};

		/* One column carries both what the packets were (IPv4/IPv6) and how
		 * they travelled (HTTPS/HTTP); either half may be unknown. */
		const protoCell = e => {
			const fam = e.family == 'ipv6' ? 'IPv6' : (e.family == 'ipv4' ? 'IPv4' : null),
			      pr = e.proto ? e.proto.toUpperCase() : null;
			return [ fam, pr ].filter(x => x).join(' · ') || '–';
		};

		const rows = entries.slice().reverse();
		const pages = Math.max(1, Math.ceil(rows.length / pageSize));

		if (this.page >= pages)
			this.page = pages - 1;

		this.renderPager(rows.length, pages);

		this.table.update(rows.slice(this.page * pageSize, (this.page + 1) * pageSize).map(e => [
			[ e.epoch ?? 0, when(e) ],
			(e.server && e.server.name) || '–',
			e.interface || '–',
			protoCell(e),
			[ num(e.download_mbps), fmtNum(e.download_mbps, 2) ],
			[ num(e.upload_mbps), fmtNum(e.upload_mbps, 2) ],
			[ num(e.ping_ms), fmtNum(e.ping_ms, 1) ],
			[ num(e.jitter_ms), fmtNum(e.jitter_ms, 1) ]
		]));
	},

	/* Shown only when there is more than one page; the count is always
	 * worth having, so it stays either way. */
	renderPager(total, pages) {
		const step = L.bind(function(delta) {
			this.page = Math.min(pages - 1, Math.max(0, this.page + delta));
			this.redraw();
		}, this);

		const nav = [ E('span', { 'class': 'librespeed-muted' },
			[ _('%d measurements').format(total) ]) ];

		if (pages > 1) {
			nav.push(E('button', {
				'class': 'cbi-button',
				'disabled': this.page > 0 ? null : '',
				'click': ui.createHandlerFn(this, function() { step(-1); })
			}, [ '\u2039 ' + _('Previous') ]));
			nav.push(E('span', { 'class': 'librespeed-muted' },
				[ _('Page %d of %d').format(this.page + 1, pages) ]));
			nav.push(E('button', {
				'class': 'cbi-button',
				'disabled': this.page < pages - 1 ? null : '',
				'click': ui.createHandlerFn(this, function() { step(1); })
			}, [ _('Next') + ' \u203a' ]));
		}

		this.pagerNode.replaceChildren(...nav);
	},

	handleExportCSV() {
		lscommon.exportCSV(this.visible(), this.resolution);
	},

	handleExportJSON() {
		lscommon.exportJSON(this.visible(), this.resolution);
	},

	render() {
		this.summaryNode = E('div', {});
		this.chartNode = E('div', {});
		this.controls = E('div', {});
		this.pagerNode = E('div', { 'class': 'librespeed-toolbar', 'style': 'margin:.5em 0' });

		/* ui.Table gives sortable headers for free -- every cell below is a
		 * [sort key, display] pair, so Time orders by epoch even though it
		 * shows a locale string, and numbers order numerically. The table is
		 * where sorting belongs; the chart above never reorders time. */
		this.table = new ui.Table([
			_('Time'), _('Server'), _('Interface'), _('Protocol'),
			_('Download [Mbps]'), _('Upload [Mbps]'), _('Ping [ms]'), _('Jitter [ms]')
		], { id: 'librespeed-history' });
		this.tableNode = this.table.render();

		const renderControls = L.bind(function() {
			const groups = lscommon.switcher(this,
				[ [ 'speed', _('Speed') ], [ 'latency', _('Latency') ] ], this.group,
				function(v) { this.group = v; renderControls(); this.redraw(); });
			const ranges = lscommon.switcher(this,
				lscommon.RANGES.map(r => [ String(r[1]), r[0] ]), String(this.range),
				function(v) {
					this.range = +v;
					this.page = 0;
					renderControls();
					return this.fetch().then(L.bind(function() {
						renderControls();
						this.redraw();
					}, this));
				});

			ranges.classList.add('librespeed-push');

			/* Filter choices are whatever the fetched range actually contains. */
			const servers = [], ifaces = [];

			this.entries.forEach(e => {
				const s = e.server && e.server.name;
				if (s && servers.indexOf(s) < 0)
					servers.push(s);
				if (e.interface && ifaces.indexOf(e.interface) < 0)
					ifaces.push(e.interface);
			});

			const filters = E('div', { 'class': 'librespeed-toolbar' }, [
				this.filterSelect(_('Server'), servers.sort(), this.server,
					function(v) { this.server = v; this.page = 0; this.redraw(); }),
				this.filterSelect(_('Interface'), ifaces.sort(), this.iface,
					function(v) { this.iface = v; this.page = 0; this.redraw(); })
			]);

			this.controls.innerHTML = '';
			this.controls.appendChild(E('div', { 'class': 'librespeed-toolbar' },
				[ groups, ranges ]));
			this.controls.appendChild(filters);
		}, this);

		this.emptyText = E('p', { 'class': 'librespeed-muted', 'style': 'margin:.5em 0 1em' });
		this.emptyStart = E('a', {
			'class': 'cbi-button cbi-button-action',
			'href': L.url('admin', 'network', 'librespeed', 'test')
		}, [ _('Start test') ]);
		this.emptyNode = E('div', {
			'class': 'cbi-section librespeed-center',
			'style': 'display:none; margin-top:1em'
		}, [
			E('div', { 'style': 'font-size:1.4em; font-weight:600' },
				[ _('No measurements yet') ]),
			this.emptyText,
			this.emptyStart
		]);

		this.dataNode = E('div', {}, [
			this.chartNode,
			this.summaryNode,
			E('h3', { 'style': 'margin-top:.75em' }, [ _('Measurements') ]),
			this.tableNode,
			this.pagerNode,
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.createHandlerFn(this, 'handleExportCSV') },
					[ _('Export CSV') ]),
				' ',
				E('button', { 'class': 'cbi-button', 'click': ui.createHandlerFn(this, 'handleExportJSON') },
					[ _('Export JSON') ])
			])
		]);

		renderControls();
		this.redraw();

		return E([], [
			lscommon.cssLink(),
			E('h2', [ _('LibreSpeed – History') ]),
			this.controls,
			this.emptyNode,
			this.dataNode
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
