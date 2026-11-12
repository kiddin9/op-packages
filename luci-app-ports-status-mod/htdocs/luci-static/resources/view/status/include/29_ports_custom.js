'use strict';
'require baseclass';
'require fs';
'require ui';
'require uci';
'require rpc';
'require network';
'require firewall';
'require dom';
'require poll';

(function() {
	var style = document.createElement('style');
	style.textContent = [
		'@keyframes status-blink { 0%, 60%, 100% { opacity: 1; } 30% { opacity: 0.2; } }',
		'.ports-operation-status {',
		'  display: none;',
		'  padding: 10px 14px;',
		'  border: 1px solid var(--border-color-medium);',
		'  border-radius: 5px;',
		'  margin: 0 0 10px 0;',
		'  font-size: 90%;',
		'}',
		'.ports-operation-status.active {',
		'  display: block;',
		'}',
		'.ports-operation-status .spinning {',
		'  display: inline-block;',
		'  margin-right: 8px;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox {',
		'  display: flex;',
		'  flex-direction: column;',
		'  align-items: stretch;',
		'  box-sizing: border-box;',
		'  text-align: center;',
		'  min-width: 60px !important;',
		'  max-width: 80px !important;',
		'  width: 100%;',
		'  margin: .2em auto !important;',
		'}',
		'html.theme-footstrap .ports-container {',
		'  grid-template-columns: repeat(auto-fit, minmax(60px, 80px)) !important;',
		'  justify-content: start;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .ifacebox-head,',
		'html.theme-footstrap .ports-container .ifacebox > .ifacebox-body {',
		'  display: block;',
		'  width: 100%;',
		'  box-sizing: border-box;',
		'  float: none;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .ifacebox-head.cbi-tooltip-container {',
		'  display: flex;',
		'}',
		'html.theme-footstrap .ports-container .port-speed-body {',
		'  padding: 0.3em 0.5em;',
		'  line-height: 1.3;',
		'}',
		'html.theme-footstrap .ports-container .port-speed-body img {',
		'  display: block;',
		'  margin: 0 auto 0.2em auto;',
		'}',
		'html.theme-footstrap .ports-container .port-speed-body .port-speed-text {',
		'  display: block;',
		'  width: 100%;',
		'  text-align: center;',
		'}',
		'html.theme-footstrap .ports-container .port-status-body {',
		'  display: block;',
		'  clear: both;',
		'  padding: 0.25em 0.5em;',
		'  text-align: center;',
		'  white-space: nowrap;',
		'  border-top: 1px solid var(--border-color-medium);',
		'  border-bottom: 1px solid var(--border-color-medium);',
		'}',
		'html.theme-footstrap .ports-container .port-status-body > span {',
		'  display: inline-block;',
		'  vertical-align: middle;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .port-label {',
		'  order: 1 !important;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .port-description {',
		'  order: 2 !important;',
		'  text-align: center;',
		'  border-bottom: 1px solid var(--border-color-medium);',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .port-speed-body {',
		'  order: 3 !important;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .ifacebox-head.cbi-tooltip-container {',
		'  order: 4 !important;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .port-status-body {',
		'  order: 5 !important;',
		'}',
		'html.theme-footstrap .ports-container .ifacebox > .port-traffic-body {',
		'  order: 6 !important;',
		'}'
	].join('\n');
	document.head.appendChild(style);

	try {
		var mediaBase = (window.L && L.env && L.env.mediaurlbase) || '';
		var isFootstrap = /footstrap/i.test(mediaBase) ||
			!!document.querySelector('link[rel="stylesheet"][href*="footstrap"]');

		if (isFootstrap)
			document.documentElement.classList.add('theme-footstrap');
	} catch (e) {
		console.warn('Theme detection failed:', e);
	}
})();

var callGetBuiltinEthernetPorts = rpc.declare({
	object: 'luci',
	method: 'getBuiltinEthernetPorts',
	expect: { result: [] }
});

var callWritePortConfig = rpc.declare({
	object: 'file',
	method: 'write',
	params: ['path', 'data'],
	expect: { }
});

var callGetPortsStatus = rpc.declare({
	object: 'ports-status-mod',
	method: 'getPortsStatus',
	expect: { }
});

var callSetPortStatus = rpc.declare({
	object: 'ports-status-mod',
	method: 'setPortStatus',
	params: ['port', 'status'],
	expect: { }
});

var USER_PORTS_FILE = '/etc/user_defined_ports.json';
var USER_PORTS_BACKUP = '/etc/user_defined_ports.json.bak';
var CONFIG_LOCK = false;
var isDragging = false;
var draggedElement = null;
var originalPorts = [];

var _portsStatusTimer = null;

function popTimeout(a, message, timeout, severity) {
    ui.addTimeLimitedNotification(a, message, timeout, severity);
}

function showPortsStatus(message) {
	var statusBox = document.getElementById('ports-operation-status');
	if (!statusBox) return;
	statusBox.innerHTML = '';
	var msgText = (message && message.textContent !== undefined)
		? message.textContent
		: (typeof message === 'string' ? message : '');
	statusBox.appendChild(E('span', {'class': 'spinning'}, msgText));
	statusBox.classList.add('active');
}

function hidePortsStatus() {
	var statusBox = document.getElementById('ports-operation-status');
	if (!statusBox) return;
	statusBox.classList.remove('active');
}

function showPortsStatusTimeout(message, timeout) {
	showPortsStatus(message);
	if (_portsStatusTimer) clearTimeout(_portsStatusTimer);
	_portsStatusTimer = setTimeout(function() {
		hidePortsStatus();
		_portsStatusTimer = null;
	}, timeout || 4000);
}

function isString(v)
{
	return typeof(v) === 'string' && v !== '';
}

function resolveVLANChain(ifname, bridges, mapping)
{
	while (!mapping[ifname]) {
		var m = ifname.match(/^(.+)\.([^.]+)$/);

		if (!m)
			break;

		if (bridges[m[1]]) {
			if (bridges[m[1]].vlan_filtering)
				mapping[ifname] = bridges[m[1]].vlans[m[2]];
			else
				mapping[ifname] = bridges[m[1]].ports;
		}
		else if (/^[0-9]{1,4}$/.test(m[2]) && m[2] <= 4095) {
			mapping[ifname] = [ m[1] ];
		}
		else {
			break;
		}

		ifname = m[1];
	}
}

function buildVLANMappings(mapping)
{
	var bridge_vlans = uci.sections('network', 'bridge-vlan'),
	    vlan_devices = uci.sections('network', 'device'),
	    interfaces = uci.sections('network', 'interface'),
	    bridges = {};

	/* find bridge VLANs */
	for (var i = 0, s; (s = bridge_vlans[i]) != null; i++) {
		if (!isString(s.device) || !/^[0-9]{1,4}$/.test(s.vlan) || +s.vlan > 4095)
			continue;

		var aliases = L.toArray(s.alias),
		    ports = L.toArray(s.ports),
		    br = bridges[s.device] = (bridges[s.device] || { ports: [], vlans: {}, vlan_filtering: true });

		br.vlans[s.vlan] = [];

		for (var j = 0; j < ports.length; j++) {
			var port = ports[j].replace(/:[ut*]+$/, '');

			if (br.ports.indexOf(port) === -1)
				br.ports.push(port);

			br.vlans[s.vlan].push(port);
		}

		for (var j = 0; j < aliases.length; j++)
			if (aliases[j] != s.vlan)
				br.vlans[aliases[j]] = br.vlans[s.vlan];
	}

	/* find bridges, VLAN devices */
	for (var i = 0, s; (s = vlan_devices[i]) != null; i++) {
		if (s.type == 'bridge') {
			if (!isString(s.name))
				continue;

			var ports = L.toArray(s.ports),
			    br = bridges[s.name] || (bridges[s.name] = { ports: [], vlans: {}, vlan_filtering: false });

			if (s.vlan_filtering == '0')
				br.vlan_filtering = false;
			else if (s.vlan_filtering == '1')
				br.vlan_filtering = true;

			for (var j = 0; j < ports.length; j++)
				if (br.ports.indexOf(ports[j]) === -1)
					br.ports.push(ports[j]);

			mapping[s.name] = br.ports;
		}
		else if (s.type == '8021q' || s.type == '8021ad') {
			if (!isString(s.name) || !isString(s.vid) || !isString(s.ifname))
				continue;

			/* parent device is a bridge */
			if (bridges[s.ifname]) {
				/* parent bridge is VLAN enabled, device refers to VLAN ports */
				if (bridges[s.ifname].vlan_filtering)
					mapping[s.name] = bridges[s.ifname].vlans[s.vid];

				/* parent bridge is not VLAN enabled, device refers to all bridge ports */
				else
					mapping[s.name] = bridges[s.ifname].ports;
			}

			/* parent is a simple netdev */
			else {
				mapping[s.name] = [ s.ifname ];
			}

			resolveVLANChain(s.ifname, bridges, mapping);
		}
	}

	/* resolve VLAN tagged interfaces in bridge ports */
	for (var brname in bridges) {
		for (var i = 0; i < bridges[brname].ports.length; i++)
			resolveVLANChain(bridges[brname].ports[i], bridges, mapping);

		for (var vid in bridges[brname].vlans)
			for (var i = 0; i < bridges[brname].vlans[vid].length; i++)
				resolveVLANChain(bridges[brname].vlans[vid][i], bridges, mapping);
	}

	/* find implicit VLAN devices */
	for (var i = 0, s; (s = interfaces[i]) != null; i++) {
		if (!isString(s.device))
			continue;

		resolveVLANChain(s.device, bridges, mapping);
	}
}

function resolveVLANPorts(ifname, mapping, seen)
{
	var ports = [];

	if (!seen)
		seen = {};

	if (mapping[ifname]) {
		for (var i = 0; i < mapping[ifname].length; i++) {
			if (!seen[mapping[ifname][i]]) {
				seen[mapping[ifname][i]] = true;
				ports.push.apply(ports, resolveVLANPorts(mapping[ifname][i], mapping, seen));
			}
		}
	}
	else {
		ports.push(ifname);
	}

	return ports.sort(L.naturalCompare);
}

function buildInterfaceMapping(zones, networks) {
	var vlanmap = {},
	    portmap = {},
	    netmap = {};

	buildVLANMappings(vlanmap);

	for (var i = 0; i < networks.length; i++) {
		var l3dev = networks[i].getDevice();

		if (!l3dev)
			continue;

		var ports = resolveVLANPorts(l3dev.getName(), vlanmap);

		for (var j = 0; j < ports.length; j++) {
			portmap[ports[j]] = portmap[ports[j]] || { networks: [], zones: [] };
			portmap[ports[j]].networks.push(networks[i]);
		}

		netmap[networks[i].getName()] = networks[i];
	}

	for (var i = 0; i < zones.length; i++) {
		var networknames = zones[i].getNetworks();

		for (var j = 0; j < networknames.length; j++) {
			if (!netmap[networknames[j]])
				continue;

			var l3dev = netmap[networknames[j]].getDevice();

			if (!l3dev)
				continue;

			var ports = resolveVLANPorts(l3dev.getName(), vlanmap);

			for (var k = 0; k < ports.length; k++) {
				portmap[ports[k]] = portmap[ports[k]] || { networks: [], zones: [] };

				if (portmap[ports[k]].zones.indexOf(zones[i]) === -1)
					portmap[ports[k]].zones.push(zones[i]);
			}
		}
	}

	return portmap;
}

function formatSpeed(carrier, speed, duplex) {
	if ((speed > 0) && duplex) {
		var d = (duplex == 'half') ? '\u202f(H)' : '',
		    e = E('span', { 'title': _('Speed: %d Mbit/s, Duplex: %s').format(speed, duplex) });

		switch (true) {
		case (speed < 1000):
			e.innerText = '%d\u202fM%s'.format(speed, d);
			break;
		case (speed == 1000):
			e.innerText = '1\u202fGbE' + d;
			break;
		case (speed >= 1e6 && speed < 1e9):
			e.innerText = '%f\u202fTbE'.format(speed / 1e6);
			break;
		case (speed >= 1e9):
			e.innerText = '%f\u202fPbE'.format(speed / 1e9);
			break;
		default: e.innerText = '%f\u202fGbE'.format(speed / 1000);
		}

		return e;
	}

	return carrier ? _('Connected') : _('no link');
}

function formatStats(portdev) {
	var stats = portdev._devstate('stats') || {};

	return ui.itemlist(E('span'), [
		_('Received bytes'), '%1024mB'.format(stats.rx_bytes),
		_('Received packets'), '%1000mPkts.'.format(stats.rx_packets),
		_('Received multicast'), '%1000mPkts.'.format(stats.multicast),
		_('Receive errors'), '%1000mPkts.'.format(stats.rx_errors),
		_('Receive dropped'), '%1000mPkts.'.format(stats.rx_dropped),

		_('Transmitted bytes'), '%1024mB'.format(stats.tx_bytes),
		_('Transmitted packets'), '%1000mPkts.'.format(stats.tx_packets),
		_('Transmit errors'), '%1000mPkts.'.format(stats.tx_errors),
		_('Transmit dropped'), '%1000mPkts.'.format(stats.tx_dropped),

		_('Collisions seen'), stats.collisions
	]);
}

function renderNetworkBadge(network, zonename) {
	var l3dev = network.getDevice();
	var span = E('span', { 'class': 'ifacebadge', 'style': 'margin:.125em 0' }, [
		E('span', {
			'class': 'zonebadge',
			'title': zonename ? _('Part of zone %q').format(zonename) : _('No zone assigned'),
			'style': firewall.getZoneColorStyle(zonename)
		}, '\u202f'),
		'\u202f', network.getName(), ': '
	]);

	if (l3dev)
		span.appendChild(E('img', {
			'title': l3dev.getI18n(),
			'src': L.resource('icons/%s%s.svg'.format(l3dev.getType(), l3dev.isUp() ? '' : '_disabled'))
		}));
	else
		span.appendChild(E('em', _('(no interfaces attached)')));

	return span;
}

function renderNetworksTooltip(pmap) {
	var res = [ null ],
	    zmap = {};

	for (var i = 0; pmap && i < pmap.zones.length; i++) {
		var networknames = pmap.zones[i].getNetworks();

		for (var k = 0; k < networknames.length; k++)
			zmap[networknames[k]] = pmap.zones[i].getName();
	}

	for (var i = 0; pmap && i < pmap.networks.length; i++)
		res.push(E('br'), renderNetworkBadge(pmap.networks[i], zmap[pmap.networks[i].getName()]));

	if (res.length > 1)
		res[0] = N_((res.length - 1) / 2, 'Part of network:', 'Part of networks:');
	else
		res[0] = _('Port is not part of any network');

	return E([], res);
}

function validatePortsConfig(config) {
	if (!config) {
		console.error('Config is null or undefined');
		return false;
	}
	
	if (!Array.isArray(config)) {
		console.error('Config is not an array');
		return false;
	}
	
	if (config.length === 0) {
		console.error('Config is empty array');
		return false;
	}
	
	for (var i = 0; i < config.length; i++) {
		if (!config[i].device || typeof config[i].device !== 'string') {
			console.error('Invalid device field at index', i);
			return false;
		}
	}
	
	console.log('Config validation passed:', config.length, 'ports');
	return true;
}

function loadUserPorts() {
	return L.resolveDefault(fs.read(USER_PORTS_FILE), null).then(function(content) {
		if (!content || content.trim() === '' || content.trim() === '[]') {
			console.log('User ports file is empty or missing');
			return null;
		}
		try {
			var parsed = JSON.parse(content);
			if (Array.isArray(parsed) && parsed.length === 0) {
				console.log('User ports file contains empty array');
				return null;
			}
			if (!validatePortsConfig(parsed)) {
				console.error('Invalid ports configuration detected');
				ui.addNotification(null, E('p', _('Port config file is corrupted. Use "Restore backup .bak" from edit modal.')), 'error');
				return null;
			}
			console.log('Successfully loaded user ports config:', parsed.length, 'ports');
			return parsed;
		} catch(e) {
			console.error('Failed to parse user ports config:', e);
			ui.addNotification(null, E('p', _('Port config parse error. Use "Restore backup .bak" from edit modal.')), 'error');
			return null;
		}
	}).catch(function(err) {
		console.log('User ports file does not exist yet:', err);
		return null;
	});
}


function setFileReadOnly(filepath) {
	return fs.exec('/bin/chmod', ['444', filepath]).then(function(res) {
		if (res.code === 0) {
			console.log('File set to read-only (444):', filepath);
		} else {
			console.warn('Failed to set read-only on', filepath, ':', res.stderr);
		}
	}).catch(function(err) {
		console.warn('chmod 444 error for', filepath, ':', err);
	});
}

function ensureFileWritable(filepath) {
	return fs.exec('/bin/chmod', ['644', filepath]).then(function(res) {
		if (res.code === 0) {
			console.log('File set to writable (644):', filepath);
			return true;
		} else {
			return fs.exec('/bin/touch', [filepath]).then(function(touchRes) {
				if (touchRes.code === 0) {
					return fs.exec('/bin/chmod', ['644', filepath]).then(function() { return true; });
				}
				console.warn('Could not create or chmod file:', filepath);
				return false;
			});
		}
	}).catch(function(err) {
		console.warn('ensureFileWritable error for', filepath, ':', err);
		return false;
	});
}

function verifyFileSaved(filepath, expectedContent) {
	return L.resolveDefault(fs.read(filepath), null).then(function(content) {
		if (!content) {
			console.error('Verification failed: file empty after save');
			return false;
		}
		var ok = content.trim().substring(0, 80) === expectedContent.trim().substring(0, 80);
		if (!ok) {
			console.error('Verification failed: content mismatch');
		}
		return ok;
	}).catch(function() { return false; });
}

function saveUserPorts(ports) {
	if (CONFIG_LOCK) {
		console.warn('Save operation already in progress, skipping...');
		return Promise.reject(new Error('Save operation locked'));
	}
	
	CONFIG_LOCK = true;
	
	if (!ports || !Array.isArray(ports) || ports.length === 0) {
		CONFIG_LOCK = false;
		console.error('Refusing to save empty or invalid configuration');
		ui.addNotification(null, E('p', _('Cannot save empty configuration')), 'error');
		return Promise.reject(new Error('Invalid configuration'));
	}
	
	var config = ports.map(function(port) {
		return {
			device: port.device,
			label: port.label || port.device,
			role: port.role,
			originalLabel: port.originalLabel || port.device,
			description: port.description || ''
		};
	});
	
	var jsonContent = JSON.stringify(config, null, 2);
	
	return ensureFileWritable(USER_PORTS_FILE).then(function(writable) {
		if (!writable) {
			CONFIG_LOCK = false;
			var msg = _('Cannot make config file writable. Check /etc permissions.');
			ui.addNotification(null, E('p', msg), 'error');
			throw new Error(msg);
		}
		return fs.write(USER_PORTS_FILE, jsonContent);
	}).then(function() {
		return verifyFileSaved(USER_PORTS_FILE, jsonContent).then(function(ok) {
			if (!ok) {
				CONFIG_LOCK = false;
				var msg = _('Save verification failed - file content mismatch!');
				ui.addNotification(null, E('p', msg), 'error');
				throw new Error(msg);
			}
			console.log('Save verified successfully for', USER_PORTS_FILE);
			return setFileReadOnly(USER_PORTS_FILE).then(function() {
				CONFIG_LOCK = false;
				return true;
			});
		});
	}).catch(function(err) {
		CONFIG_LOCK = false;
		console.error('saveUserPorts failed:', err);
		throw err;
	});
}

function mergePortConfigs(detectedPorts, userConfig) {
	if (!userConfig || !Array.isArray(userConfig) || userConfig.length === 0) {
		console.log('No valid user config, using detected ports');
		return detectedPorts;
	}
	
	var userMap = {};
	userConfig.forEach(function(p) {
		if (p && p.device) {
			userMap[p.device] = p;
		}
	});
	
	var merged = [];
	var addedDevices = {};
	
	userConfig.forEach(function(userPort) {
		if (!userPort || !userPort.device) return;
		
		var detected = detectedPorts.find(function(p) { return p.device === userPort.device; });
		if (detected) {
			merged.push({
				device: detected.device,
				role: detected.role,
				netdev: detected.netdev,
				label: userPort.label || detected.device,
				originalLabel: userPort.originalLabel || detected.device,
				description: userPort.description || ''
			});
			addedDevices[userPort.device] = true;
		}
	});

	detectedPorts.forEach(function(port) {
		if (!addedDevices[port.device]) {
			merged.push({
				device: port.device,
				role: port.role,
				netdev: port.netdev,
				label: port.device,
				originalLabel: port.originalLabel || port.device,
				description: ''
			});
		}
	});
	
	console.log('Merged config: detected=' + detectedPorts.length + ', user=' + userConfig.length + ', result=' + merged.length);
	return merged;
}

function showEditLabelModal(port, labelElement, descriptionElement, statusElement, ports) {
	poll.stop();
	
	var modalTitle = _('Edit Port Label');
	var currentLabel = port.label || port.device;
	var currentDescription = port.description || '';
	var originalLabel = port.originalLabel || port.device;
	
	var statusRadioUp = E('input', {
		'type': 'radio',
		'name': 'port_status',
		'value': 'up',
		'id': 'port-status-up',
		'disabled': true
	});
	
	var statusRadioDown = E('input', {
		'type': 'radio',
		'name': 'port_status',
		'value': 'down',
		'id': 'port-status-down',
		'disabled': true
	});
	
	var isLanPort = false;
	
	L.resolveDefault(callGetPortsStatus(), {}).then(function(portsStatus) {
		var deviceForStatus = port.device.split('@')[0];
		var operstate = portsStatus[deviceForStatus];
		
		if (operstate !== undefined) {
			isLanPort = true;
			statusRadioUp.disabled = false;
			statusRadioDown.disabled = false;
			
			var isCurrentlyEnabled = (operstate !== 'disabled');
			
			if (isCurrentlyEnabled) {
				statusRadioUp.checked = true;
			} else {
				statusRadioDown.checked = true;
			}
			port._currentOperstate = operstate;
		} else {
			var msgElement = document.getElementById('port-status-message');
			if (msgElement) {
				msgElement.style.display = 'block';
			}
		}
		
		console.log('Modal opened for port:', port.device);
		console.log('Device for status lookup:', deviceForStatus);
		console.log('Operstate from rpcd:', operstate);
		console.log('isLanPort (enabled):', isLanPort);
	});
	
	var labelInputEl = E('input', {
		'type': 'text',
		'class': 'cbi-input-text',
		'value': currentLabel,
		'style': 'width: 100%; margin-bottom: 1em;',
		'placeholder': port.device,
		'maxlength': '9'
	});
	
	var descriptionInputEl = E('input', {
		'type': 'text',
		'class': 'cbi-input-text',
		'value': currentDescription,
		'style': 'width: 100%; margin-bottom: 1em;',
		'placeholder': _(''),
		'maxlength': '50'
	});
	
	var infoText = E('p', { 'style': 'margin: 0.5em 0; font-size: 90%; color: var(--text-color-secondary);' }, [
		_('Device')+': ',
		E('strong', {}, port.device),
		E('br'),
		_('Original label')+': ',
		E('strong', {}, originalLabel),
		E('br'),
		E('small', {}, _('Label max 9 chars, description max 50 chars.')),
		E('br'),
		E('small', {}, _('User settings are saved to the /etc/user_defined_ports.json file.'))
	]);
	
	var statusSection = [
		E('p', { 'style': 'margin-top: 1em;' }, _('Change port state')),
		E('div', { 'style': 'margin-bottom: 1em;' }, [
			E('label', {
				'data-tooltip': _('Enable this port')
			}, [
				statusRadioUp,
				' ',
				_('Enable port')
			]),
			' \u00a0 ',
			E('label', {
				'data-tooltip': _('Disable this port')
			}, [
				statusRadioDown,
				' ',
				_('Disable port')
			])
		]),
		E('div', { 
			'id': 'port-status-message',
			'style': 'margin-top: 8px; padding: 8px; background: var(--background-color-medium); border: 1px solid var(--border-color-medium); border-radius: 4px; font-size: 12px; color: var(--text-color-secondary); display: none;' 
		}, [
			_('Changing port state is available only for LAN ports')
		])
	];
	
	var modalContent = E('div', {}, [
		E('p', {}, _('Enter new label for this port:')),
		labelInputEl,
		E('p', { 'style': 'margin-top: 1em;' }, _('Enter description (optional):')),
		descriptionInputEl
	].concat(statusSection).concat([infoText]));
	
	var restoreBtn = E('button', {
		'class': 'cbi-button cbi-button-neutral',
		'click': function(ev) {
			labelInputEl.value = originalLabel;
			descriptionInputEl.value = '';
			ev.target.blur();
			labelInputEl.focus();
		}
	}, _('Restore Original'));
	
	var handleDownloadConfig = function() {
		L.resolveDefault(fs.read(USER_PORTS_FILE), null).then(function(content) {
			if (content) {
				var link = E('a', {
					'download': 'user_defined_ports.json',
					'href': URL.createObjectURL(new Blob([content], {
						type: 'application/json'
					}))
				});
				link.click();
				URL.revokeObjectURL(link.href);
			} else {
				ui.addNotification(null, E('p', _('Configuration file not found')), 'warning');
			}
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Download error: %s').format(err.message)), 'error');
		});
	};
	
	var handleUploadConfig = function(ev) {
		var fileInput = E('input', {
			'type': 'file',
			'accept': '.json',
			'style': 'display: none',
			'change': function(e) {
				var file = e.target.files[0];
				if (!file) return;
				
				var reader = new FileReader();
				reader.onload = function(event) {
					try {
						var config = JSON.parse(event.target.result);
						
						if (!Array.isArray(config)) {
							throw new Error(_('Invalid configuration format'));
						}
						
						if (!validatePortsConfig(config)) {
							throw new Error(_('Configuration validation failed'));
						}
						
						ui.showModal(_('Restore configuration'), [
							E('p', _('This will overwrite current ports configuration. Continue?')),
							E('p', {}, [
								E('strong', {}, _('File contains:')),
								' ', config.length, ' ', _('ports')
							]),
							E('div', { 'class': 'right' }, [
								E('button', {
									'class': 'cbi-button cbi-button-neutral',
									'click': function() {
										ui.hideModal();
										poll.start();
									}
								}, _('Cancel')),
								' ',
								E('button', {
									'class': 'cbi-button cbi-button-positive',
									'click': function() {
										fs.write(USER_PORTS_FILE, JSON.stringify(config, null, 2)).then(function() {
											ui.hideModal();
											popTimeout(null, E('p', _('Configuration restored successfully. Reloading...')), 5000, 'info');
											setTimeout(function() {
												window.location.reload();
											}, 1500);
										}).catch(function(err) {
											ui.hideModal();
											ui.addNotification(null, E('p', _('File restore failed: %s').format(err.message)), 'error');
											poll.start();
										});
									}
								}, _('Restore'))
							])
						]);
					} catch(err) {
						ui.addNotification(null, E('p', _('Invalid JSON file: %s').format(err.message)), 'error');
					}
				};
				reader.readAsText(file);
			}
		});
		
		document.body.appendChild(fileInput);
		fileInput.click();
		document.body.removeChild(fileInput);
	};
	
	var handleRestoreBackup = function() {
		L.resolveDefault(fs.read(USER_PORTS_BACKUP), null).then(function(backupContent) {
			if (!backupContent) {
				ui.addNotification(null, E('p', _('No backup file found')), 'warning');
				return;
			}
			
			try {
				var backupConfig = JSON.parse(backupContent);
				if (!validatePortsConfig(backupConfig)) {
					throw new Error('Invalid backup configuration');
				}
				
				ui.showModal(_('Restore from backup'), [
					E('p', _('Restore configuration from backup file? This will overwrite current settings.')),
					E('p', {}, [
						E('strong', {}, _('Backup contains:')),
						' ', backupConfig.length, ' ', _('ports')
					]),
					E('div', { 'class': 'right' }, [
						E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'click': function() {
								ui.hideModal();
								poll.start();
							}
						}, _('Cancel')),
						' ',
						E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'click': function() {
								ensureFileWritable(USER_PORTS_FILE).then(function() {
									return fs.write(USER_PORTS_FILE, backupContent);
								}).then(function() {
									return verifyFileSaved(USER_PORTS_FILE, backupContent);
								}).then(function(ok) {
									if (!ok) throw new Error('Verification failed');
									return setFileReadOnly(USER_PORTS_FILE);
								}).then(function() {
									ui.hideModal();
                                    popTimeout(null, E('p', _('Configuration restored from backup. Reloading...')), 5000, 'info');									
									setTimeout(function() { window.location.reload(); }, 1500);
								}).catch(function(err) {
									ui.hideModal();
									ui.addNotification(null, E('p', _('Restore failed: %s').format(err.message)), 'error');
									poll.start();
								});
							}
						}, _('Restore'))
					])
				]);
			} catch(e) {
				ui.addNotification(null, E('p', _('Backup file is corrupted: %s').format(e.message)), 'error');
			}
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Error reading backup: %s').format(err.message)), 'error');
		});
	};
	
	var handleCreateBackup = function() {
		L.resolveDefault(fs.read(USER_PORTS_FILE), null).then(function(content) {
			if (!content) {
				ui.addNotification(null, E('p', _('No config file to backup')), 'warning');
				return;
			}
			try {
				var parsed = JSON.parse(content);
				if (!validatePortsConfig(parsed)) throw new Error('invalid');
			} catch(e) {
				ui.addNotification(null, E('p', _('Config file is corrupted, cannot create backup')), 'error');
				return;
			}
			ensureFileWritable(USER_PORTS_BACKUP).then(function() {
				return fs.write(USER_PORTS_BACKUP, content);
			}).then(function() {
				return verifyFileSaved(USER_PORTS_BACKUP, content);
			}).then(function(ok) {
				if (ok) {
					return setFileReadOnly(USER_PORTS_BACKUP).then(function() {
						popTimeout(null, E('p', _('Backup file created: %s').format(USER_PORTS_BACKUP)), 5000, 'info');
					});
				} else {
					ui.addNotification(null, E('p', _('Backup write verification failed!')), 'error');
				}
			}).catch(function(err) {
				ui.addNotification(null, E('p', _('Backup creation failed: %s').format(err.message)), 'error');
			});
		}).catch(function(err) {
			ui.addNotification(null, E('p', _('Error reading config: %s').format(err.message)), 'error');
		});
	};

	var backupComboButton = new ui.ComboButton('_backup', {
		'_backup': _('Create backup .bak'),
		'_save': _('Save .json file'),
		'_upload': _('Upload .json file'),
		'_restore_backup': _('Restore backup .bak')
	}, {
		'click': function(ev, name) {
			if (name === '_backup') {
				handleCreateBackup();
			} else if (name === '_save') {
				handleDownloadConfig();
			} else if (name === '_upload') {
				handleUploadConfig(ev);
			} else if (name === '_restore_backup') {
				handleRestoreBackup();
			}
		},
		'classes': {
			'_backup': 'cbi-button cbi-button-action',
			'_save': 'cbi-button cbi-button-neutral',
			'_upload': 'cbi-button cbi-button-neutral',
			'_restore_backup': 'cbi-button cbi-button-negative'
		}
	}).render();
	
	ui.showModal(modalTitle, [
		modalContent,
		E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center;' }, [
			E('div', {}, [
				backupComboButton
			]),
			E('div', { 'class': 'right' }, [
				restoreBtn,
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': function() {
						ui.hideModal();
						poll.start();
					}
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': function() {
						var newLabel = labelInputEl.value.trim();
						var newDescription = descriptionInputEl.value.trim();
						
						if (newLabel === '') {
							newLabel = port.device;
						}
						
						port.label = newLabel;
						port.description = newDescription;
						labelElement.textContent = newLabel;
						
						if (newDescription) {
							descriptionElement.textContent = newDescription;
							descriptionElement.style.display = 'block';
						} else {
							descriptionElement.textContent = '';
							descriptionElement.style.display = 'none';
						}
						
						var newStatusEnabled = document.getElementById('port-status-up').checked;
						var currentOperstate = port._currentOperstate || 'unknown';
						var isCurrentlyEnabled = (currentOperstate !== 'disabled');
						var statusChanged = isLanPort && (newStatusEnabled !== isCurrentlyEnabled);
						
						ui.showModal(null, E('p', { 'class': 'spinning' }, _('Saving configuration...')));
						
						var promises = [saveUserPorts(ports)];
						
						if (statusChanged) {
							var newStatus = newStatusEnabled ? 'up' : 'down';
							promises.push(
								L.resolveDefault(callSetPortStatus(port.device, newStatus), {})
									.then(function(res) {
										if (res && res.success) {
											var newOperstate = newStatusEnabled ? 'idle' : 'disabled';
											var statusColor = '#888';
											var statusText = _('Down');
											var statusAnimate = '';
											
											if (newOperstate === 'disabled') {
												statusColor = '#FF204E'; // Red
												statusText = _('Disabled');
											} else if (newOperstate === 'idle') {
												statusColor = '#FFF455'; // Yellow
												statusText = _('Idle');
											}
											
											var statusDot = E('span', {
												'style': 'display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px;background-color:' + statusColor + ';' + statusAnimate
											});
											
											dom.content(statusElement, [ statusDot, statusText ]);
											port._operstate = newOperstate;
											port._currentOperstate = newOperstate;
											
											var msg = newStatusEnabled ? _('Port has been enabled successfully') : _('Port has been disabled successfully');
											showPortsStatusTimeout(msg, 5000);
										} else {
											showPortsStatusTimeout(_('Failed to change port status'), 5000);
										}
									})
									.catch(function(err) {
										showPortsStatusTimeout(_('Error changing port status'), 5000);
									})
							);
						}
						
						Promise.all(promises).then(function() {
							ui.hideModal();
							showPortsStatusTimeout(_('Port configuration saved successfully'), 5000);
							poll.start();
						}).catch(function(err) {
							ui.hideModal();
							poll.start();
						});
					}
				}, _('Save'))
			])
		])
	]);
	
	setTimeout(function() {
		labelInputEl.focus();
		labelInputEl.select();
	}, 100);
	
	var handleKeydown = function(ev) {
		if (ev.key === 'Enter') {
			ev.preventDefault();
			var saveBtn = modalContent.parentNode.querySelector('.cbi-button-positive');
			if (saveBtn) {
				saveBtn.click();
			}
		} else if (ev.key === 'Escape') {
			ev.preventDefault();
			ui.hideModal();
			poll.start();
		}
	};
	
	labelInputEl.addEventListener('keydown', handleKeydown);
	descriptionInputEl.addEventListener('keydown', handleKeydown);
}

