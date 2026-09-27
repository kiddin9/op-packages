'use strict';
'require baseclass';

// ─── State ────────────────────────────────────────────────────────────────────
let prev        = {};
let last_time   = Date.now();
let _pollAdded  = false;
let _container  = null;

// Peak speeds per direction (bits/s)
let peakRx = 0;
let peakTx = 0;

// Previous speeds for trending arrows
let lastRxSpeed = 0;
let lastTxSpeed = 0;

// Sparkline history – last 30 samples (~60 s at 2 s poll)
const SPARK_LEN = 30;
let sparkRx = new Array(SPARK_LEN).fill(0);
let sparkTx = new Array(SPARK_LEN).fill(0);

// ─── CSS Loader (theme-aware, no busy-poll) ───────────────────────────────────
(function loadDynamicCSS() {
	let loadedCss = null;

	function isDarkMode() {
		try {
			const bg  = getComputedStyle(document.body).backgroundColor;
			if (!bg || bg === 'transparent') return false;
			const rgb = bg.match(/\d+/g);
			if (!rgb || rgb.length < 3) return false;
			const [r, g, b] = rgb.map(Number);
			return (r * 299 + g * 587 + b * 114) / 1000 < 100;
		} catch (_) { return false; }
	}

	function applyCSS() {
		const file = isDarkMode() ? 'netstat_dark.css' : 'netstat.css';
		if (loadedCss === file) return;
		loadedCss = file;

		document.querySelectorAll('link[data-netstat-css]').forEach(l => l.remove());

		const link       = document.createElement('link');
		link.rel         = 'stylesheet';
		link.setAttribute('data-netstat-css', '1');
		link.href        = '/luci-static/resources/netstat/' + file + '?t=' + Date.now();
		document.head.appendChild(link);
	}

	requestAnimationFrame(() => setTimeout(applyCSS, 50));

	if (window.matchMedia) {
		window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyCSS);
	}

	const mo = new MutationObserver(applyCSS);
	const waitForBody = setInterval(() => {
		if (!document.body) return;
		clearInterval(waitForBody);
		mo.observe(document.body, { attributes: true, attributeFilter: ['style', 'class'] });
		applyCSS();
	}, 50);
})();

// ─── Helpers ──────────────────────────────────────────────────────────────────
function parseNetdev(raw) {
	const stats = {};
	for (const line of raw.split('\n')) {
		const m = line.trim().match(/^([^:]+):\s+(.*)$/);
		if (!m) continue;
		const vals = m[2].trim().split(/\s+/).map(v => parseInt(v) || 0);
		if (vals.length >= 9)
			stats[m[1].trim()] = { rx: vals[0], tx: vals[8] };
	}
	return stats;
}

function getBestWAN(stats, preferred) {
	for (const i of preferred) if (stats[i]) return i;

	const dynamic = Object.keys(stats).find(i =>
		/^(wwan|usb|ppp|lte|qmi|modem)/.test(i) && i.includes('_'));
	if (dynamic) return dynamic;

	for (const i of ['pppoe-wan','lte0','usb0','wan','eth1','tun0','wg0'])
		if (stats[i]) return i;

	return Object.keys(stats).find(k => k !== 'lo') || '';
}

function formatRate(bps) {
	const units = ['Bps','Kbps','Mbps','Gbps'];
	let i = 0;
	while (bps >= 1000 && i < units.length - 1) { bps /= 1000; i++; }
	return { number: bps.toFixed(i > 0 ? 1 : 0), unit: units[i] + '/s' };
}

function formatBytes(v) {
	if (v >= 1099511627776) return (v / 1099511627776).toFixed(2) + ' TB';
	if (v >= 1073741824)   return (v / 1073741824).toFixed(2) + ' GB';
	if (v >= 1048576)      return (v / 1048576).toFixed(2) + ' MB';
	if (v >= 1024)         return (v / 1024).toFixed(2) + ' KB';
	return v + ' B';
}

