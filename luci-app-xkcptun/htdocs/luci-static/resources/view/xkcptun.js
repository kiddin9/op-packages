'use strict';
'require view';
'require dom';
'require ui';
'require uci';
'require form';
'require rpc';
'require fs';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

function formatBytes(bytes) {
	if (!bytes || bytes <= 0) return '0 B';
	const units = ['B', 'KB', 'MB', 'GB', 'TB'];
	let i = Math.floor(Math.log(bytes) / Math.log(1024));
	if (i >= units.length) i = units.length - 1;
	return (bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : (i === 1 ? 1 : 2)) + ' ' + units[i];
}

function formatSpeed(bps) {
	if (!bps || bps <= 0) return '0 B/s';
	return formatBytes(bps) + '/s';
}

function formatUptime(sec) {
	if (!sec || sec <= 0) return '0s';
	sec = Math.floor(sec);
	let m = Math.floor(sec / 60);
	let s = sec % 60;
	if (m === 0) return s + 's';
	let h = Math.floor(m / 60);
	m = m % 60;
	if (h === 0) return m + 'm ' + s + 's';
	return h + 'h ' + m + 'm';
}

function getServiceStatus() {
	return Promise.all([
		L.resolveDefault(callServiceList('xkcptun'), {}),
		L.resolveDefault(fs.exec_direct('/usr/bin/xkcp_spy', ['-c', 'json']), '')
	]).then(function (results) {
		let res = results[0];
		let spyOut = results[1];
		let status = {
			client: null,
			server: null,
			stats: null
		};
		try {
			let instances = res['xkcptun']['instances'];
			if (instances['client'] && instances['client']['running']) {
				status.client = instances['client']['pid'];
			}
			if (instances['server'] && instances['server']['running']) {
				status.server = instances['server']['pid'];
			}
		} catch (e) {}

		if (typeof spyOut === 'string' && spyOut.trim()) {
			try {
				status.stats = JSON.parse(spyOut.trim());
			} catch (e) {}
		}
		return status;
	});
}