function makeEditable(element, descriptionElement, statusElement, port, ports) {
	element.style.cursor = 'pointer';
	element.title = _('Click to edit label');
	
	element.addEventListener('click', function(ev) {
		if (isDragging)
			return;
		
		ev.stopPropagation();
		ev.preventDefault();
		
		showEditLabelModal(port, element, descriptionElement, statusElement, ports);
	});
}

function makeDraggable(element, port, container, ports) {
    var dragHandle = E('div', {
        'class': 'drag-handle',
        'style': 'position: absolute; top: 0; left: 0; right: 0; bottom: 0; cursor: move; z-index: 1; pointer-events: none;',
        'title': _('Hold to drag and reorder')
    });

    element.style.position = 'relative';
    element.appendChild(dragHandle);

    var clickTimer = null;
    var clickStart = null;
    var hasMoved = false;
    var isTouch = false;

    function startDrag(ev) {
        isDragging = true;
        draggedElement = element;
        poll.stop();

        element.style.opacity = '0.5';
        element.style.zIndex = '1000';
        dragHandle.style.cursor = 'move';
        dragHandle.style.pointerEvents = 'auto';

        document.body.style.cursor = 'move';

        var placeholder = E('div', {
            'class': 'ifacebox drag-placeholder',
            'style': element.style.cssText + 'opacity: 0.3; border: 3px dashed var(--border-color-medium); background: var(--border-color-low);'
        });

        element.style.boxShadow = '0 5px 15px var(--border-color-strong)';

        function onMouseMove(e) {
            if (isTouch && e.cancelable) {
                e.preventDefault();
            }
            
            var clientX = e.clientX;
            if (e.touches && e.touches.length > 0) {
                clientX = e.touches[0].clientX;
            }
            
            var afterElement = getDragAfterElement(container, clientX);
            if (afterElement == null) {
                container.appendChild(placeholder);
            } else {
                container.insertBefore(placeholder, afterElement);
            }
        }

        function onMouseUp(e) {
            document.removeEventListener('mousemove', onMouseMove);
            document.removeEventListener('mouseup', onMouseUp);
            document.removeEventListener('touchmove', onMouseMove, { passive: false });
            document.removeEventListener('touchend', onMouseUp);

            var clientX = e.clientX;
            if (e.changedTouches && e.changedTouches.length > 0) {
                clientX = e.changedTouches[0].clientX;
            }
            
            var afterElement = getDragAfterElement(container, clientX);
            if (afterElement == null) {
                container.appendChild(element);
            } else {
                container.insertBefore(element, afterElement);
            }

            if (placeholder.parentNode)
                placeholder.parentNode.removeChild(placeholder);

            element.style.opacity = '1';
            element.style.zIndex = '';
            element.style.boxShadow = '';
            dragHandle.style.cursor = 'move';
            dragHandle.style.pointerEvents = 'none';
            document.body.style.cursor = '';

            var newOrder = Array.from(container.children).map(function(el) {
                return el.__port__;
            }).filter(function(p) { return p; });

            ports.length = 0;
            newOrder.forEach(function(p) { ports.push(p); });

            saveUserPorts(ports).then(function() {
                isDragging = false;
                draggedElement = null;
                isTouch = false;
                showPortsStatusTimeout(_('Port order saved'), 4000);
                poll.start();
            }).catch(function(err) {
                isDragging = false;
                draggedElement = null;
                isTouch = false;
                poll.start();
            });
        }

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
        document.addEventListener('touchmove', onMouseMove, { passive: false });
        document.addEventListener('touchend', onMouseUp);
    }

    function getDragAfterElement(container, x) {
        var draggableElements = Array.from(container.children).filter(function(child) {
            return child !== draggedElement && child.classList.contains('ifacebox');
        });

        return draggableElements.reduce(function(closest, child) {
            var box = child.getBoundingClientRect();
            var offset = x - box.left - box.width / 2;

            if (offset < 0 && offset > closest.offset) {
                return { offset: offset, element: child };
            } else {
                return closest;
            }
        }, { offset: Number.NEGATIVE_INFINITY }).element;
    }

    function onPointerDown(ev) {
        if (ev.target.classList.contains('port-label') || ev.target.closest('.port-label')) {
            return;
        }

        isTouch = (ev.type === 'touchstart');
        
        if (!isTouch && ev.button !== undefined && ev.button !== 0) {
            return;
        }

        var clientX = ev.clientX;
        var clientY = ev.clientY;
        
        if (isTouch && ev.touches && ev.touches.length > 0) {
            clientX = ev.touches[0].clientX;
            clientY = ev.touches[0].clientY;
        }
        
        clickStart = { x: clientX, y: clientY };
        hasMoved = false;

        var delay = isTouch ? 600 : 300;
        
        clickTimer = setTimeout(function() {
            if (!hasMoved) {
                startDrag(ev);
            }
        }, delay);

        if (isTouch) {
            ev.preventDefault();
        }
    }

    function onPointerUp(ev) {
        if (clickTimer) {
            clearTimeout(clickTimer);
            clickTimer = null;
        }
        hasMoved = false;
        clickStart = null;
    }

    function onPointerMove(ev) {
        if (clickTimer && clickStart) {
            var clientX = ev.clientX;
            var clientY = ev.clientY;
            
            if (isTouch && ev.touches && ev.touches.length > 0) {
                clientX = ev.touches[0].clientX;
                clientY = ev.touches[0].clientY;
            }
            
            var distance = Math.sqrt(
                Math.pow(clientX - clickStart.x, 2) + 
                Math.pow(clientY - clickStart.y, 2)
            );
            
            if (distance > 10) {
                hasMoved = true;
                clearTimeout(clickTimer);
                clickTimer = null;
            }
        }
    }

    element.addEventListener('mousedown', onPointerDown);
    element.addEventListener('touchstart', onPointerDown, { passive: false });
    document.addEventListener('mouseup', onPointerUp);
    document.addEventListener('touchend', onPointerUp);
    document.addEventListener('mousemove', onPointerMove);
    document.addEventListener('touchmove', onPointerMove, { passive: false });
}