function formatUptime(sec) {
	const d = Math.floor(sec / 86400);
	const h = Math.floor((sec % 86400) / 3600);
	const m = Math.floor((sec % 3600) / 60);
	if (d > 0) return d + 'd ' + h + 'h';
	if (h > 0) return h + 'h ' + m + 'm';
	return m + 'm ' + (sec % 60) + 's';
}

// trend arrow: +1 = rising, -1 = falling, 0 = stable
function trendArrow(current, previous) {
	const ratio = previous > 0 ? current / previous : 1;
	if (ratio > 1.10) return { char: '▲', cls: 'ns-trend-up' };
	if (ratio < 0.90) return { char: '▼', cls: 'ns-trend-down' };
	return { char: '●', cls: 'ns-trend-flat' };
}

// ─── Sparkline SVG ────────────────────────────────────────────────────────────
function drawSparkline(values, colorVar) {
	const W = 90, H = 28;
	const max = Math.max(...values, 1);
	const step = W / (values.length - 1);

	const points = values.map((v, i) => {
		const x = i * step;
		const y = H - (v / max) * (H - 2) - 1;
		return x.toFixed(1) + ',' + y.toFixed(1);
	}).join(' ');

	// filled area path
	const areaPoints =
		'0,' + H + ' ' + points + ' ' + (W) + ',' + H;

	const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	svg.setAttribute('width', W);
	svg.setAttribute('height', H);
	svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
	svg.style.display = 'block';
	svg.style.overflow = 'visible';

	const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
	const grad = document.createElementNS('http://www.w3.org/2000/svg', 'linearGradient');
	grad.setAttribute('id', 'sg-' + colorVar.replace(/[^a-z]/gi,''));
	grad.setAttribute('x1', '0'); grad.setAttribute('y1', '0');
	grad.setAttribute('x2', '0'); grad.setAttribute('y2', '1');

	const s1 = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
	s1.setAttribute('offset', '0%');
	s1.setAttribute('stop-color', 'var(' + colorVar + ')');
	s1.setAttribute('stop-opacity', '0.35');
	const s2 = document.createElementNS('http://www.w3.org/2000/svg', 'stop');
	s2.setAttribute('offset', '100%');
	s2.setAttribute('stop-color', 'var(' + colorVar + ')');
	s2.setAttribute('stop-opacity', '0.03');

	grad.appendChild(s1); grad.appendChild(s2);
	defs.appendChild(grad); svg.appendChild(defs);

	const area = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
	area.setAttribute('points', areaPoints);
	area.setAttribute('fill', 'url(#sg-' + colorVar.replace(/[^a-z]/gi,'') + ')');
	svg.appendChild(area);

	const line = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
	line.setAttribute('points', points);
	line.setAttribute('fill', 'none');
	line.setAttribute('stroke', 'var(' + colorVar + ')');
	line.setAttribute('stroke-width', '1.5');
	line.setAttribute('stroke-linejoin', 'round');
	line.setAttribute('stroke-linecap', 'round');
	svg.appendChild(line);

	return svg;
}

// Replace sparkline SVG inside a container (identified by class)
function updateSparkline(container, cls, values, colorVar) {
	const box = container.querySelector('.' + cls);
	if (!box) return;
	const wrap = box.querySelector('.ns-spark');
	if (!wrap) return;
	wrap.innerHTML = '';
	wrap.appendChild(drawSparkline(values, colorVar));
}

// ─── Fetch with timeout ───────────────────────────────────────────────────────
function fetchWithTimeout(url, ms) {
	const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
	const tid   = ctrl ? setTimeout(() => ctrl.abort(), ms) : null;
	return fetch(url, ctrl ? { signal: ctrl.signal } : {})
		.then(r => r.json())
		.finally(() => tid && clearTimeout(tid));
}