function renderStatus(status) {
	let stats = status.stats || {};
	let totalTunnels = stats.num_tunnels || (stats.tunnels ? stats.tunnels.length : 0);
	let activeConns = stats.active_conns || 0;
	let totalConns = stats.total_conns || 0;
	let bytesIn = stats.bytes_in || 0;
	let bytesOut = stats.bytes_out || 0;
	let totalBytes = bytesIn + bytesOut;
	let rxRate = stats.rx_rate_bps || 0;
	let txRate = stats.tx_rate_bps || 0;

	let clientRunning = !!status.client;
	let svcBadge = E('span', {
		'class': 'label ' + (clientRunning ? 'success' : 'neutral'),
		'style': 'padding: 4px 10px; border-radius: 4px; font-weight: bold; font-size: 85%; color: #fff; background-color: ' + (clientRunning ? '#28a745' : '#6c757d') + ';'
	}, clientRunning ? (_('运行中') + (status.client ? (' (PID ' + status.client + ')') : '')) : _('未运行'));

	let headerBar = E('div', { 'style': 'display: flex; align-items: center; justify-content: space-between; margin-bottom: 15px;' }, [
		E('div', { 'style': 'display: flex; align-items: center; gap: 12px;' }, [
			E('h3', { 'style': 'margin: 0; font-size: 16px; font-weight: 600;' }, _('服务运行状态')),
			svcBadge
		]),
		E('div', { 'style': 'color: #888; font-size: 12px;' }, _('每 3 秒自动轮询刷新'))
	]);

	function createKpiCard(title, icon, value, color, subText, isHero) {
		return E('div', {
			'class': 'xkcp-kpi-card' + (isHero ? ' hero' : '')
		}, [
			E('div', { 'class': 'xkcp-kpi-header' }, [
				E('span', { 'class': 'xkcp-kpi-title' }, title),
				E('span', { 'class': 'xkcp-kpi-icon' }, icon)
			]),
			E('div', { 'class': 'xkcp-kpi-val', 'style': 'color: ' + color + ';' }, value),
			subText ? E('div', { 'class': 'xkcp-kpi-sub' }, subText) : ''
		]);
	}

	let kpiGrid = E('div', { 'class': 'xkcp-kpi-grid' }, [
		createKpiCard(_('加速通道总流量'), '🚀', formatBytes(totalBytes), '#0891b2', _('KCP 双向加速累计吞吐'), true),
		createKpiCard(_('下行加速流量'), '📥', formatBytes(bytesOut), '#10b981', (txRate > 0 ? (_('实时流速') + ': ' + formatSpeed(txRate)) : _('接收下行吞吐'))),
		createKpiCard(_('上行传输流量'), '📤', formatBytes(bytesIn), '#3b82f6', (rxRate > 0 ? (_('实时流速') + ': ' + formatSpeed(rxRate)) : _('发送上行吞吐'))),
		createKpiCard(_('此刻加速连接'), '⚡', String(activeConns), '#f59e0b', _('累计处理') + ' ' + String(totalConns) + ' ' + _('连接')),
		createKpiCard(_('全链路加速隧道'), '🚇', String(totalTunnels) + ' ' + _('条'), '#8b5cf6', _('KCP 多路复用隧道'))
	]);

	// Collect active sessions across all tunnels
	let sessionRows = [];
	if (stats.tunnels && Array.isArray(stats.tunnels)) {
		stats.tunnels.forEach(function(t) {
			if (!t.sessions || !Array.isArray(t.sessions)) return;
			t.sessions.forEach(function(s) {
				let protoTag = (s.proto || t.proto || 'tcp').toUpperCase();
				let clientAddr = (s.client_host || '127.0.0.1') + (s.client_port ? ':' + s.client_port : '');
				let targetAddr = (s.target_host || '127.0.0.1') + (s.target_port ? ':' + s.target_port : '');
				let rttText = s.rtt_ms ? (s.rtt_ms + ' ms') : '-';
				let rttColor = (s.rtt_ms && s.rtt_ms < 150) ? '#10b981' : ((s.rtt_ms && s.rtt_ms < 300) ? '#f59e0b' : '#6b7280');

				sessionRows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'font-weight: 600;' }, clientAddr),
					E('td', { 'class': 'td', 'style': 'font-family: monospace;' }, targetAddr),
					E('td', { 'class': 'td' }, [
						E('span', {
							'style': 'display: inline-block; padding: 2px 6px; font-size: 11px; font-weight: 600; border-radius: 4px; background: rgba(99, 102, 241, 0.1); color: #6366f1;'
						}, t.name + ' (' + protoTag + ')')
					]),
					E('td', { 'class': 'td' }, formatBytes(s.bytes_out) + (s.tx_rate_bps > 0 ? (' · ' + formatSpeed(s.tx_rate_bps)) : '')),
					E('td', { 'class': 'td' }, formatBytes(s.bytes_in) + (s.rx_rate_bps > 0 ? (' · ' + formatSpeed(s.rx_rate_bps)) : '')),
					E('td', { 'class': 'td' }, [
						E('span', {
							'style': 'display: inline-block; padding: 2px 6px; font-size: 11px; font-weight: 600; border-radius: 4px; background: rgba(16, 185, 129, 0.1); color: ' + rttColor + ';'
						}, rttText)
					]),
					E('td', { 'class': 'td', 'style': 'color: #6b7280; font-size: 12px;' }, formatUptime(s.uptime))
				]));
			});
		});
	}

	let headerRow = E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('客户端地址')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('目标服务器')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('所属隧道')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('下行加速流量')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('上行传输流量')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('往返时延 (RTT)')),
		E('th', { 'class': 'th', 'style': 'text-align: left;' }, _('持续时间'))
	]);

	let tableRows = [ headerRow ];
	if (sessionRows.length > 0) {
		tableRows = tableRows.concat(sessionRows);
	} else {
		tableRows.push(E('tr', { 'class': 'tr placeholder' }, [
			E('td', { 'class': 'td', 'style': 'text-align: center; padding: 25px 10px; color: #9ca3af;', 'colspan': '7' },
				E('em', {}, _('暂无活跃加速连接（当局域网客户端发起分流流量或端口转发访问时将实时显示）'))
			)
		]));
	}

	let sessionTable = E('div', { 'style': 'overflow-x: auto; margin-top: 10px;' }, [
		E('table', { 'class': 'table', 'style': 'width: 100%; border-collapse: collapse;' }, tableRows)
	]);

	let sessionSection = E('div', { 'class': 'cbi-section', 'style': 'margin-top: 25px;' }, [
		E('h3', { 'style': 'margin: 0 0 6px 0; font-size: 15px; font-weight: 600;' }, [
			_('此刻正在加速的连接'),
			' (',
			String(sessionRows.length),
			')'
		]),
		E('p', { 'class': 'cbi-section-descr', 'style': 'margin-bottom: 10px;' },
			_('当局域网客户端发起分流流量或通过端口转发访问时，将实时动态呈现连接会话明细。')
		),
		sessionTable
	]);

	return E('div', { 'class': 'xkcp-status-panel' }, [
		headerBar,
		kpiGrid,
		sessionSection
	]);
}