return baseclass.extend({
	title: _('Port status'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callGetBuiltinEthernetPorts(), []),
			L.resolveDefault(fs.read('/etc/board.json'), '{}'),
			firewall.getZones(),
			network.getNetworks(),
			uci.load('network'),
			loadUserPorts(),
			L.resolveDefault(callGetPortsStatus(), {})
		]);
	},

	render: function(data) {
		if (L.hasSystemFeature('swconfig'))
			return null;

		var board = JSON.parse(data[1]),
		    detected_ports = [],
		    port_map = buildInterfaceMapping(data[2], data[3]),
		    userConfig = data[5],
		    portsStatus = data[6] || {};

		if (Array.isArray(data[0]) && data[0].length > 0) {
			detected_ports = data[0].map(function(port) {
				return {
					device: port.device,
					role: port.role,
					netdev: network.instantiateDevice(port.device),
					originalLabel: port.label || port.device
				};
			});
		}
		else {
			if (L.isObject(board) && L.isObject(board.network)) {
				for (var k = 'lan'; k != null; k = (k == 'lan') ? 'wan' : null) {
					if (!L.isObject(board.network[k]))
						continue;

					if (Array.isArray(board.network[k].ports))
						for (var i = 0; i < board.network[k].ports.length; i++)
							detected_ports.push({
								role: k,
								device: board.network[k].ports[i],
								netdev: network.instantiateDevice(board.network[k].ports[i]),
								originalLabel: board.network[k].ports[i]
							});
					else if (typeof(board.network[k].device) == 'string')
						detected_ports.push({
							role: k,
							device: board.network[k].device,
							netdev: network.instantiateDevice(board.network[k].device),
							originalLabel: board.network[k].device
						});
				}
			}
		}

		detected_ports.sort(function(a, b) {
			return L.naturalCompare(a.device, b.device);
		});

		if (!userConfig || !validatePortsConfig(userConfig)) {
			var initialConfig = detected_ports.map(function(p) {
				return {
					device: p.device,
					label: p.device,
					role: p.role,
					originalLabel: p.originalLabel || p.device,
					description: ''
				};
			});
			
			if (initialConfig.length > 0) {
				console.log('Creating initial port configuration with', initialConfig.length, 'ports');
				saveUserPorts(initialConfig).then(function() {
					console.log('Initial configuration created successfully');
				}).catch(function(err) {
					console.error('Failed to create initial configuration:', err);
				});
				
				userConfig = initialConfig;
			}
		} else {
			console.log('Using existing configuration with', userConfig.length, 'ports');
		}

		var known_ports = mergePortConfigs(detected_ports, userConfig);
		originalPorts = known_ports.slice();

		var statusBar = E('div', {
			'id': 'ports-operation-status',
			'class': 'ports-operation-status'
		});

		var container = E('div', { 
			'class': 'ports-container',
			'style': 'display:grid;grid-template-columns:repeat(auto-fit, minmax(70px, 1fr));margin-bottom:1em' 
		});

		var wrapper = E('div', {}, [ statusBar, container ]);

		known_ports.forEach(function(port) {
			var speed = port.netdev.getSpeed(),
			    duplex = port.netdev.getDuplex(),
			    carrier = port.netdev.getCarrier(),
			    pmap = port_map[port.netdev.getName()],
			    pzones = (pmap && pmap.zones.length) ? pmap.zones.sort(function(a, b) { return L.naturalCompare(a.getName(), b.getName()) }) : [ null ];

			var labelDiv = E('div', { 
				'class': 'ifacebox-head port-label', 
				'style': 'font-weight:bold; position: relative; z-index: 2; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; padding: 0.25em 0.5em;' 
			}, [ port.label || port.device ]);

			var descriptionDiv = E('div', { 
				'class': 'ifacebox-body port-description', 
				'style': 'font-size:70%; color: var(--text-color-secondary); padding: 0.2em 0.5em; min-height: 1.2em; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; cursor: help; display: ' + (port.description ? 'block' : 'none'),
				'title': port.description || ''
			}, [ port.description || '' ]);

			var deviceForStatus = port.device.split('@')[0];
			var operstate = portsStatus[deviceForStatus] || 'unknown';

			var statusColor = '#ccc';
			var statusText = _('Down');
			var statusAnimate = '';
			
			if (operstate === 'disabled') {
				statusColor = '#FF204E'; // Red
				statusText = _('Disabled');
			} else if (operstate === 'down') {
				statusColor = '#ccc'; // Gray
				statusText = _('Down');
			} else if (operstate === 'idle') {
				statusColor = '#FFA500'; // Orange - idle
				statusText = _('Idle');
			} else if (operstate === 'active') {
				statusColor = '#39FF13'; // Light green - active
				statusText = _('Active');
				statusAnimate = 'animation: status-blink 0.8s infinite;';
			} else {
				statusColor = '#ccc';
				statusText = _('Unknown');
			}
			
			var statusDot = E('span', {
				'style': 'display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px;background-color:' + statusColor + ';' + statusAnimate
			});
			
			var statusElement = E('span', { 
				'style': 'font-size: 85%; display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;'
			}, [ statusDot, statusText ]);
			
			port._operstate = operstate;
			port._currentOperstate = operstate;
			port._isLanPort = true;

			var portBox = E('div', { 
				'class': 'ifacebox', 
				'style': 'margin:.25em;min-width:70px;max-width:100px; user-select: none;' 
			}, [
				labelDiv,
				descriptionDiv,
				E('div', { 
					'class': 'ifacebox-body port-speed-body',
					'style': 'overflow: hidden; text-overflow: ellipsis; white-space: nowrap;'
				}, [
					E('img', { 'src': L.resource('icons/port_%s.svg').format(carrier ? 'up' : 'down') }),
					E('br'),
					E('span', {
						'class': 'port-speed-text',
						'style': 'display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;',
						'title': carrier ? 
							(speed > 0 && duplex ? _('Speed: %d Mibit/s, Duplex: %s').format(speed, duplex) : _('Connected')) : 
							_('no link')
					}, [
						formatSpeed(carrier, speed, duplex)
					])
				]),
				E('div', { 'class': 'ifacebox-head cbi-tooltip-container', 'style': 'display:flex' }, [
					E([], pzones.map(function(zone) {
						return E('div', {
							'class': 'zonebadge',
							'style': 'cursor:help;flex:1;height:3px;opacity:' + (carrier ? 1 : 0.25) + ';' + firewall.getZoneColorStyle(zone)
						});
					})),
					E('span', { 'class': 'cbi-tooltip left' }, [ renderNetworksTooltip(pmap) ])
				]),
				E('div', { 
					'class': 'ifacebox-body port-status-body',
					'style': 'padding: 0.15em 0.5em; text-align: center; border-top: 1px solid var(--border-color-medium); border-bottom: 1px solid var(--border-color-medium); background: transparent; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;'
				}, [
					statusElement
				]),
				E('div', { 'class': 'ifacebox-body port-traffic-body' }, [
					E('div', { 'class': 'cbi-tooltip-container', 'style': 'text-align:left;font-size:80%' }, [
						'\u25b2\u202f%1024.1mB'.format(port.netdev.getTXBytes()),
						E('br'),
						'\u25bc\u202f%1024.1mB'.format(port.netdev.getRXBytes()),
						E('span', { 'class': 'cbi-tooltip' }, formatStats(port.netdev))
					]),
				])
			]);

			portBox.__port__ = port;

			makeEditable(labelDiv, descriptionDiv, statusElement, port, known_ports);
			makeDraggable(portBox, port, container, known_ports);
			
			container.appendChild(portBox);
		});

		return wrapper;
	}
});