// ─── DOM builders ─────────────────────────────────────────────────────────────
function createRateBox(label, value, unit, extraClass, colorVar, sparkValues, peak) {
	const cls = 'netstat-box ' + extraClass;
	const peakFmt = formatRate(peak * 8);

	const box = E('div', { class: cls }, [
		E('div', { class: 'ns-spark' }),   // sparkline goes here
		E('div', { class: 'ns-rate-row' }, [
			E('div', { class: 'netstat-number' }, value),
			E('div', { class: 'netstat-unit' }, unit)
		]),
		E('div', { class: 'ns-peak' }, _('Peak') + ': ' + peakFmt.number + ' ' + peakFmt.unit),
		E('div', { class: 'netstat-label' }, label)
	]);

	// draw initial sparkline
	const wrap = box.querySelector('.ns-spark');
	wrap.appendChild(drawSparkline(sparkValues, colorVar));

	return box;
}

function createStatBox(label, value, unit, extraClass) {
	const cls = 'netstat-box' + (extraClass ? ' ' + extraClass : '');
	const box = E('div', { class: cls }, [
		E('div', { class: 'ns-stat-value-row' }, [
			E('div', { class: 'netstat-number' }, value),
			unit ? E('div', { class: 'netstat-unit' }, unit) : null
		].filter(Boolean)),
		E('div', { class: 'netstat-label' }, label)
	]);
	return box;
}


function createStatusCard(status, ip) {
	const up = status === 'Connected';
	return E('div', { class: 'netstat-box netstat-center ' + (up ? 'is-up' : 'is-down') }, [
		E('div', { class: 'netstat-center-title' }, _('Internet')),
		E('div', { class: 'netstat-center-status' }, up ? _('Connected') : _('Disconnected')),
		E('div', { class: 'netstat-center-sep' }),
		E('div', { class: 'netstat-center-title' }, _('IP')),
		E('div', { class: 'netstat-center-ip' }, ip || 'N/A'),
	]);
}

// ─── Inline SVG icons ─────────────────────────────────────────────────────────
function svgIcon(path, color) {
	const ns = 'http://www.w3.org/2000/svg';
	const svg = document.createElementNS(ns, 'svg');
	svg.setAttribute('viewBox', '0 0 24 24');
	svg.setAttribute('width', '16');
	svg.setAttribute('height', '16');
	svg.setAttribute('fill', 'none');
	svg.setAttribute('stroke', color || 'currentColor');
	svg.setAttribute('stroke-width', '2');
	svg.setAttribute('stroke-linecap', 'round');
	svg.setAttribute('stroke-linejoin', 'round');
	svg.style.flexShrink = '0';
	svg.innerHTML = path;
	return svg;
}

// clock icon
function iconUptime() {
	return svgIcon('<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>', 'var(--ns-muted)');
}
// database/memory icon
function iconMem() {
	return svgIcon('<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4.03 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4.03 3 9 3s9-1.34 9-3"/>', 'var(--ns-mem-color)');
}
// thermometer/temperature icon
function iconTemp() {
	return svgIcon('<path d="M14 14.76V3.5a2.5 2.5 0 0 0-5 0v11.26a4.5 4.5 0 1 0 5 0z"/>', 'var(--ns-temp-color)');
}
// hard-drive/disk icon
function iconDisk() {
	return svgIcon('<line x1="22" y1="12" x2="2" y2="12"/><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" y1="16" x2="6.01" y2="16"/><line x1="10" y1="16" x2="10.01" y2="16"/>', 'var(--ns-disk-color)');
}

// Pill-style bar: filled background + "used MB / total MB (pct%)" text overlay
function makePillBar(pct, used, total, fillId, textId) {
	const clampedPct = Math.min(100, Math.max(0, pct));
	const fill = E('div', { class: 'ns-pill-fill', id: fillId });
	fill.style.width = clampedPct + '%';
	const label = E('span', { class: 'ns-pill-text', id: textId },
		used + ' / ' + total + ' (' + clampedPct + '%)');
	return E('div', { class: 'ns-pill-bar' }, [fill, label]);
}

