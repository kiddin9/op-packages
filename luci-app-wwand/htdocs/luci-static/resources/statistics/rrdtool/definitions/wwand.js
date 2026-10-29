/* Licensed to the public under the Apache License 2.0. */

/* Graph definitions for the data `wwandctl collectd` feeds into collectd.
 *
 * luci-app-statistics LISTS this directory at runtime and loads every .js it
 * finds (statistics/rrdtool.js:144,166), so this ships from luci-app-wwand
 * without patching anything over there.
 *
 * One graph per QUANTITY, never one per unit. RSRP and RSSI are both dBm and
 * mean different things — the serving cell's own power against the whole band,
 * with ladders 20 dB apart — and sharing an axis leaves the stronger one
 * flattened against the edge. That mistake was made once already in the live
 * graph and is not repeated here. Within a graph there is one line per radio
 * technology, and the colours are the live graph's, so the same radio is the
 * same colour in both places.
 */

'use strict';
'require baseclass';

const RAT = {
	lte:  '0069d9',   /* blue   */
	nr5g: '8e44ad',   /* purple */
	wcdma:'17a2b8',   /* teal   */
	gsm:  '6c757d',   /* grey   */
	any:  'e0a800',   /* amber, the band-wide fallback */
};

const LABEL = { lte: 'LTE', nr5g: '5G', wcdma: '3G', gsm: '2G' };

return baseclass.extend({
	title: _('Cellular modem'),

	rrdargs(graph, host, plugin, plugin_instance, dtype) {
		/* What this modem actually recorded. Asked rather than assumed: an
		   LTE-only modem has no 5G instances, and naming one anyway would point
		   rrdtool at a file that does not exist — `instances` is taken verbatim
		   (rrdtool.js:551). */
		const have = (type) => graph.dataInstances(host, plugin, plugin_instance, type) || [];

		const series = (type, insts, prefix, unit) => {
			const options = {};

			for (const inst of insts) {
				const rat = inst.slice(prefix.length).replace(/^_/, '');
				const key = `${type}_${inst.replace(/\W/g, '_')}_value`;

				options[key] = {
					title: rat.length ? `${unit} ${LABEL[rat] || rat}` : unit,
					color: RAT[rat] || RAT.any,
					noarea: true,
					overlay: true,
				};
			}

			return { instances: { [type]: insts }, options: options };
		};

		const pick = (type, re) => have(type).filter((i) => re.test(i));
		const out = [];

		/* serving-cell power: RSRP, and RSCP where a 3G modem reports one */
		const rsrp = pick('signal_power', /^rsrp_/);

		if (rsrp.length)
			out.push({
				title: '%H: Signal strength on %pi',
				vlabel: 'dBm',
				number_format: '%5.1lf dBm',
				data: series('signal_power', rsrp, 'rsrp', 'RSRP'),
			});

		/* band-wide power — its own graph, and its own scale: the RSSI ladder
		   sits about 20 dB above the RSRP one */
		const rssi = pick('signal_power', /^rssi/);

		if (rssi.length)
			out.push({
				title: '%H: Band power (RSSI) on %pi',
				vlabel: 'dBm',
				number_format: '%5.1lf dBm',
				data: series('signal_power', rssi, 'rssi', 'RSSI'),
			});

		/* quality: RSRQ, and Ec/Io on 3G — both dB, both negative */
		const rsrq = pick('signal_power', /^(rsrq|ecio)/);

		if (rsrq.length)
			out.push({
				title: '%H: Signal quality on %pi',
				vlabel: 'dB',
				number_format: '%5.1lf dB',
				data: series('signal_power', rsrq, 'rsrq', 'RSRQ'),
			});

		/* SINR is a `gauge`, not signal_quality: it runs roughly -20..+30 dB and
		   collectd's signal_quality has a floor of 0, which would discard every
		   negative reading. Negative SINR is not exotic — a sponsor box reported
		   -2.5 dB and -0.8 dB on two modems at once. */
		const sinr = pick('gauge', /^sinr_/);

		if (sinr.length)
			out.push({
				title: '%H: SINR on %pi',
				vlabel: 'dB',
				number_format: '%5.1lf dB',
				data: series('gauge', sinr, 'sinr', 'SINR'),
			});

		/* Aggregation, which is why anyone wants this in an RRD at all: the live
		   graph shows carriers and bandwidth for as long as a browser is open,
		   and the question people actually have ("does the second carrier come
		   back at night?") is about the hours it was not. Two graphs, not one —
		   a count runs 1..6 and a bandwidth 5..200, and an axis carrying both
		   flattens the count onto the baseline.

		   The instance names are `carriers_lte` / `carriers_nr`, so the RAT
		   suffix is `nr` here where the signal series use `nr5g`; both map to
		   the same purple through the lookup below. */
		const RAT_AGG = { lte: RAT.lte, nr: RAT.nr5g };
		const LABEL_AGG = { lte: 'LTE', nr: '5G' };

		const aggSeries = (insts, prefix, unit) => {
			const options = {};

			for (const inst of insts) {
				const rat = inst.slice(prefix.length).replace(/^_/, '');

				options[`gauge_${inst.replace(/\W/g, '_')}_value`] = {
					title: `${unit} ${LABEL_AGG[rat] || rat}`,
					color: RAT_AGG[rat] || RAT.any,
					noarea: true,
					overlay: true,
				};
			}

			return { instances: { gauge: insts }, options: options };
		};

		const carriers = pick('gauge', /^carriers_/);

		if (carriers.length)
			out.push({
				title: '%H: Aggregated carriers on %pi',
				vlabel: 'Carriers',
				number_format: '%5.0lf',
				data: aggSeries(carriers, 'carriers', 'Carriers'),
			});

		const bwidth = pick('gauge', /^bandwidth_/);

		if (bwidth.length)
			out.push({
				title: '%H: Aggregate bandwidth on %pi',
				vlabel: 'MHz',
				number_format: '%5.0lf MHz',
				data: aggSeries(bwidth, 'bandwidth', 'MHz'),
			});

		if (have('temperature').length)
			out.push({
				title: '%H: Modem temperature on %pi',
				vlabel: 'C',
				number_format: '%5.1lf C',
				data: {
					types: [ 'temperature' ],
					options: { temperature: { title: 'Temperature', color: 'ff6600', noarea: true } },
				},
			});

		/* state and the recovery counters on one axis: `registered` and
		   `connected` are 0/1, and a rising `attempts` beside a flat 0 is the
		   picture of an outage nobody was watching */
		const state = pick('gauge', /^(registered|connected|attempts|proto_errors)$/);

		if (state.length) {
			const options = {};

			for (const inst of state)
				options[`gauge_${inst}_value`] = {
					title: inst,
					color: inst == 'registered' || inst == 'connected' ? '00a000' : 'cc0000',
					noarea: true,
					overlay: true,
				};

			out.push({
				title: '%H: State on %pi',
				vlabel: 'Count',
				number_format: '%5.0lf',
				data: { instances: { gauge: state }, options: options },
			});
		}

		return out;
	}
});
