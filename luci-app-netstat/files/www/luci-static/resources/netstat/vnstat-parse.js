/*
 * Turns `vnstat --json d|m` output into chart series for the Network Usage
 * tab. Handles vnStat 2 (jsonversion "2": bytes, keys "day"/"month") and the
 * older jsonversion "1" layout (KiB, keys "days"/"months").
 */
(function (root) {
	'use strict';

	var MONTHS = ['Jan','Feb','Mar','Apr','May','Jun',
	              'Jul','Aug','Sep','Oct','Nov','Dec'];

	function pad2(n) { return (n < 10 ? '0' : '') + n; }

	function dayLabel(y, m, d) {
		return pad2(d) + ' ' + MONTHS[m - 1] + ' ' + pad2(y % 100);
	}

	function monthLabel(y, m) {
		return MONTHS[m - 1] + " '" + pad2(y % 100);
	}

	function findInterface(data, name) {
		var list = (data && Array.isArray(data.interfaces)) ? data.interfaces : [];
		for (var i = 0; i < list.length; i++)
			if (list[i] && list[i].name === name) return list[i];
		return list.length === 1 ? list[0] : null;
	}

	/*
	 * data:  parsed vnStat JSON (or the raw string)
	 * iface: interface name to pick from data.interfaces
	 * mode:  'daily' | 'monthly'
	 * now:   Date used to add an empty entry for today / this month
	 *
	 * Returns { labels, rx, tx, totalRx, totalTx, entries } where entries is
	 * the number of rows vnStat actually had (0 while it is still collecting).
	 */
	function series(data, iface, mode, now) {
		var out = { labels: [], rx: [], tx: [], totalRx: 0, totalTx: 0, entries: 0 };

		if (typeof data === 'string') {
			try { data = JSON.parse(data); } catch (e) { return out; }
		}

		var ifc = findInterface(data, iface);
		if (!ifc || !ifc.traffic) return out;

		var legacy  = String(data.jsonversion) === '1';
		var scale   = legacy ? 1024 : 1;
		var monthly = mode === 'monthly';
		var key     = monthly ? (legacy ? 'months' : 'month') : (legacy ? 'days' : 'day');
		var rows    = Array.isArray(ifc.traffic[key]) ? ifc.traffic[key].slice() : [];

		rows = rows.filter(function (r) {
			return r && r.date && r.date.year && r.date.month && (monthly || r.date.day);
		});

		function sortKey(r) {
			return r.date.year * 10000 + r.date.month * 100 + (monthly ? 0 : r.date.day);
		}
		rows.sort(function (a, b) { return sortKey(a) - sortKey(b); });

		out.entries = rows.length;
		if (!rows.length) return out;

		rows.forEach(function (r) {
			var rx = (Number(r.rx) || 0) * scale;
			var tx = (Number(r.tx) || 0) * scale;
			out.labels.push(monthly ? monthLabel(r.date.year, r.date.month)
			                        : dayLabel(r.date.year, r.date.month, r.date.day));
			out.rx.push(rx);
			out.tx.push(tx);
			out.totalRx += rx;
			out.totalTx += tx;
		});

		// Always show the current period, even before any traffic was saved.
		now = now || new Date();
		var cur = monthly ? monthLabel(now.getFullYear(), now.getMonth() + 1)
		                  : dayLabel(now.getFullYear(), now.getMonth() + 1, now.getDate());
		if (out.labels.indexOf(cur) < 0) {
			out.labels.push(cur);
			out.rx.push(0);
			out.tx.push(0);
		}

		return out;
	}

	var api = { series: series, findInterface: findInterface };

	if (typeof module === 'object' && module.exports)
		module.exports = api;
	else
		root.netstatVnstat = api;
})(typeof window !== 'undefined' ? window : this);
