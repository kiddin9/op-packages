'use strict';
'require view';
'require fs';
'require ui';
'require poll';
'require rpc';
'require dom';

var chartRegistry = {};
var downloadLineChart, uploadLineChart;

// Data structures for stacked line charts
var lineCategories = [];
var downloadSeriesData = {};
var uploadSeriesData = {};

// Color palette for chart series
var colorPalette = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de', '#3ba272', '#fc8452', '#9a60b4', '#ea7ccc'];

var currentSortInfo = {
	table: null,
	column: null,
	reverse: false
};
var sidLookupTable = {};
var isPaused = false;
var lastUpdated = null;
var pollActive = false;
var lastSIDData = null;
var lastL7ProtoData = null;
var resizeListenerAdded = false;
var resizeTimer = null;

// Pre-fill with 60 empty points for a smooth start
for (var i = 0; i < 60; i++) {
	lineCategories.push('');
}

// Helper to convert hex to rgba
function hexToRgba(hex, opacity) {
	var result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
	return result ? 
		'rgba(' + parseInt(result[1], 16) + ', ' + parseInt(result[2], 16) + ', ' + parseInt(result[3], 16) + ', ' + opacity + ')' :
		null;
};

function isDarkMode() {
	var attr = document.documentElement.getAttribute('data-darkmode');
	if (attr === 'true')
		return true;
	if (attr === 'false')
		return false;

	var bg = getComputedStyle(document.body).backgroundColor;
	var m = bg && bg.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
	if (m) {
		var lum = (0.299 * m[1] + 0.587 * m[2] + 0.114 * m[3]) / 255;
		return lum < 0.5;
	}

	return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function getChartColors() {
	var dark = isDarkMode();
	return {
		background: 'transparent',
		text: dark ? '#cccccc' : '#333333',
		muted: dark ? '#adb5bd' : '#666666',
		axis: dark ? 'rgba(255,255,255,0.28)' : 'rgba(0,0,0,0.25)',
		split: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)',
		pieBorder: dark ? '#252526' : '#ffffff',
		tooltipBg: dark ? 'rgba(32,32,32,0.94)' : 'rgba(255,255,255,0.95)',
		tooltipBorder: dark ? '#555555' : '#cccccc',
		tooltipText: dark ? '#eeeeee' : '#333333'
	};
}

function applyViewTheme() {
	var theme = isDarkMode() ? 'dark' : 'light';
	document.querySelectorAll('.l7-view-container, .display-view-container').forEach(function(el) {
		el.setAttribute('data-aw-theme', theme);
	});
	return theme;
}

function observeChartEl(chart, el) {
	if (!chart || !el || !window.ResizeObserver || el._awRo)
		return;
	el._awRo = new ResizeObserver(function() {
		chart.resize();
	});
	el._awRo.observe(el);
}

function chartAxisTheme(colors) {
	return {
		backgroundColor: colors.background,
		textStyle: { color: colors.text },
		legend: { textStyle: { color: colors.text } },
		tooltip: {
			backgroundColor: colors.tooltipBg,
			borderColor: colors.tooltipBorder,
			textStyle: { color: colors.tooltipText }
		},
		xAxis: {
			axisLine: { lineStyle: { color: colors.axis } },
			axisLabel: { color: colors.muted },
			splitLine: { show: false }
		},
		yAxis: {
			axisLine: { lineStyle: { color: colors.axis } },
			axisLabel: { color: colors.muted },
			splitLine: { lineStyle: { color: colors.split } }
		}
	};
}

