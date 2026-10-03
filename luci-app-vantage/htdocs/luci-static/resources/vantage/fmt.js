'use strict';
'require baseclass';

/* Number and text formatting for the Vantage dashboard. Pure functions:
   no DOM, no rpc. Every function accepts junk (null, strings, NaN) and
   returns a placeholder instead of "NaN" or "undefined". */

var DASH = '—';

function num(v) { if (v == null || v === '') return null; v = +v; return isFinite(v) ? v : null; }

/* 3 significant digits, at most 2 decimals: 1.23, 12.3, 123 */
function sig3(v) {
	return v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2).replace(/\.?0+$/, '') || '0';
}

/* Characters that reorder or hide text (bidi controls, zero-width, C0/C1
   controls, fillers, tag characters). Client-chosen names and SSIDs may
   carry them; they become a visible replacement mark. ZWJ/ZWNJ and the
   emoji presentation selectors are kept. */
var UNSAFE_TEXT = /[\u0000-\u001f\u007f-\u009f\u00ad\u034f\u061c\u115f\u1160\u17b4\u17b5\u180e\u200b\u200e\u200f\u2028-\u202e\u2060-\u206f\u3164\ufe00-\ufe0d\ufeff\uffa0\ufff9-\ufffb]|\uDB40[\uDC00-\uDC7F]/g;

return baseclass.extend({
	DASH: DASH,

	/* bits per second -> { v: '372', u: 'Mbit/s' } */
	bitsParts: function(bps) {
		bps = num(bps);
		if (bps == null || bps < 0) return { v: DASH, u: '' };
		var u = [ _('bit/s'), _('kbit/s'), _('Mbit/s'), _('Gbit/s'), _('Tbit/s') ], i = 0;
		while (bps >= 1000 && i < u.length - 1) { bps /= 1000; i++; }
		return { v: i === 0 ? bps.toFixed(0) : sig3(bps), u: u[i] };
	},

	bits: function(bps) {
		var p = this.bitsParts(bps);
		return p.u ? p.v + ' ' + p.u : p.v;
	},

	/* compact axis label: 400M, 1.5G, 20k */
	bitsShort: function(bps) {
		bps = num(bps);
		if (bps == null || bps <= 0) return '0';
		var u = [ '', 'k', 'M', 'G', 'T' ], i = 0;
		while (bps >= 1000 && i < u.length - 1) { bps /= 1000; i++; }
		return (bps >= 10 ? bps.toFixed(0) : String(+bps.toFixed(1))) + u[i];
	},

	/* binary units for memory/storage */
	bytes: function(b) {
		b = num(b);
		if (b == null || b < 0) return DASH;
		var u = [ _('B'), _('KiB'), _('MiB'), _('GiB'), _('TiB'), _('PiB') ], i = 0;
		while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
		return (i === 0 ? b.toFixed(0) : b >= 100 ? b.toFixed(0) : b >= 10 ? b.toFixed(1) : b.toFixed(2)) + ' ' + u[i];
	},

	/* PHY rate from iwinfo (kbit/s) -> '576 Mbit/s' */
	phyRate: function(kbit) {
		kbit = num(kbit);
		if (kbit == null || kbit <= 0) return DASH;
		return this.bits(kbit * 1000);
	},

	pct: function(p, digits) {
		p = num(p);
		if (p == null) return DASH;
		return p.toFixed(digits || 0) + '%';
	},

	/* seconds -> '5d 23h', '4h 12m', '3m 20s', '12s' */
	duration: function(s) {
		s = num(s);
		if (s == null || s < 0) return DASH;
		s = Math.floor(s);
		var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
		if (d) return d + 'd ' + h + 'h';
		if (h) return h + 'h ' + m + 'm';
		if (m) return m + 'm ' + (s % 60) + 's';
		return s + 's';
	},

	/* milliseconds since -> 'just now', '12 s ago', '3 min ago' */
	ago: function(ms) {
		ms = num(ms);
		if (ms == null || ms < 0) return DASH;
		var s = Math.round(ms / 1000);
		if (s < 3) return _('just now');
		if (s < 60) return _('%d s ago').format(s);
		if (s < 3600) return _('%d min ago').format(Math.floor(s / 60));
		return _('%d h ago').format(Math.floor(s / 3600));
	},

	dbm: function(v) {
		v = num(v);
		if (v == null || v === 0) return DASH;
		return (v < 0 ? '−' + Math.abs(v) : String(v)) + ' ' + _('dBm');
	},

	/* load average as reported by system.info (fixed point, 65536 = 1.0) */
	load: function(v) {
		v = num(v);
		return v == null ? DASH : (v / 65536).toFixed(2);
	},

	/* upper-case, colon separated; anything else is returned unchanged */
	mac: function(mac) {
		var s = String(mac == null ? '' : mac).trim();
		return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(s) ? s.replace(/-/g, ':').toUpperCase() : s;
	},

	/* last three octets: '…00:53:C1' (the distinguishing part of a MAC) */
	macTail: function(mac) {
		var m = this.mac(mac);
		return /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(m) ? '…' + m.slice(9) : m;
	},

	/* Client- or radio-supplied text for display: invisible/reordering
	   characters become U+FFFD and long values are cut (by code point) with
	   an ellipsis. The result is still only ever used as a text node. */
	safeText: function(s, maxLen) {
		if (s == null) return '';
		var chars = Array.from(String(s).replace(UNSAFE_TEXT, '\ufffd'));
		maxLen = maxLen > 1 ? maxLen : 64;
		return chars.length > maxLen ? chars.slice(0, maxLen - 1).join('') + '…' : chars.join('');
	},

	/* frequency MHz -> '5975 MHz' / '5.975 GHz' is less readable; keep MHz */
	mhz: function(v) {
		v = num(v);
		return v ? _('%s MHz').format(v) : DASH;
	}
});