// Card 1: RAM + Storage pill bars
function createInfoCard(memPct, memUsed, memTotal, diskPct, diskUsed, diskTotal) {
	const card = E('div', { class: 'netstat-box netstat-info-card' });

	// RAM row
	const memRow = E('div', { class: 'ns-info-row' });
	memRow.appendChild(iconMem());
	const memBlock = E('div', { class: 'ns-info-block ns-info-block-grow' });
	memBlock.appendChild(E('div', { class: 'ns-info-tag' }, _('RAM')));
	memBlock.appendChild(makePillBar(memPct,
		memUsed + ' MB', memTotal + ' MB', 'ns-mem-bar', 'ns-mem-sub'));
	memRow.appendChild(memBlock);
	card.appendChild(memRow);

	card.appendChild(E('div', { class: 'netstat-center-sep' }));

	// Storage row
	const diskRow = E('div', { class: 'ns-info-row' });
	diskRow.appendChild(iconDisk());
	const diskBlock = E('div', { class: 'ns-info-block ns-info-block-grow' });
	diskBlock.appendChild(E('div', { class: 'ns-info-tag' }, _('STORAGE')));
	diskBlock.appendChild(makePillBar(diskPct,
		diskUsed + ' MB', diskTotal + ' MB', 'ns-disk-bar', 'ns-disk-sub'));
	diskRow.appendChild(diskBlock);
	card.appendChild(diskRow);

	return card;
}

// Card 2: CPU Temperature + Uptime
function createTempCard(cpuTemp, uptime) {
	const card = E('div', { class: 'netstat-box netstat-info-card' });

	// Temp row
	const tempRow = E('div', { class: 'ns-info-row' });
	tempRow.appendChild(iconTemp());
	const tempBlock = E('div', { class: 'ns-info-block ns-info-block-grow' });
	const tempVal = cpuTemp != null ? cpuTemp + '°C' : 'N/A';
	tempBlock.appendChild(E('div', { class: 'ns-info-value ns-temp-val', id: 'ns-temp-val' }, tempVal));
	tempBlock.appendChild(E('div', { class: 'ns-info-tag' }, _('CPU TEMP')));
	tempRow.appendChild(tempBlock);
	card.appendChild(tempRow);

	card.appendChild(E('div', { class: 'netstat-center-sep' }));

	// Uptime row
	const uptimeRow = E('div', { class: 'ns-info-row' });
	uptimeRow.appendChild(iconUptime());
	const uptimeBlock = E('div', { class: 'ns-info-block ns-info-block-grow' });
	uptimeBlock.appendChild(E('div', { class: 'ns-info-value', id: 'ns-uptime-val' }, uptime));
	uptimeBlock.appendChild(E('div', { class: 'ns-info-tag' }, _('UPTIME')));
	uptimeRow.appendChild(uptimeBlock);
	card.appendChild(uptimeRow);

	return card;
}

// ─── In-place DOM patch ───────────────────────────────────────────────────────
function patchText(el, sel, val) {
	const n = el && el.querySelector(sel);
	if (n && n.textContent !== val) n.textContent = val;
}