return view.extend({
	hasXdns: false,
	xdnsDomains: {},

	load: function() {
		return Promise.all([
			this.loadSIDData(),
			this.loadL7ProtoData(),
			this.checkXdnsStatus()
		]);
	},

	checkXdnsStatus: function() {
		var self = this;
		return fs.stat('/usr/bin/xdns-ctl').then(function(stat) {
			if (stat && stat.type === 'file') {
				self.hasXdns = true;
				return fs.read_direct('/etc/xdns/whitelist.txt').then(function(content) {
					var domains = {};
					if (content) {
						content.split('\n').forEach(function(line) {
							line = line.trim();
							if (!line || line.charAt(0) === '#') return;
							if (line.indexOf('*.') === 0) line = line.substring(2);
							if (line.charAt(0) === '.') line = line.substring(1);
							domains[line.toLowerCase()] = true;
						});
					}
					self.xdnsDomains = domains;
					return true;
				}).catch(function() {
					self.xdnsDomains = {};
					return true;
				});
			} else {
				self.hasXdns = false;
				return false;
			}
		}).catch(function() {
			self.hasXdns = false;
			return false;
		});
	},

	isDomainProxied: function(dName) {
		if (!dName || !this.xdnsDomains) return false;
		dName = dName.toLowerCase();
		if (this.xdnsDomains[dName]) return true;
		var parts = dName.split('.');
		for (var i = 1; i < parts.length - 1; i++) {
			var parent = parts.slice(i).join('.');
			if (this.xdnsDomains[parent]) return true;
		}
		return false;
	},

	handleAddXdnsDomain: function(domain, btn) {
		var self = this;
		if (!domain) return;
		btn.disabled = true;
		var origText = btn.textContent;
		btn.textContent = _('添加中...');

		fs.exec_direct('/usr/bin/xdns-ctl', ['add-domain', domain]).then(function() {
			self.xdnsDomains[domain.toLowerCase()] = true;
			ui.addNotification(null, E('p', _('域名「%s」已成功加入 xdns-bpf 代理名单并即刻生效！').format(domain)), 'info');
			if (lastL7ProtoData) {
				self.renderL7ProtoData(lastL7ProtoData);
			}
		}).catch(function(err) {
			btn.disabled = false;
			btn.textContent = origText;
			ui.addNotification(null, E('p', _('加入代理名单失败: %s').format(err.message || err)), 'error');
		});
	},

	showError: function(message) {
		var errorEl = document.getElementById('l7-error-message');
		if (errorEl) {
			errorEl.textContent = message;
			errorEl.style.display = 'block';
		}
	},

	hideError: function() {
		var errorEl = document.getElementById('l7-error-message');
		if (errorEl) {
			errorEl.style.display = 'none';
		}
	},

	loadSIDData: function() {
		var self = this;
		return fs.exec_direct('/usr/bin/aw-bpfctl', ['sid', 'json'], 'json').then(function(result) {
			self.hideError();
			lastSIDData = result;
			return result;
		}).catch(function(error) {
			console.error('Error loading SID data:', error);
			self.showError(_('Error loading SID data: %s').format(error.message));
			return { status: 'error', data: [] };
		});
	},

	loadL7ProtoData: function() {
		var self = this;
		return fs.exec_direct('/usr/bin/aw-bpfctl', ['l7', 'json'], 'json').then(function(result) {
			self.hideError();
			return result;
		}).catch(function(error) {
			console.error('Error loading L7 protocol data:', error);
			self.showError(_('Error loading L7 protocol data: %s').format(error.message));
			return { status: 'error', data: [] };
		});
	},

	updateStackedLineCharts: function(perServiceDownload, perServiceUpload) {
		var now = new Date().toLocaleTimeString();
		lineCategories.push(now);
		lineCategories.shift();
	
		var processChartData = function(seriesData, perServiceData) {
			var allServices = Object.keys(seriesData);
			Object.keys(perServiceData).forEach(function(service) {
				if (allServices.indexOf(service) === -1) {
					allServices.push(service);
				}
			});
	
			allServices.forEach(function(service) {
				if (!seriesData[service]) {
					seriesData[service] = Array(59).fill(0);
				}
				var rate = perServiceData[service] || 0;
				seriesData[service].push(rate);
				seriesData[service].shift();
			});
	
			return Object.keys(seriesData).map(function(service, index) {
				var color = colorPalette[index % colorPalette.length];
				return {
					name: service,
					type: 'line',
					stack: 'Total',
					smooth: true,
					lineStyle: { width: 1, color: color },
					showSymbol: false,
					itemStyle: { color: color },
					areaStyle: {
						color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
							{ offset: 0, color: hexToRgba(color, 0.5) },
							{ offset: 1, color: hexToRgba(color, 0) }
						])
					},
					data: seriesData[service]
				};
			});
		};
	
		var downloadChartSeries = processChartData(downloadSeriesData, perServiceDownload);
		var uploadChartSeries = processChartData(uploadSeriesData, perServiceUpload);
	
		var legendData = downloadChartSeries.map(function(s) { return s.name; });
		var colors = getChartColors();

		if (downloadLineChart) {
			downloadLineChart.setOption({
				legend: { data: legendData, type: 'scroll', top: 0, left: 'center', textStyle: { color: colors.text } },
				series: downloadChartSeries,
				xAxis: { data: lineCategories }
			});
		}
	
		if (uploadLineChart) {
			uploadLineChart.setOption({
				legend: { data: legendData, type: 'scroll', top: 0, left: 'center', textStyle: { color: colors.text } },
				series: uploadChartSeries,
				xAxis: { data: lineCategories }
			});
		}
	},

	pie: function(id, data, valueFormatter) {
		var total = data.reduce(function(n, d) { return n + d.value; }, 0);

		data.sort(function(a, b) { return b.value - a.value; });

		if (total === 0) {
			data = [{ value: 1, color: '#cccccc', name: _('no traffic') }];
		}

		data.forEach(function(d, i) {
			if (!d.color) {
				var hue = (i * 137.508) % 360;
				d.color = 'hsl(' + hue + ', 75%, 55%)';
			}
		});

		var colors = getChartColors();
		var option = {
			backgroundColor: colors.background,
			textStyle: { color: colors.text },
			tooltip: {
				trigger: 'item',
				backgroundColor: colors.tooltipBg,
				borderColor: colors.tooltipBorder,
				textStyle: { color: colors.tooltipText },
				formatter: function(params) {
					if (valueFormatter) {
						// 将 ECharts params 对象转换为自定义格式
						return valueFormatter({
							name: params.name,
							value: params.value,
							percent: params.percent.toFixed(2)
						});
					}
					return params.name + ': ' + params.value + ' (' + params.percent.toFixed(2) + '%)';
				}
			},
			series: [{
				type: 'pie',
				radius: ['25%', '80%'],
				avoidLabelOverlap: false,
				padAngle: 10,
				itemStyle: { borderRadius: 10, borderColor: colors.pieBorder, borderWidth: 2 },
				label: { show: false, position: 'center', color: colors.text },
				emphasis: { label: { show: true, fontSize: 14, fontWeight: 'bold', color: colors.text } },
				labelLine: { show: false },
				data: data.map(function(d) {
					return { value: d.value, name: d.label || d.name, itemStyle: { color: d.color } };
				})
			}]
		};

		var dom = typeof id === 'string' ? document.getElementById(id) : id;

		if (!chartRegistry[id]) {
			chartRegistry[id] = echarts.init(dom);
			observeChartEl(chartRegistry[id], dom);
		}

		chartRegistry[id].setOption(option, true);

		return chartRegistry[id];
	},

	sortTable: function(table, column) {
		var tbody = table.querySelector('tbody');
		if (!tbody) return;
		var rows = Array.from(tbody.querySelectorAll('tr:not(.table-titles):not(.placeholder)'));
		var reverse = (currentSortInfo.table === table && currentSortInfo.column === column) ? !currentSortInfo.reverse : false;

		table.querySelectorAll('th').forEach(function(th) {
			th.classList.remove('th-sort-asc', 'th-sort-desc');
		});

		var th = table.querySelector('th:nth-child(' + (column + 1) + ')');
		th.classList.add(reverse ? 'th-sort-desc' : 'th-sort-asc');

		rows.sort(function(row1, row2) {
			var a = row1.cells[column].getAttribute('data-value') || row1.cells[column].textContent;
			var b = row2.cells[column].getAttribute('data-value') || row2.cells[column].textContent;

			if (!isNaN(a) && !isNaN(b)) { a = Number(a); b = Number(b); }

			if (a < b) return reverse ? 1 : -1;
			if (a > b) return reverse ? -1 : 1;
			return 0;
		});

		currentSortInfo.table = table;
		currentSortInfo.column = column;
		currentSortInfo.reverse = reverse;

		rows.forEach(function(row) { tbody.removeChild(row); });
		rows.forEach(function(row) { tbody.appendChild(row); });
	},

	formatMbps: function(bits) {
		if (typeof bits !== 'number') return '0.00 Mbps';
		return (bits / 1024 / 1024).toFixed(2) + ' Mbps';
	},

	formatMB: function(bytes) {
		if (typeof bytes !== 'number') return '0.00 MB';
		return (bytes / 1024 / 1024).toFixed(2) + ' MB';
	},

	renderSIDData: function(data) {
		var rows = [];
		var txRateData = [], rxRateData = [];
		var txVolumeData = [], rxVolumeData = [];
		var tx_rate_total = 0, rx_rate_total = 0;
		var tx_bytes_total = 0, rx_bytes_total = 0;
		var perServiceTxRate = {};
		var perServiceRxRate = {};
		var self = this;
		var allItems = [];
		
		if (data && data.status === 'success' && Array.isArray(data.data)) {
			allItems = data.data;
			var listSizeEl = document.getElementById('sid-size-select');
			var listSize = listSizeEl ? parseInt(listSizeEl.value, 10) : 10;

			var activeConnections = allItems.filter(function(item) { return item.incoming.rate > 0 || item.outgoing.rate > 0; });
			var inactiveConnections = allItems.filter(function(item) { return item.incoming.rate === 0 && item.outgoing.rate === 0; });
		
			activeConnections.sort(function(a, b) { return (b.incoming.rate + b.outgoing.rate) - (a.incoming.rate + a.outgoing.rate); });
			inactiveConnections.sort(function(a, b) { return b.incoming.total_bytes - a.incoming.total_bytes; });
		
			var displayData = activeConnections;
			if (displayData.length < listSize) {
				displayData = displayData.concat(inactiveConnections.slice(0, listSize - displayData.length));
			}
			
			if (displayData.length > listSize) {
				displayData = displayData.slice(0, listSize);
			}

			displayData.forEach(function(item) {
				var domainOrL7Proto = 'unknown';
				var lookupInfo = sidLookupTable[item.sid];
				
				if (lookupInfo) {
					domainOrL7Proto = lookupInfo.name;
				} else if (item.sid_type === 'Domain' && item.domain && item.domain !== 'unknown') {
					domainOrL7Proto = item.domain;
				} else if (item.sid_type === 'L7' && item.l7_proto_desc && item.l7_proto_desc !== 'unknown') {
					domainOrL7Proto = item.l7_proto_desc;
				}
				
				// 判断连接是否活跃
				var isActive = item.incoming.rate > 0 || item.outgoing.rate > 0;
				var activityIcon = isActive ? '🟢' : '⚪';
				
				rows.push([
					E('span', { 'class': 'sid-cell' }, [
						E('span', { 'class': 'activity-indicator', 'title': isActive ? _('Active') : _('Inactive') }, activityIcon),
						E('span', {}, ' ' + item.sid)
					]),
					E('span', { 'class': 'protocol-cell' }, [
						E('span', { 'class': 'protocol-icon' }, '🌐'),
						E('span', {}, ' ' + domainOrL7Proto)
					]),
					[ item.incoming.rate, E('span', { 'class': 'speed-cell download' }, [
						E('span', { 'class': 'data-value' }, '%1024.2mbps'.format(item.incoming.rate))
					])],
					[ item.incoming.total_bytes, E('span', { 'class': 'volume-cell download' }, [
						E('span', { 'class': 'data-value' }, '%1024.2mB'.format(item.incoming.total_bytes))
					])],
					[ item.incoming.total_packets, E('span', { 'class': 'packet-cell download' }, [
						E('span', { 'class': 'data-value' }, '%1000.2mP'.format(item.incoming.total_packets))
					])],
					[ item.outgoing.rate, E('span', { 'class': 'speed-cell upload' }, [
						E('span', { 'class': 'data-value' }, '%1024.2mbps'.format(item.outgoing.rate))
					])],
					[ item.outgoing.total_bytes, E('span', { 'class': 'volume-cell upload' }, [
						E('span', { 'class': 'data-value' }, '%1024.2mB'.format(item.outgoing.total_bytes))
					])],
					[ item.outgoing.total_packets, E('span', { 'class': 'packet-cell upload' }, [
						E('span', { 'class': 'data-value' }, '%1000.2mP'.format(item.outgoing.total_packets))
					])]
				]);

				txRateData.push({ value: item.incoming.rate, label: domainOrL7Proto });
				rxRateData.push({ value: item.outgoing.rate, label: domainOrL7Proto });
				txVolumeData.push({ value: item.incoming.total_bytes, label: domainOrL7Proto });
				rxVolumeData.push({ value: item.outgoing.total_bytes, label: domainOrL7Proto });

				perServiceTxRate[domainOrL7Proto] = (perServiceTxRate[domainOrL7Proto] || 0) + item.incoming.rate;
				perServiceRxRate[domainOrL7Proto] = (perServiceRxRate[domainOrL7Proto] || 0) + item.outgoing.rate;
			});

			allItems.forEach(function(item) {
				tx_rate_total += item.incoming.rate;
				rx_rate_total += item.outgoing.rate;
				tx_bytes_total += item.incoming.total_bytes;
				rx_bytes_total += item.outgoing.total_bytes;
			});
		}

		this.updateStackedLineCharts(perServiceTxRate, perServiceRxRate);

		var table = document.getElementById('sid-data');
		cbi_update_table(table, rows, E('em', _('No data recorded yet.')));

		var headers = table.querySelectorAll('th');
		
		if (!table.hasAttribute('data-sort-initialized')) {
			headers.forEach(function(header, index) {
				header.style.cursor = 'pointer';
				header.addEventListener('click', function() { self.sortTable(table, index); });
			});
			table.setAttribute('data-sort-initialized', 'true');
		}

		table.querySelectorAll('tr:not(.table-titles):not(.placeholder)').forEach(function(row, rowIndex) {
			if (!rows[rowIndex]) return;
			Array.from(row.cells).forEach(function(cell, cellIndex) {
				if (Array.isArray(rows[rowIndex][cellIndex])) {
					cell.setAttribute('data-value', rows[rowIndex][cellIndex][0]);
				}
			});
		});

		this.pie('sid-tx-rate-pie', txRateData, function(p) { return p.name + ': ' + self.formatMbps(p.value) + ' (' + p.percent + '%)'; });
		this.pie('sid-rx-rate-pie', rxRateData, function(p) { return p.name + ': ' + self.formatMbps(p.value) + ' (' + p.percent + '%)'; });
		this.pie('sid-tx-volume-pie', txVolumeData, function(p) { return p.name + ': ' + self.formatMB(p.value) + ' (' + p.percent + '%)'; });
		this.pie('sid-rx-volume-pie', rxVolumeData, function(p) { return p.name + ': ' + self.formatMB(p.value) + ' (' + p.percent + '%)'; });

		var sidTotalEl = document.getElementById('sid-total-val');
		if(sidTotalEl) sidTotalEl.textContent = allItems.length;

		var txRateEl = document.getElementById('sid-tx-rate-val');
		if(txRateEl) txRateEl.textContent = '%1024.2mbps'.format(tx_rate_total);

		var rxRateEl = document.getElementById('sid-rx-rate-val');
		if(rxRateEl) rxRateEl.textContent = '%1024.2mbps'.format(rx_rate_total);

		var txVolEl = document.getElementById('sid-tx-volume-val');
		if(txVolEl) txVolEl.textContent = '%1024.2mB'.format(tx_bytes_total);

		var rxVolEl = document.getElementById('sid-rx-volume-val');
		if(rxVolEl) rxVolEl.textContent = '%1024.2mB'.format(rx_bytes_total);

		lastUpdated = new Date();
		var timestampEl = document.getElementById('last-updated');
		if (timestampEl) {
			timestampEl.textContent = _('Last updated: %s').format(lastUpdated.toLocaleTimeString());
		}
	},

	fillSortableTable: function(tableId, rows) {
		var table = document.getElementById(tableId);
		var self = this;
		if (!table)
			return;

		if (!table.hasAttribute('data-sort-initialized')) {
			table.querySelectorAll('th').forEach(function(header, index) {
				header.style.cursor = 'pointer';
				header.addEventListener('click', function() { self.sortTable(table, index); });
			});
			table.setAttribute('data-sort-initialized', 'true');
		}

		cbi_update_table(table, rows, E('em', _('No data recorded yet.')));

		table.querySelectorAll('tr:not(.table-titles):not(.placeholder)').forEach(function(row, rowIndex) {
			if (!rows[rowIndex])
				return;
			Array.from(row.cells).forEach(function(cell, cellIndex) {
				if (Array.isArray(rows[rowIndex][cellIndex]))
					cell.setAttribute('data-value', rows[rowIndex][cellIndex][0]);
			});
		});
	},

	renderL7ProtoData: function(data) {
		var self = this;
		var protoRows = [];
		var domainRows = [];

		lastL7ProtoData = data;
		sidLookupTable = {};

		if (data && data.status === 'success' && data.data) {
			if (Array.isArray(data.data.protocols)) {
				data.data.protocols.forEach(function(item) {
					sidLookupTable[item.sid] = { type: 'protocol', name: item.protocol };
					protoRows.push([
						[ item.id, E('span', { 'class': 'id-cell' }, item.id) ],
						E('span', { 'class': 'protocol-cell' }, [
							E('span', { 'class': 'protocol-icon l7' }, '🔌'),
							E('span', {}, ' ' + item.protocol)
						]),
						[ item.sid, E('span', { 'class': 'sid-cell' }, item.sid) ]
					]);
				});
			}

			if (Array.isArray(data.data.domains)) {
				var domains = data.data.domains.slice().sort(function(a, b) {
					var ac = (b.access_count || 0) - (a.access_count || 0);
					if (ac !== 0)
						return ac;
					return (b.last_access || 0) - (a.last_access || 0);
				});

				domains.forEach(function(item) {
					sidLookupTable[item.sid] = { type: 'domain', name: item.domain };
					var row = [
						[ item.id, E('span', { 'class': 'id-cell' }, item.id) ],
						E('span', { 'class': 'protocol-cell' }, [
							E('span', { 'class': 'protocol-icon domain' }, '🌍'),
							E('span', {}, ' ' + item.domain)
						]),
						[ item.sid, E('span', { 'class': 'sid-cell' }, item.sid) ],
						[ item.access_count || 0, E('span', { 'class': 'data-value' }, item.access_count || 0) ],
						item.first_seen_str || '-',
						item.last_access_str || '-'
					];

					if (self.hasXdns) {
						var isProxied = self.isDomainProxied(item.domain);
						if (isProxied) {
							row.push(E('span', {
								'class': 'badge success',
								'style': 'color: #2ecc71; background: rgba(46,204,113,0.12); border: 1px solid rgba(46,204,113,0.3); padding: 2px 8px; border-radius: 4px; font-size: 85%; white-space: nowrap;'
							}, [ '✔ ', _('已代理') ]));
						} else {
							row.push(E('button', {
								'class': 'btn cbi-button cbi-button-action',
								'style': 'padding: 2px 8px; font-size: 85%; white-space: nowrap;',
								'click': function(ev) {
									var b = ev.target.closest('button');
									self.handleAddXdnsDomain(item.domain, b);
								}
							}, [ '➕ ', _('加入代理') ]));
						}
					}

					domainRows.push(row);
				});
			}
		}

		this.fillSortableTable('l7-protocol-data', protoRows);
		this.fillSortableTable('l7-domain-data', domainRows);

		var protoCountEl = document.getElementById('l7-protocol-count');
		if (protoCountEl)
			protoCountEl.textContent = protoRows.length;
		var domainCountEl = document.getElementById('l7-domain-count');
		if (domainCountEl)
			domainCountEl.textContent = domainRows.length;
	},

	pollL7Data: function() {
		if (pollActive) return;

		var self = this;
		pollActive = true;
		
		self.loadL7ProtoData().then(function(l7data) {
			self.renderL7ProtoData(l7data);
			return self.loadSIDData();
		}).then(function(sidData){
			self.renderSIDData(sidData);
		});

		poll.add(function() {
			if (isPaused) return Promise.resolve();
			
			return self.loadL7ProtoData().then(function(data) {
				self.renderL7ProtoData(data);
			}).then(function() {
				return self.loadSIDData().then(function(data) {
					self.renderSIDData(data);
				});
			});
		}, 5);
	},

	initializeUI: function() {
		applyViewTheme();
		if (window.echarts) {
			var self = this;
			var dlChartEl = document.getElementById('download-speed-line-chart');
			var ulChartEl = document.getElementById('upload-speed-line-chart');
			if (!dlChartEl || !ulChartEl) return;

			var colors = getChartColors();
			var axisTheme = chartAxisTheme(colors);
			var baseChartOption = {
				backgroundColor: axisTheme.backgroundColor,
				textStyle: axisTheme.textStyle,
				legend: axisTheme.legend,
				tooltip: Object.assign({
					trigger: 'axis',
					formatter: function (params) {
						if (!params || params.length === 0) {
							return null;
						}
						var tooltipContent = params[0].axisValueLabel + '<br/>';
						params.sort(function(a, b) { return b.value - a.value; });
						params.forEach(function(item) {
							if (item.value > 0) {
								tooltipContent += item.marker + ' ' + item.seriesName + ': ' + '%1024.2mbps'.format(item.value) + '<br/>';
							}
						});
						return tooltipContent;
					}
				}, axisTheme.tooltip),
				grid: { left: '3%', right: '4%', bottom: '10%', top: '50px', containLabel: true },
				xAxis: {
					type: 'category',
					boundaryGap: false,
					data: lineCategories,
					axisLine: axisTheme.xAxis.axisLine,
					axisLabel: axisTheme.xAxis.axisLabel,
					splitLine: axisTheme.xAxis.splitLine
				},
				yAxis: {
					type: 'value',
					axisLine: axisTheme.yAxis.axisLine,
					splitLine: axisTheme.yAxis.splitLine,
					axisLabel: { formatter: function(val) { return '%1024.2mbps'.format(val); }, color: colors.muted }
				},
				series: []
			};


		downloadLineChart = echarts.init(dlChartEl);
		downloadLineChart.setOption(baseChartOption);
		observeChartEl(downloadLineChart, dlChartEl);

		uploadLineChart = echarts.init(ulChartEl);
		uploadLineChart.setOption(baseChartOption);
		observeChartEl(uploadLineChart, ulChartEl);

		// 添加窗口大小变化监听器，使图表能够响应式调整
		if (!resizeListenerAdded) {
			var resizeTimer = null;
			var resizeHandler = function() {
				// 使用防抖，避免频繁触发 resize
				if (resizeTimer) {
					clearTimeout(resizeTimer);
				}
				resizeTimer = setTimeout(function() {
					self.resizeAllCharts();
				}, 200);
			};
			
			window.addEventListener('resize', resizeHandler);
			resizeListenerAdded = true;
		}

		this.pollL7Data();
	} else {
		setTimeout(this.initializeUI.bind(this), 50);
	}
	},

	resizeAllCharts: function() {
		if (downloadLineChart)
			downloadLineChart.resize();
		if (uploadLineChart)
			uploadLineChart.resize();
		Object.keys(chartRegistry).forEach(function(chartId) {
			if (chartRegistry[chartId])
				chartRegistry[chartId].resize();
		});
	},

	bindTabChartResize: function(root) {
		var self = this;
		if (!root)
			return;
		var host = root.parentNode || root;
		if (host._awTabResizeBound)
			return;
		host._awTabResizeBound = true;

		var schedule = function() {
			setTimeout(function() { self.resizeAllCharts(); }, 80);
		};

		host.addEventListener('click', function(ev) {
			if (ev.target.closest && ev.target.closest('ul.cbi-tabmenu'))
				schedule();
		});
		root.querySelectorAll('[data-tab]').forEach(function(pane) {
			pane.addEventListener('cbi-tab-active', schedule);
		});
	},

	render: function() {
		var self = this;

		var controls = E('div', { 'class': 'l7-controls' }, [
			E('div', { 'class': 'l7-controls-left' }, [
				E('div', { 'class': 'control-group' }, [
					E('span', { 'class': 'control-icon' }, '📊'),
					E('label', { 'for': 'sid-size-select', 'class': 'control-label' }, _('Show entries:')),
					E('select', {
						'id': 'sid-size-select',
						'class': 'cbi-input-select',
						'change': ui.createHandlerFn(this, function() {
							if (lastSIDData) {
								self.renderSIDData(lastSIDData);
							}
						})
					}, [
						E('option', { 'value': '10' }, '10'),
						E('option', { 'value': '15' }, '15'),
						E('option', { 'value': '20' }, '20'),
						E('option', { 'value': '25' }, '25'),
						E('option', { 'value': '50' }, '50')
					])
				])
			]),
			E('div', { 'class': 'l7-controls-right' }, [
				E('div', { 'class': 'control-group' }, [
					E('span', { 'class': 'control-icon' }, '🕐'),
					E('span', { 'id': 'last-updated', 'class': 'last-updated-text' }, _('Last updated: never'))
				]),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'id': 'pause-resume-btn',
					'click': function(ev) {
						isPaused = !isPaused;
						var btn = ev.target;
						if (isPaused) {
							btn.innerHTML = '<span class="btn-icon">▶️</span> ' + _('Resume');
							btn.classList.remove('cbi-button-action');
							btn.classList.add('cbi-button-positive');
						} else {
							btn.innerHTML = '<span class="btn-icon">⏸️</span> ' + _('Pause');
							btn.classList.remove('cbi-button-positive');
							btn.classList.add('cbi-button-action');
						}
					}
				}, [
					E('span', { 'class': 'btn-icon' }, '⏸️'),
					E('span', {}, ' ' + _('Pause'))
				])
			])
		]);

		var sidInnerTabs = E('div', { 'class': 'aw-inner-tabs' }, [
			E('div', { 'class': 'cbi-section', 'data-tab': 'sid-trend', 'data-tab-title': _('Speed Trend') }, [
				E('div', { 'class': 'dashboard-container' }, [
					E('div', { 'class': 'kpi-row' }, [
						E('div', { 'class': 'kpi-card' }, [ E('big', { id: 'sid-total-val' }, '0'), E('span', { 'class': 'kpi-card-label' }, _('L7 Protocol Data')) ]),
						E('div', { 'class': 'kpi-card' }, [ E('big', { id: 'sid-tx-rate-val' }, '0'), E('span', { 'class': 'kpi-card-label' }, _('Download Speed')) ]),
						E('div', { 'class': 'kpi-card' }, [ E('big', { id: 'sid-rx-rate-val' }, '0'), E('span', { 'class': 'kpi-card-label' }, _('Upload Speed')) ]),
						E('div', { 'class': 'kpi-card' }, [ E('big', { id: 'sid-tx-volume-val' }, '0'), E('span', { 'class': 'kpi-card-label' }, _('Download Total')) ]),
						E('div', { 'class': 'kpi-card' }, [ E('big', { id: 'sid-rx-volume-val' }, '0'), E('span', { 'class': 'kpi-card-label' }, _('Upload Total')) ])
					]),
					E('div', { 'class': 'line-chart-row' }, [
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Real-time Download Speed')]),
							E('div', { id: 'download-speed-line-chart', style: 'width: 100%; height: 350px;' })
						]),
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Real-time Upload Speed')]),
							E('div', { id: 'upload-speed-line-chart', style: 'width: 100%; height: 350px;' })
						])
					])
				])
			]),
			E('div', { 'class': 'cbi-section', 'data-tab': 'sid-share', 'data-tab-title': _('Traffic Share') }, [
				E('div', { 'class': 'dashboard-container' }, [
					E('div', { 'class': 'chart-grid' }, [
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Download Speed / SID')]),
							E('div', { id: 'sid-tx-rate-pie', style: 'width: 100%; height: 300px;' })
						]),
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Upload Speed / SID')]),
							E('div', { id: 'sid-rx-rate-pie', style: 'width: 100%; height: 300px;' })
						]),
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Download Total')]),
							E('div', { id: 'sid-tx-volume-pie', style: 'width: 100%; height: 300px;' })
						]),
						E('div', { 'class': 'chart-card' }, [
							E('h4', [_('Upload Total')]),
							E('div', { id: 'sid-rx-volume-pie', style: 'width: 100%; height: 300px;' })
						])
					])
				])
			]),
			E('div', { 'class': 'cbi-section', 'data-tab': 'sid-list', 'data-tab-title': _('SID List') }, [
				E('table', { 'class': 'table', 'id': 'sid-data' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🆔'), ' ', _('SID') ]),
						E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🌐'), ' ', _('Domain&L7Protocol') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '⬇️'), ' ', _('Download Speed (Bit/s)') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '📦'), ' ', _('Download (Bytes)') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '📨'), ' ', _('Download (Packets)') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '⬆️'), ' ', _('Upload Speed (Bit/s)') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '📦'), ' ', _('Upload (Bytes)') ]),
						E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '📨'), ' ', _('Upload (Packets)') ])
					]),
					E('tr', { 'class': 'tr placeholder' }, [
						E('td', { 'class': 'td', 'colspan': '8' }, [
							E('em', { 'class': 'spinning' }, [ _('Collecting data...') ])
						])
					])
				]),
				controls
			])
		]);

		var tabContainer = E('div', {}, [
			E('div', { 'class': 'cbi-section', 'data-tab': 'sid', 'data-tab-title': _('L7 SID Data') }, [
				sidInnerTabs
			]),
			E('div', { 'class': 'cbi-section', 'data-tab': 'l7proto', 'data-tab-title': _('L7 Protocol Data') }, [
				E('div', { 'class': 'aw-inner-tabs' }, [
					E('div', { 'class': 'cbi-section', 'data-tab': 'l7-protocols', 'data-tab-title': _('Protocol Library') }, [
						E('p', { 'class': 'cbi-section-descr' }, [
							_('Built-in L7 protocol signatures from aw-bpf.'),
							' ',
							_('Entries:'),
							' ',
							E('strong', { 'id': 'l7-protocol-count' }, '0')
						]),
						E('table', { 'class': 'table', 'id': 'l7-protocol-data' }, [
							E('tr', { 'class': 'tr table-titles' }, [
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '#️⃣'), ' ', _('ID') ]),
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🔌'), ' ', _('Protocol') ]),
								E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '🔑'), ' ', _('SID') ])
							]),
							E('tr', { 'class': 'tr placeholder' }, [
								E('td', { 'class': 'td', 'colspan': '3' }, [
									E('em', { 'class': 'spinning' }, [ _('Collecting data...') ])
								])
							])
						])
					]),
					E('div', { 'class': 'cbi-section', 'data-tab': 'l7-domains', 'data-tab-title': _('常用域名') }, [
						E('p', { 'class': 'cbi-section-descr' }, [
							_('Frequently accessed domains discovered by xDPI, sorted by access count.'),
							' ',
							_('Entries:'),
							' ',
							E('strong', { 'id': 'l7-domain-count' }, '0')
						]),
						E('table', { 'class': 'table', 'id': 'l7-domain-data' }, [
							E('tr', { 'class': 'tr table-titles' }, [
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '#️⃣'), ' ', _('ID') ]),
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🌍'), ' ', _('Domain') ]),
								E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '🔑'), ' ', _('SID') ]),
								E('th', { 'class': 'th right' }, [ E('span', { 'class': 'th-icon' }, '📊'), ' ', _('Access Count') ]),
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🕒'), ' ', _('First Seen') ]),
								E('th', { 'class': 'th left' }, [ E('span', { 'class': 'th-icon' }, '🕒'), ' ', _('Last Access') ]),
								this.hasXdns ? E('th', { 'class': 'th center' }, [ E('span', { 'class': 'th-icon' }, '⚡'), ' ', _('xdns代理') ]) : null
							].filter(Boolean)),
							E('tr', { 'class': 'tr placeholder' }, [
								E('td', { 'class': 'td', 'colspan': this.hasXdns ? '7' : '6' }, [
									E('em', { 'class': 'spinning' }, [ _('Collecting data...') ])
								])
							])
						])
					])
				])
			])
		]);

		var node = E([], [
		    E('link', { 'rel': 'stylesheet', 'href': L.resource('view/aw-bpf.css') }),
		    E('script', { 'type': 'text/javascript', 'src': L.resource('echarts.min.js') }),

		    E('div', { 'class': 'l7-view-container', 'data-aw-theme': isDarkMode() ? 'dark' : 'light' }, [
		        E('h2', [ _('L7 Data Monitor') ]),
		        E('div', { 'id': 'l7-error-message' }),
		        tabContainer
		    ])
		]);

		tabContainer.querySelectorAll('.aw-inner-tabs').forEach(function(inner) {
			ui.tabs.initTabGroup(inner.childNodes);
		});
		ui.tabs.initTabGroup(tabContainer.childNodes);
		this.bindTabChartResize(tabContainer);

		setTimeout(this.initializeUI.bind(this), 0);

		return node;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});