const modeProfiles = [
	['fast3', 'fast3 (nodelay=1, interval=10ms, resend=2, nc=1)'],
	['fast2', 'fast2 (nodelay=1, interval=10ms, resend=2, nc=0)'],
	['fast', 'fast (nodelay=0, interval=20ms, resend=2, nc=0)'],
	['normal', 'normal (nodelay=0, interval=30ms, resend=2, nc=0)'],
	['manual', _('manual (custom parameters)')]
];

function addCommonAdvancedOptions(s, tabName) {
	let tab = tabName || 'advanced';
	let o;

	o = s.taboption(tab, form.Value, 'mtu', _('MTU'),
		_('Maximum Transmission Unit for UDP packets. Default is 1350.'));
	o.datatype = 'uinteger';
	o.placeholder = '1350';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'sndwnd', _('Send Window (sndwnd)'),
		_('Send window size (number of packets). Default is 4096.'));
	o.datatype = 'uinteger';
	o.placeholder = '4096';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'rcvwnd', _('Receive Window (rcvwnd)'),
		_('Receive window size (number of packets). Default is 4096.'));
	o.datatype = 'uinteger';
	o.placeholder = '4096';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'fec', _('Enable FEC (fec)'),
		_('Frame all UDP datagrams with Reed-Solomon FEC header. Default is enabled.'));
	o.default = '1';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'datashard', _('Data Shards (FEC)'),
		_('Reed-Solomon erasure coding data shards. Default is 10.'));
	o.datatype = 'uinteger';
	o.placeholder = '10';
	o.optional = true;
	o.depends('fec', '1');

	o = s.taboption(tab, form.Value, 'parityshard', _('Parity Shards (FEC)'),
		_('Reed-Solomon erasure coding parity shards. Default is 3.'));
	o.datatype = 'uinteger';
	o.placeholder = '3';
	o.optional = true;
	o.depends('fec', '1');

	o = s.taboption(tab, form.Value, 'dscp', _('DSCP'),
		_('DSCP IP TOS value (0-63). Default is 0.'));
	o.datatype = 'range(0,63)';
	o.placeholder = '0';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'lossctrl', _('Loss-Driven AIMD (lossctrl)'),
		_('Enable loss-driven AIMD send window adaptation. Default is disabled.'));
	o.default = '0';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'pacing', _('Send Pacing (pacing)'),
		_('Max KCP segments per flush tick to smooth send bursts (0 = off). Default is 0.'));
	o.datatype = 'uinteger';
	o.placeholder = '0';
	o.optional = true;

	o = s.taboption(tab, form.ListValue, 'nodelay', _('No Delay (nodelay)'),
		_('Enable KCP nodelay mode.'));
	o.value('0', '0 (' + _('Disable') + ')');
	o.value('1', '1 (' + _('Enable') + ')');
	o.default = '1';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'interval', _('Internal Interval'),
		_('Internal clock interval in milliseconds (10-5000). Default is 10ms.'));
	o.datatype = 'range(10,5000)';
	o.placeholder = '10';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'resend', _('Fast Resend'),
		_('Fast resend count. 0 = off, 2 = fast resend. Default is 2.'));
	o.datatype = 'uinteger';
	o.placeholder = '2';
	o.optional = true;

	o = s.taboption(tab, form.Flag, 'nc', _('No Congestion Control (nc)'),
		_('Disable congestion window flow control. Default is 1 (disabled).'));
	o.default = '1';
	o.rmempty = false;

	o = s.taboption(tab, form.Value, 'sockbuf', _('Socket Buffer Size'),
		_('UDP socket receive/send buffer size in bytes. Default is 16777216 (16MB).'));
	o.datatype = 'uinteger';
	o.placeholder = '16777216';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'keepalive', _('Keepalive Interval'),
		_('KCP keepalive ping interval in seconds. Default is 10s.'));
	o.datatype = 'uinteger';
	o.placeholder = '10';
	o.optional = true;

	o = s.taboption(tab, form.Value, 'conntimeout', _('Connection Timeout'),
		_('Idle connection timeout in seconds (0 = disable timeout sweep). Default is 60s.'));
	o.datatype = 'uinteger';
	o.placeholder = '60';
	o.optional = true;
}