function updateContainer(container, data, dt) {
	const stats     = data.stats || {};
	const preferred = data.preferred || [];
	const iface     = getBestWAN(stats, preferred);
	const curr      = stats[iface] || { rx: 0, tx: 0 };
	curr.rx = parseInt(curr.rx) || 0;
	curr.tx = parseInt(curr.tx) || 0;

	const ps       = prev[iface] || { rx: curr.rx, tx: curr.tx };
	const rxSpeed  = Math.max(0, (curr.rx - ps.rx) / dt);
	const txSpeed  = Math.max(0, (curr.tx - ps.tx) / dt);
	prev[iface]    = { rx: curr.rx, tx: curr.tx };

	// peaks
	if (rxSpeed > peakRx) peakRx = rxSpeed;
	if (txSpeed > peakTx) peakTx = txSpeed;

	// sparkline ring buffers
	sparkRx.push(rxSpeed); if (sparkRx.length > SPARK_LEN) sparkRx.shift();
	sparkTx.push(txSpeed); if (sparkTx.length > SPARK_LEN) sparkTx.shift();

	// trend
	const tRx = trendArrow(rxSpeed, lastRxSpeed);
	const tTx = trendArrow(txSpeed, lastTxSpeed);
	lastRxSpeed = rxSpeed;
	lastTxSpeed = txSpeed;

	const rxRate  = formatRate(rxSpeed * 8);
	const txRate  = formatRate(txSpeed * 8);
	const totalRx = formatBytes(curr.rx).split(' ');
	const totalTx = formatBytes(curr.tx).split(' ');
	const peakRxFmt = formatRate(peakRx * 8);
	const peakTxFmt = formatRate(peakTx * 8);

	const boxes = container.querySelectorAll('.netstat-box');
	if (boxes.length < 7) return false; // stale, rebuild

	// download rate box
	patchText(container, '.is-download .netstat-number', rxRate.number);
	patchText(container, '.is-download .netstat-unit',   rxRate.unit);
	patchText(container, '.is-download .ns-peak',
		_('Peak') + ': ' + peakRxFmt.number + ' ' + peakRxFmt.unit);

	// trend on download
	const dlTrend = container.querySelector('.is-download .ns-trend');
	if (dlTrend) { dlTrend.textContent = tRx.char; dlTrend.className = 'ns-trend ' + tRx.cls; }

	// upload rate box
	patchText(container, '.is-upload .netstat-number', txRate.number);
	patchText(container, '.is-upload .netstat-unit',   txRate.unit);
	patchText(container, '.is-upload .ns-peak',
		_('Peak') + ': ' + peakTxFmt.number + ' ' + peakTxFmt.unit);

	// trend on upload
	const ulTrend = container.querySelector('.is-upload .ns-trend');
	if (ulTrend) { ulTrend.textContent = tTx.char; ulTrend.className = 'ns-trend ' + tTx.cls; }

	// sparklines
	updateSparkline(container, 'is-download', sparkRx, '--ns-dl-color');
	updateSparkline(container, 'is-upload',   sparkTx, '--ns-ul-color');

	// center status card
	const center = container.querySelector('.netstat-center');
	if (center) {
		const up = (data.status || '') === 'Connected';
		center.className = 'netstat-box netstat-center ' + (up ? 'is-up' : 'is-down');
		patchText(center, '.netstat-center-status', up ? _('Connected') : _('Disconnected'));
		patchText(center, '.netstat-center-ip',     data.ip || 'N/A');
	}

	// totals
	const totals = container.querySelectorAll('.is-total');
	if (totals[0]) {
		patchText(totals[0], '.netstat-number', totalRx[0]);
		patchText(totals[0], '.netstat-unit',   totalRx[1] || '');
	}
	if (totals[1]) {
		patchText(totals[1], '.netstat-number', totalTx[0]);
		patchText(totals[1], '.netstat-unit',   totalTx[1] || '');
	}

	// uptime in status card
	patchText(container, '#ns-uptime-val', formatUptime(data.uptime || 0));

	// temp
	const tempVal = data.cpu_temp != null ? data.cpu_temp + '°C' : 'N/A';
	patchText(container, '#ns-temp-val', tempVal);

	// pill bar: update fill width + text label
	const memPct  = data.mem_pct  || 0;
	const diskPct = data.disk_pct || 0;

	const memFill = container.querySelector('#ns-mem-bar');
	if (memFill) memFill.style.width = Math.min(100, Math.max(0, memPct)) + '%';
	patchText(container, '#ns-mem-sub',
		(data.mem_used || 0) + ' MB / ' + (data.mem_total || 0) + ' MB (' + memPct + '%)');

	const diskFill = container.querySelector('#ns-disk-bar');
	if (diskFill) diskFill.style.width = Math.min(100, Math.max(0, diskPct)) + '%';
	patchText(container, '#ns-disk-sub',
		(data.disk_used || 0) + ' MB / ' + (data.disk_total || 0) + ' MB (' + diskPct + '%)');

	return true;
}

