'use strict';
'require baseclass';

/* Time series kept in the browser for the session, and the SVG path
   geometry to draw them. A series is an array of [ t (ms), v0, v1, ... ]
   in strictly increasing t. Pure functions. */

function finite(v) { return typeof v === 'number' && isFinite(v); }
function r1(v) { return Math.round(v * 10) / 10; }

return baseclass.extend({
	/* append, keeping entries newer than now - windowMs and at most max */
	push: function(series, point, windowMs, max) {
		var out = Array.isArray(series) ? series : [];
		if (!Array.isArray(point) || !finite(point[0])) return out;
		if (out.length && out[out.length - 1][0] >= point[0]) return out;
		out.push(point);
		var cutoff = point[0] - (windowMs > 0 ? windowMs : Infinity);
		while (out.length && (out[0][0] < cutoff || (max > 0 && out.length > max))) out.shift();
		return out;
	},

	/* Stored series (sessionStorage) are untrusted: keep arrays of exactly
	   `width` finite numbers with values >= 0 (except t), strictly
	   increasing t, nothing after notAfter, at most maxLen (newest). */
	valid: function(arr, width, maxLen, notAfter) {
		if (!Array.isArray(arr)) return [];
		var out = [], lastT = -Infinity;
		for (var i = 0; i < arr.length; i++) {
			var p = arr[i], ok = Array.isArray(p) && p.length === width;
			for (var j = 0; ok && j < width; j++) ok = finite(p[j]) && (j === 0 || p[j] >= 0);
			if (!ok || p[0] <= lastT || (notAfter != null && p[0] > notAfter)) continue;
			out.push(p.slice());
			lastT = p[0];
		}
		return out.length > maxLen ? out.slice(out.length - maxLen) : out;
	},

	/* a round axis maximum >= v: 1, 2, 2.5, 5 x 10^n */
	niceMax: function(v) {
		if (!finite(v) || v <= 0) return 1;
		var e = Math.pow(10, Math.floor(Math.log10(v))), f = v / e;
		var n = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
		return n * e;
	},

	/* a round axis maximum >= v with finer steps (1, 1.5, 2, 2.5, 3, 4,
	   5, 6, 8, 10 x 10^n), so a 374 Mbit/s peak gets a 400 axis, not 500 */
	niceCeil: function(v) {
		if (!finite(v) || v <= 0) return 1;
		var e = Math.pow(10, Math.floor(Math.log10(v))), f = v / e;
		var steps = [ 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 ];
		for (var i = 0; i < steps.length; i++)
			if (f <= steps[i] * (1 + 1e-9)) return steps[i] * e;
		return 10 * e;
	},

	/* { now, peak, avg, n } of column idx over points with t >= t0 (now:
	   the newest finite value); nulls when there is no point */
	stats: function(series, idx, t0) {
		var n = 0, sum = 0, peak = null, now = null;
		(series || []).forEach(function(p) {
			if (!Array.isArray(p) || !finite(p[idx]) || (t0 != null && p[0] < t0)) return;
			n++; sum += p[idx];
			if (peak == null || p[idx] > peak) peak = p[idx];
			now = p[idx];
		});
		return { now: now, peak: peak, avg: n ? sum / n : null, n: n };
	},

	/* Time domain of a chart that fills in while history accumulates:
	   [t1 - span, t1] where span is the age of the oldest point (of any
	   of the series) clamped to [minMs, maxMs]. age: of the oldest point;
	   full: the whole window is covered. -> { t0, t1, span, age, full } */
	domain: function(list, t1, minMs, maxMs) {
		var first = Infinity;
		(list || []).forEach(function(sr) {
			(sr || []).forEach(function(p) { if (Array.isArray(p) && finite(p[0]) && p[0] < first) first = p[0]; });
		});
		var span = isFinite(first) ? Math.max(minMs, Math.min(maxMs, t1 - first)) : minMs;
		return { t0: t1 - span, t1: t1, span: span, age: isFinite(first) ? Math.min(maxMs, t1 - first) : 0, full: span >= maxMs - 1000 };
	},

	/* max over columns idx of the series (for a shared y scale) */
	max: function(series, idx) {
		var m = 0;
		(series || []).forEach(function(p) {
			idx.forEach(function(i) { if (finite(p[i]) && p[i] > m) m = p[i]; });
		});
		return m;
	},

	/* Screen points of column idx within a w x h box: x by time over
	   [t0, t1], y by value over [0, vmax] (0 at the bottom). A gap longer
	   than maxGap ms starts a new segment. -> [ [ [x, y], ... ], ... ] */
	segments: function(series, idx, t0, t1, vmax, w, h, maxGap) {
		var segs = [], cur = null, lastT = null, span = (t1 - t0) || 1;
		vmax = vmax > 0 ? vmax : 1;
		(series || []).forEach(function(p) {
			var v = p[idx];
			if (!finite(v) || p[0] < t0 - (maxGap || 0)) { cur = null; return; }
			if (cur && maxGap && lastT != null && p[0] - lastT > maxGap) cur = null;
			if (!cur) { cur = []; segs.push(cur); }
			var x = (p[0] - t0) / span * w, y = h - Math.min(1, Math.max(0, v / vmax)) * h;
			cur.push([ r1(x), r1(y) ]);
			lastT = p[0];
		});
		return segs;
	},

	/* 'M x y L x y ...' for line segments */
	linePath: function(segs) {
		return (segs || []).filter(function(s) { return s.length > 0; }).map(function(s) {
			if (s.length === 1) return 'M' + s[0][0] + ' ' + s[0][1] + 'h0.1';
			return 'M' + s.map(function(pt) { return pt[0] + ' ' + pt[1]; }).join('L');
		}).join('');
	},

	/* closed area down to the baseline y = h */
	areaPath: function(segs, h) {
		return (segs || []).filter(function(s) { return s.length > 1; }).map(function(s) {
			return 'M' + s[0][0] + ' ' + h + 'L' + s.map(function(pt) { return pt[0] + ' ' + pt[1]; }).join('L') +
				'L' + s[s.length - 1][0] + ' ' + h + 'Z';
		}).join('');
	},

	/* index of the point closest in time to t (for hover), or -1 */
	nearest: function(series, t) {
		var best = -1, bd = Infinity;
		(series || []).forEach(function(p, i) {
			var d = Math.abs(p[0] - t);
			if (d < bd) { bd = d; best = i; }
		});
		return best;
	}
});