const SERVER_AI_PROMPT = [
	'请在当前这台 Linux VPS 服务器上编译并部署 xkcptun 服务端守护进程（作为高速动态网关）：',
	'',
	'### 1. 架构说明',
	'- xkcptun 采用统一动态网关模式：服务端监听单个 UDP 端口（默认 9089），客户端透明代理与转发流量均复用此通道。',
	'- 源码仓库：https://github.com/liudf0716/xkcptun',
	'',
	'### 2. 编译与安装步骤',
	'1. 安装依赖：',
	'   - Debian/Ubuntu: apt-get update && apt-get install -y git build-essential cmake libevent-dev pkg-config',
	'   - CentOS/Rocky/RHEL: yum install -y git gcc gcc-c++ make cmake libevent-devel',
	'2. 克隆仓库并编译：',
	'   git clone https://github.com/liudf0716/xkcptun.git /opt/xkcptun-src',
	'   cd /opt/xkcptun-src && mkdir -p build && cd build',
	'   cmake -DCMAKE_BUILD_TYPE=Release .. && make -j$(nproc)',
	'   cp xkcp_server /usr/local/bin/',
	'',
	'### 3. 创建服务端配置 (/etc/xkcptun/server.toml)',
	'mkdir -p /etc/xkcptun',
	'cat << \'EOF\' > /etc/xkcptun/server.toml',
	'[global]',
	'syslog = true',
	'mon_port = 9087',
	'',
	'[[tunnel]]',
	'name = "gateway"',
	'local_interface = "0.0.0.0"',
	'local_port = 9089',
	'key = "YOUR_SHARED_SECRET_KEY"   # 请替换为强随机密钥',
	'mode = "fast3"',
	'mtu = 1350',
	'sndwnd = 4096',
	'rcvwnd = 4096',
	'datashard = 10',
	'parityshard = 3',
	'fec = 1',
	'nodelay = 1',
	'interval = 10',
	'resend = 2',
	'nc = 1',
	'lossctrl = 0',
	'pacing = 0',
	'sockbuf = 16777216',
	'keepalive = 10',
	'conntimeout = 60',
	'EOF',
	'',
	'### 4. 创建守护服务与启动',
	'cat << \'EOF\' > /etc/systemd/system/xkcptun-server.service',
	'[Unit]',
	'Description=xkcptun High-Speed Server Dynamic Gateway',
	'After=network.target',
	'',
	'[Service]',
	'Type=simple',
	'User=root',
	'ExecStart=/usr/local/bin/xkcp_server -f --syslog -c /etc/xkcptun/server.toml',
	'Restart=always',
	'RestartSec=3',
	'LimitNOFILE=65535',
	'',
	'[Install]',
	'WantedBy=multi-user.target',
	'EOF',
	'',
	'systemctl daemon-reload && systemctl enable --now xkcptun-server',
	'sysctl -w net.ipv4.ip_forward=1',
	'',
	'### 5. 防火墙放行',
	'放行 UDP 9089 端口（例如: ufw allow 9089/udp 或 firewall-cmd --add-port=9089/udp --permanent && firewall-cmd --reload）。',
	'',
	'部署完成后，请告诉我当前服务器公网 IP、UDP 端口以及设置的预共享密钥。'
].join('\n');