// ─── Cached public IP (refreshed every 60 s, not on every 2 s poll) ──────────
let _cachedIp        = 'N/A';
let _lastIpFetch     = 0;
const IP_REFRESH_MS  = 300000;

function maybeRefreshIp() {
	const now = Date.now();
	if (now - _lastIpFetch < IP_REFRESH_MS) return;
	_lastIpFetch = now;
	// Full fetch (no ?fast=1) to get public IP; update cache on success
	fetchWithTimeout('/cgi-bin/luci/admin/tools/get_netdev_stats', 8000)
		.then(r => { if (r && r.ip && r.ip !== 'N/A') _cachedIp = r.ip; })
		.catch(() => {});
}

// ─── Main baseclass ───────────────────────────────────────────────────────────
return baseclass.extend({
	title: _(''),

	load() {
		// Use ?fast=1 to skip slow public-IP APIs — response is near-instant
		return fetchWithTimeout('/cgi-bin/luci/admin/tools/get_netdev_stats?fast=1', 5000)
			.then(r => {
				// Seed the cached IP from the local WAN address on first load
				if (r && r.ip && r.ip !== 'N/A') _cachedIp = r.ip;
				return {
					stats:      (r && r.stats)       || {},
					ip:         _cachedIp,
					status:     (r && r.status)      || 'Disconnected',
					uptime:     (r && r.uptime)      || 0,
					cpu_pct:    (r && r.cpu_pct)     || 0,
					cpu_temp:   (r && r.cpu_temp)    != null ? r.cpu_temp : null,
					mem_pct:    (r && r.mem_pct)     || 0,
					mem_used:   (r && r.mem_used)    || 0,
					mem_total:  (r && r.mem_total)   || 0,
					disk_pct:   (r && r.disk_pct)    || 0,
					disk_used:  (r && r.disk_used)   || 0,
					disk_total: (r && r.disk_total)  || 0,
					preferred:  (r && r.prefer_iface) ? [r.prefer_iface] : []
				};
			})
			.catch(() => ({ stats: {}, ip: 'N/A', status: 'Disconnected',
			                uptime: 0, cpu_pct: 0, cpu_temp: null, mem_pct: 0, mem_used: 0, mem_total: 0,
			                disk_pct: 0, disk_used: 0, disk_total: 0, preferred: [] }));
	},

	render(data) {
		const now  = Date.now();
		const dt   = Math.max(0.1, (now - last_time) / 1000);
		last_time  = now;

		const stats     = data.stats || {};
		const preferred = data.preferred || [];

		if (!stats || typeof stats !== 'object' || Array.isArray(stats))
			return E('div', { style: 'padding:20px;text-align:center;color:#999;font-size:13px' },
				_('Loading network stats...'));

		const iface    = getBestWAN(stats, preferred);
		const curr     = stats[iface] || { rx: 0, tx: 0 };
		curr.rx = parseInt(curr.rx) || 0;
		curr.tx = parseInt(curr.tx) || 0;

		const ps       = prev[iface] || { rx: curr.rx, tx: curr.tx };
		const rxSpeed  = Math.max(0, (curr.rx - ps.rx) / dt);
		const txSpeed  = Math.max(0, (curr.tx - ps.tx) / dt);
		prev[iface]    = { rx: curr.rx, tx: curr.tx };

		if (rxSpeed > peakRx) peakRx = rxSpeed;
		if (txSpeed > peakTx) peakTx = txSpeed;

		sparkRx.push(rxSpeed); if (sparkRx.length > SPARK_LEN) sparkRx.shift();
		sparkTx.push(txSpeed); if (sparkTx.length > SPARK_LEN) sparkTx.shift();

		const tRx = trendArrow(rxSpeed, lastRxSpeed);
		const tTx = trendArrow(txSpeed, lastTxSpeed);
		lastRxSpeed = rxSpeed;
		lastTxSpeed = txSpeed;

		const rxRate  = formatRate(rxSpeed * 8);
		const txRate  = formatRate(txSpeed * 8);
		const totalRx = formatBytes(curr.rx).split(' ');
		const totalTx = formatBytes(curr.tx).split(' ');

		// Build download box manually to inject trend badge
		const dlBox = createRateBox(_('download'), rxRate.number, rxRate.unit,
			'is-download', '--ns-dl-color', [...sparkRx], peakRx);
		const dlTrend = E('span', { class: 'ns-trend ' + tRx.cls }, tRx.char);
		dlBox.querySelector('.ns-rate-row').appendChild(dlTrend);

		const ulBox = createRateBox(_('upload'), txRate.number, txRate.unit,
			'is-upload', '--ns-ul-color', [...sparkTx], peakTx);
		const ulTrend = E('span', { class: 'ns-trend ' + tTx.cls }, tTx.char);
		ulBox.querySelector('.ns-rate-row').appendChild(ulTrend);

		// Desktop order: DOWNLOAD | UPLOAD | TEMP | INTERNET STATUS | DISK+RAM | DOWNLOADED | UPLOADED
		const row = E('div', { class: 'netstat-row' }, [
			dlBox,
			ulBox,
			createTempCard(data.cpu_temp != null ? data.cpu_temp : null,
				formatUptime(data.uptime || 0)),
			createStatusCard(data.status || 'Disconnected', data.ip),
			createInfoCard(data.mem_pct || 0, data.mem_used || 0, data.mem_total || 0,
				data.disk_pct || 0, data.disk_used || 0, data.disk_total || 0),
			createStatBox(_('downloaded'), totalRx[0], totalRx[1], 'is-total is-downloaded'),
			createStatBox(_('uploaded'),   totalTx[0], totalTx[1], 'is-total is-uploaded'),
		]);

		const container = E('div', { class: 'stats-grid netstat-wrap' }, row);
		_container = container;

		if (!_pollAdded) {
			_pollAdded = true;
			L.Poll.add(() => {
				// Periodically refresh the public IP in the background (non-blocking)
				maybeRefreshIp();
				return fetchWithTimeout('/cgi-bin/luci/admin/tools/get_netdev_stats?fast=1', 5000)
					.then(r => {
						const now2 = Date.now();
						const dt2  = Math.max(0.1, (now2 - last_time) / 1000);
						last_time  = now2;

						// Update cached IP from local WAN if we got a valid one
						if (r && r.ip && r.ip !== 'N/A') _cachedIp = r.ip;

						if (_container && _container.isConnected) {
							updateContainer(_container, {
								stats:      (r && r.stats)       || {},
								ip:         _cachedIp,
								status:     (r && r.status)      || 'Disconnected',
								uptime:     (r && r.uptime)      || 0,
								cpu_pct:    (r && r.cpu_pct)     || 0,
								cpu_temp:   (r && r.cpu_temp)    != null ? r.cpu_temp : null,
								mem_pct:    (r && r.mem_pct)     || 0,
								mem_used:   (r && r.mem_used)    || 0,
								mem_total:  (r && r.mem_total)   || 0,
								disk_pct:   (r && r.disk_pct)    || 0,
								disk_used:  (r && r.disk_used)   || 0,
								disk_total: (r && r.disk_total)  || 0,
								preferred:  (r && r.prefer_iface) ? [r.prefer_iface] : []
							}, dt2);
						}
					})
					.catch(() => {});
			}, 2);
		}

		return container;
	}
});