function renderPromptTab() {
	return E('div', {
		'class': 'cbi-section',
		'data-tab': 'prompt',
		'data-tab-title': _('Server Configuration')
	}, [
		E('h3', {}, _('Server Deployment AI Prompt')),
		E('div', { 'class': 'cbi-section-descr' },
			_('Chawrt only functions as the client. Copy this prompt directly to an AI assistant to automatically build and deploy the xkcptun dynamic gateway on your remote VPS.')
		),
		E('div', { 'style': 'position: relative; margin-top: 15px;' }, [
			E('textarea', {
				'id': 'xkcptun_server_prompt_area',
				'class': 'cbi-input-textarea',
				'style': 'width: 100%; height: 260px; font-family: monospace; font-size: 13px; line-height: 1.5; background: #1e1e2e; color: #cdd6f4; border: 1px solid #45475a; border-radius: 6px; padding: 12px; resize: vertical;',
				'readonly': 'readonly'
			}, [ SERVER_AI_PROMPT ]),
			E('div', { 'style': 'margin-top: 10px; display: flex; align-items: center; gap: 15px;' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': function(ev) {
						let textarea = document.getElementById('xkcptun_server_prompt_area');
						if (!textarea) return;

						let copySuccess = function() {
							let origText = ev.target.textContent;
							ev.target.textContent = '✔ ' + _('Copied to Clipboard!');
							ev.target.classList.remove('cbi-button-action');
							ev.target.classList.add('cbi-button-positive');
							setTimeout(function() {
								ev.target.textContent = origText;
								ev.target.classList.remove('cbi-button-positive');
								ev.target.classList.add('cbi-button-action');
							}, 2000);
							ui.addNotification(null, E('p', {}, _('Server deployment prompt copied to clipboard!')), 'info');
						};

						if (navigator.clipboard && navigator.clipboard.writeText) {
							navigator.clipboard.writeText(textarea.value).then(copySuccess).catch(function() {
								textarea.select();
								document.execCommand('copy');
								copySuccess();
							});
						} else {
							textarea.select();
							document.execCommand('copy');
							copySuccess();
						}
					}
				}, [ _('📋 Copy Prompt for AI Deployment') ]),
				E('span', { 'style': 'color: #888; font-size: 13px;' },
					_('Paste this prompt to AI (Claude/ChatGPT/DeepSeek) on your VPS terminal.')
				)
			])
		])
	]);
}

return view.extend({
	render: function() {
		let m, s, o;

		m = new form.Map('xkcptun');
		m.tabbed = true;

		// ===== Tab 1: Service Status Overview =====
		let s_status = m.section(form.NamedSection, '_status', 'status', _('Service Status'),
			_('Real-time connection telemetry, throughput metrics, and active accelerated sessions.'));
		s_status.anonymous = true;
		s_status.addremove = false;
		s_status.load = function() { return Promise.resolve(); };
		s_status.parse = function() { return Promise.resolve(); };
		s_status.render = function() {
			let statusDiv = E('div', { 'id': 'service_status', 'style': 'margin-top: 10px;' }, [
				E('em', { 'class': 'spinning' }, _('Collecting status ...'))
			]);
			return Promise.resolve(E('div', {
				'class': 'cbi-section',
				'data-tab': 'status',
				'data-tab-title': _('Service Status')
			}, [
				E('div', { 'class': 'cbi-section-descr' },
					_('Real-time connection telemetry, throughput metrics, and active accelerated sessions.')
				),
				statusDiv
			]));
		};

		// ===== Tab 2: Client Global Default Settings =====
		s = m.section(form.NamedSection, 'client', 'global', _('Client Global Settings'),
			_('Common connection parameters and KCP profile inherited by all client tunnels.'));
		s.anonymous = false;
		s.addremove = false;

		s.tab('general', _('General Settings'));
		s.tab('advanced', _('Advanced Settings'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable Client Daemon'),
			_('Enable unified xkcptun client daemon.'));
		o.enabled = '1';
		o.disabled = '0';
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'remote_addr', _('Server Address'),
			_('Remote xkcptun server IP address or domain name.'));
		o.datatype = 'host';
		o.placeholder = '1.2.3.4';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'remote_port', _('Server Port'),
			_('Remote xkcptun server UDP listen port.'));
		o.datatype = 'port';
		o.placeholder = '9089';
		o.default = '9089';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'key', _('Pre-Shared Key'),
			_('Pre-shared key for authentication. Must match the server.'));
		o.password = true;
		o.placeholder = "it's a secret";
		o.optional = true;

		o = s.taboption('general', form.ListValue, 'mode', _('Mode Profile'),
			_('KCP performance tuning profile.'));
		for (let i = 0; i < modeProfiles.length; i++) {
			o.value(modeProfiles[i][0], modeProfiles[i][1]);
		}
		o.default = 'fast3';

		addCommonAdvancedOptions(s, 'advanced');

		// ===== Tab 2: Client Tunnels =====
		s = m.section(form.GridSection, 'client', _('Client Tunnels'),
			_('Configure local client listening ports and proxy modes. Transparent proxy (redir) handles smart split-routing automatically.'));
		s.anonymous = false;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.addbtntitle = _('Add Client Tunnel');

		s.handleAdd = function(ev, name) {
			let config_name = this.uciconfig || this.map.config;
			let section_id = this.map.data.add(config_name, this.sectiontype, name);
			this.map.data.set(config_name, section_id, 'proto', 'tcp');
			this.map.data.set(config_name, section_id, 'proxy_type', 'redir');
			let mapNode = this.getPreviousModalMap();
			let prevMap = mapNode ? dom.findClassInstance(mapNode) : this.map;
			prevMap.addedSection = section_id;
			return this.renderMoreOptionsModal(section_id);
		};

		s.tab('general', _('General Settings'));

		// --- Table Overview Columns (modalonly = false) ---
		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.enabled = '1';
		o.disabled = '0';
		o.default = '1';
		o.rmempty = false;
		o.editable = true;
		o.modalonly = false;

		o = s.option(form.DummyValue, '_proxy_type', _('Proxy Type'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			let proto = uci.get('xkcptun', section_id, 'proto') || 'tcp';
			if (proto === 'udp') return _('Port Forward');
			let val = uci.get('xkcptun', section_id, 'proxy_type') || 'redir';
			if (val === 'redir') return _('Transparent Proxy (redir)');
			if (val === 'socks5') return _('SOCKS5');
			return _('Port Forward');
		};

		o = s.option(form.ListValue, 'proto', _('Protocol'));
		o.value('tcp', 'TCP');
		o.value('udp', 'UDP');
		o.default = 'tcp';
		o.modalonly = false;

		o = s.option(form.Value, 'local_port', _('Local Port'));
		o.datatype = 'port';
		o.placeholder = '12345';
		o.modalonly = false;

		o = s.option(form.DummyValue, '_destination', _('Target / Destination'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			let proto = (this.map && this.map.data ? this.map.data.get('xkcptun', section_id, 'proto') : uci.get('xkcptun', section_id, 'proto')) || 'tcp';
			let ptype = (this.map && this.map.data ? this.map.data.get('xkcptun', section_id, 'proxy_type') : uci.get('xkcptun', section_id, 'proxy_type'));
			if (proto === 'udp') {
				ptype = 'forward';
			} else if (!ptype) {
				let target = (this.map && this.map.data ? this.map.data.get('xkcptun', section_id, 'target_addr') : uci.get('xkcptun', section_id, 'target_addr'));
				ptype = target ? 'forward' : 'redir';
			}
			if (ptype === 'redir') {
				return E('span', { 'style': 'color:#10b981; font-weight:600;' }, _('Dynamic / Smart Route'));
			} else if (ptype === 'socks5') {
				return E('span', { 'style': 'color:#6366f1; font-weight:600;' }, _('SOCKS5 Proxy'));
			} else {
				let host = (this.map && this.map.data ? this.map.data.get('xkcptun', section_id, 'target_addr') : uci.get('xkcptun', section_id, 'target_addr')) || '127.0.0.1';
				let port = (this.map && this.map.data ? this.map.data.get('xkcptun', section_id, 'target_port') : uci.get('xkcptun', section_id, 'target_port')) || _('(Dynamic/Auto)');
				return E('code', {}, host + ':' + port);
			}
		};

		// --- Modal Dialog Options: General Settings Tab (modalonly = true) ---
		o = s.taboption('general', form.Flag, 'enabled', _('Enable Tunnel'),
			_('Enable or disable this client tunnel.'));
		o.enabled = '1';
		o.disabled = '0';
		o.default = '1';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'name', _('Tunnel Name / Alias'),
			_('Descriptive name for this tunnel (e.g. redir_tunnel, dns_tunnel).'));
		o.placeholder = _('(Auto)');
		o.optional = true;
		o.modalonly = true;

		o = s.taboption('general', form.ListValue, 'proto', _('Protocol'),
			_('Protocol to tunnel: TCP (supports Transparent Proxy, Port Forward, SOCKS5) or UDP (Port Forward only, e.g. DNS).'));
		o.value('tcp', 'TCP');
		o.value('udp', 'UDP');
		o.default = 'tcp';
		o.rmempty = false;
		o.forcewrite = true;
		o.modalonly = true;

		// --- Modal Option: Proxy Type for TCP (3 modes available) ---
		o = s.taboption('general', form.ListValue, 'proxy_type', _('Proxy Type'),
			_('Proxy mode: Transparent Proxy (redir) automatically routes traffic from iptables/nftables/eBPF; Port Forward forwards local port to fixed server port; SOCKS5 provides local SOCKS5 proxy.'));
		o.depends('proto', 'tcp');
		o.value('redir', _('Transparent Proxy (redir)'));
		o.value('forward', _('Port Forward'));
		o.value('socks5', _('SOCKS5'));
		o.default = 'redir';
		o.rmempty = false;
		o.forcewrite = true;
		o.modalonly = true;
		o.write = function(section_id, formvalue) {
			return uci.set('xkcptun', section_id, 'proxy_type', formvalue || 'redir');
		};

		// --- Modal Option: Proxy Type for UDP (Port Forward only) ---
		o = s.taboption('general', form.ListValue, '_proxy_type_udp', _('Proxy Type'),
			_('UDP protocol in xkcptun only supports fixed-destination Port Forwarding (e.g. DNS tunnel).'));
		o.depends('proto', 'udp');
		o.value('forward', _('Port Forward (UDP only)'));
		o.default = 'forward';
		o.rmempty = false;
		o.forcewrite = true;
		o.modalonly = true;
		o.write = function(section_id, formvalue) {
			return uci.set('xkcptun', section_id, 'proxy_type', 'forward');
		};

		o = s.taboption('general', form.Value, 'local_interface', _('Local Interface'),
			_('Local network interface to listen on (default: any).'));
		o.placeholder = 'any';
		o.default = 'any';
		o.optional = true;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'local_port', _('Local Listen Port'),
			_('Local port on router to listen for traffic (e.g. 12345 for redir, 5353 for DNS).'));
		o.datatype = 'port';
		o.placeholder = '12345';
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'target_addr', _('Target Host (Port Forward only)'),
			_('Destination host on the server side (default: 127.0.0.1). Leave empty for Transparent Proxy.'));
		o.datatype = 'host';
		o.placeholder = '127.0.0.1';
		o.default = '127.0.0.1';
		o.optional = true;
		o.modalonly = true;
		o.depends('proxy_type', 'forward');
		o.depends('proto', 'udp');

		o = s.taboption('general', form.Value, 'target_port', _('Target Port (Port Forward only)'),
			_('Destination port on the server side. Leave empty for Transparent Proxy.'));
		o.datatype = 'port';
		o.placeholder = _('(Dynamic/Auto)');
		o.optional = true;
		o.modalonly = true;
		o.depends('proxy_type', 'forward');
		o.depends('proto', 'udp');

		// ===== Tab 3: Server Configuration (AI Prompt) =====
		let s_prompt = m.section(form.NamedSection, '_server_prompt', 'prompt', _('Server Configuration'));
		s_prompt.load = function() { return Promise.resolve(); };
		s_prompt.parse = function() { return Promise.resolve(); };
		s_prompt.render = function() {
			return Promise.resolve(renderPromptTab());
		};

		return m.render().then(function(mapNode) {
			let customStyle = E('style', {}, [
				'.cbi-tblsection { overflow-x: auto !important; }',
				'.cbi-section-table .cbi-section-actions { white-space: nowrap !important; text-align: right !important; min-width: 140px !important; width: 1% !important; }',
				'.cbi-section-table .cbi-section-actions > div { display: inline-flex !important; align-items: center !important; justify-content: flex-end !important; gap: 4px !important; }',
				'.xkcp-kpi-grid {',
				'    display: grid;',
				'    grid-template-columns: repeat(5, minmax(0, 1fr));',
				'    gap: 12px;',
				'    margin: 15px 0 25px 0;',
				'}',
				'.xkcp-kpi-card {',
				'    background: var(--cbi-section-bg, #fff);',
				'    border: 1px solid var(--cbi-section-border, rgba(0, 0, 0, 0.08));',
				'    border-radius: 10px;',
				'    padding: 14px 16px;',
				'    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.03);',
				'    transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;',
				'    display: flex;',
				'    flex-direction: column;',
				'    justify-content: space-between;',
				'    min-height: 86px;',
				'    box-sizing: border-box;',
				'}',
				'.xkcp-kpi-card:hover {',
				'    transform: translateY(-2px);',
				'    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);',
				'}',
				'.xkcp-kpi-header {',
				'    display: flex;',
				'    align-items: center;',
				'    justify-content: space-between;',
				'    font-size: 13px;',
				'    color: var(--cbi-descr-color, #666);',
				'    margin-bottom: 6px;',
				'    white-space: nowrap;',
				'}',
				'.xkcp-kpi-title {',
				'    font-weight: 500;',
				'}',
				'.xkcp-kpi-icon {',
				'    font-size: 16px;',
				'    line-height: 1;',
				'    opacity: 0.85;',
				'}',
				'.xkcp-kpi-val {',
				'    font-size: 24px;',
				'    font-weight: 700;',
				'    line-height: 1.2;',
				'    letter-spacing: -0.3px;',
				'}',
				'.xkcp-kpi-sub {',
				'    font-size: 11px;',
				'    color: #999;',
				'    margin-top: 3px;',
				'    white-space: nowrap;',
				'    overflow: hidden;',
				'    text-overflow: ellipsis;',
				'}',
				'@media screen and (max-width: 1080px) {',
				'    .xkcp-kpi-grid {',
				'        grid-template-columns: repeat(4, 1fr);',
				'    }',
				'    .xkcp-kpi-card.hero {',
				'        grid-column: span 4;',
				'        background: linear-gradient(135deg, rgba(6, 182, 212, 0.08) 0%, rgba(99, 102, 241, 0.08) 100%);',
				'        border-color: rgba(6, 182, 212, 0.25);',
				'        padding: 16px 20px;',
				'    }',
				'    .xkcp-kpi-card.hero .xkcp-kpi-val {',
				'        font-size: 28px;',
				'    }',
				'}',
				'@media screen and (max-width: 720px) {',
				'    .xkcp-kpi-grid {',
				'        grid-template-columns: repeat(2, 1fr);',
				'        gap: 10px;',
				'    }',
				'    .xkcp-kpi-card.hero {',
				'        grid-column: span 2;',
				'    }',
				'    .xkcp-kpi-card {',
				'        padding: 12px;',
				'        min-height: 76px;',
				'    }',
				'    .xkcp-kpi-val {',
				'        font-size: 20px;',
				'    }',
				'    .xkcp-kpi-header {',
				'        font-size: 12px;',
				'    }',
				'}'
			]);

			document.addEventListener('cbi-tab-active', function() {
				window.dispatchEvent(new Event('resize'));
			});

			getServiceStatus().then(function(status) {
				let view = document.getElementById('service_status');
				if (view) {
					dom.content(view, renderStatus(status));
				}
			});

			L.Poll.add(function () {
				return L.resolveDefault(getServiceStatus(), {}).then(function(status) {
					let view = document.getElementById('service_status');
					if (view) {
						dom.content(view, renderStatus(status));
					}
				});
			});

			return E('div', {}, [
				customStyle,
				E('h2', {}, _('xkcptun')),
				E('div', { 'class': 'cbi-map-descr' },
					_('xkcptun is a high-performance C implementation of kcptun with dynamic destination multi-tunnel unified daemon architecture.')
				),
				mapNode
			]);
		});
	},

	handleSaveApply: function(ev, mode) {
		return this.super('handleSaveApply', [ev, mode]).then(function() {
			return fs.exec_direct('/etc/init.d/xkcptun', ['restart']);
		});
	}
});
