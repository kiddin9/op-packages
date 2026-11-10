'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend, renderLoadedPage } = require('./helpers/runtime');

const model = loadModule('device-manager.model', environment());

test('model.sortDevices sorts IPv4 addresses numerically in ascending and descending orders', () => {
	const devices = [
		{ mac: '00:00:00:00:00:03', ipv4: '192.168.1.100', hostname: 'PC-100' },
		{ mac: '00:00:00:00:00:01', ipv4: '192.168.1.2', hostname: 'PC-2' },
		{ mac: '00:00:00:00:00:04', ipv4: '', hostname: 'No-IP' },
		{ mac: '00:00:00:00:00:02', ipv4: '192.168.1.10', hostname: 'PC-10' },
		{ mac: '00:00:00:00:00:05', ipv4: '10.0.0.1', hostname: 'Router' }
	];

	// Ascending: 10.0.0.1 -> 192.168.1.2 -> 192.168.1.10 -> 192.168.1.100 -> No-IP
	const asc = model.sortDevices(devices, 'ip', 'asc');
	assert.deepEqual(asc.map(d => d.ipv4), [
		'10.0.0.1',
		'192.168.1.2',
		'192.168.1.10',
		'192.168.1.100',
		''
	]);

	// Descending: 192.168.1.100 -> 192.168.1.10 -> 192.168.1.2 -> 10.0.0.1 -> No-IP (empty remains at bottom)
	const desc = model.sortDevices(devices, 'ip', 'desc');
	assert.deepEqual(desc.map(d => d.ipv4), [
		'192.168.1.100',
		'192.168.1.10',
		'192.168.1.2',
		'10.0.0.1',
		''
	]);
});

test('model.sortDevices handles IPv6-only devices and tie-breakers', () => {
	const devices = [
		{ mac: '00:00:00:00:00:02', ipv4: '', ipv6: 'fd00::2' },
		{ mac: '00:00:00:00:00:01', ipv4: '', ipv6: 'fd00::1' },
		{ mac: '00:00:00:00:00:03', ipv4: '', ipv6: '' }
	];

	const sorted = model.sortDevices(devices, 'ip', 'asc');
	assert.equal(sorted[0].ipv6, 'fd00::1');
	assert.equal(sorted[1].ipv6, 'fd00::2');
	assert.equal(sorted[2].ipv6, '');
});

test('model.sortDevices sorts by name, MAC, group, and type', () => {
	const devices = [
		{ mac: '00:00:00:00:00:03', customName: 'Zebra', group: 'grp2', type: 'phone' },
		{ mac: '00:00:00:00:00:01', customName: 'Apple', group: 'grp1', type: 'laptop' },
		{ mac: '00:00:00:00:00:02', customName: 'Banana', group: 'grp3', type: 'tv' }
	];

	const byName = model.sortDevices(devices, 'name', 'asc');
	assert.deepEqual(byName.map(d => d.customName), ['Apple', 'Banana', 'Zebra']);

	const byMac = model.sortDevices(devices, 'mac', 'desc');
	assert.deepEqual(byMac.map(d => d.mac), ['00:00:00:00:00:03', '00:00:00:00:00:02', '00:00:00:00:00:01']);

	const byGroup = model.sortDevices(devices, 'group', 'asc', id => id);
	assert.deepEqual(byGroup.map(d => d.group), ['grp1', 'grp2', 'grp3']);

	const byType = model.sortDevices(devices, 'type', 'asc');
	assert.deepEqual(byType.map(d => d.type), ['laptop', 'phone', 'tv']);
});

test('clicking the IP column header sorts devices in the table', async () => {
	const initial = [
		{ '.type': 'device', '.name': 'dev_1', mac: '00:11:22:33:44:01', name: 'Dev-1' },
		{ '.type': 'device', '.name': 'dev_2', mac: '00:11:22:33:44:02', name: 'Dev-2' },
		{ '.type': 'device', '.name': 'dev_3', mac: '00:11:22:33:44:03', name: 'Dev-3' }
	];

	const mocks = backend(initial);
	mocks.replies['luci.device-manager.get_online_status'] = {
		ok: true,
		neighbors: [
			{ mac: '00:11:22:33:44:01', state: 'REACHABLE' },
			{ mac: '00:11:22:33:44:02', state: 'REACHABLE' },
			{ mac: '00:11:22:33:44:03', state: 'REACHABLE' }
		]
	};
	mocks.replies['luci-rpc.getHostHints'] = {
		'00:11:22:33:44:01': { name: 'host1', ipaddrs: ['192.168.1.100'] },
		'00:11:22:33:44:02': { name: 'host2', ipaddrs: ['192.168.1.5'] },
		'00:11:22:33:44:03': { name: 'host3', ipaddrs: ['192.168.1.20'] }
	};

	const env = environment(mocks);
	const page = loadModule('view.device-manager.devices', env);

	const viewNode = await renderLoadedPage(page);

	const table = viewNode.querySelector('#device_manager_table');
	const thList = table.querySelectorAll('th');
	assert.equal(thList.length, 8);
	assert.ok(thList[0].classes.has('dm-index-column'));
	const ipTh = thList.find(th => th.getAttribute('data-sort') === 'ip');
	assert.ok(ipTh);
	assert.equal(ipTh.classes.has('dm-sortable'), true);
	assert.equal(ipTh.querySelector('button').attrs.type, 'button');

	// First click: Sort by IP ascending (192.168.1.5 -> 192.168.1.20 -> 192.168.1.100)
	await ipTh.querySelector('button').click();
	assert.equal(page.sortKey, 'ip');
	assert.equal(page.sortDir, 'asc');
	assert.equal(ipTh.classes.has('sorted-asc'), true);
	assert.equal(ipTh.getAttribute('aria-sort'), 'ascending');

	let tbody = viewNode.querySelector('#device_manager_tbody');
	let rows = tbody.querySelectorAll('tr');
	assert.equal(rows.length, 3);
	assert.deepEqual(rows.map(row => row.querySelector('.dm-index-column').textContent), ['1', '2', '3']);
	// 4th td in each row is IP address
	assert.ok(rows[0].querySelectorAll('td')[3].textContent.includes('192.168.1.5'));
	assert.ok(rows[1].querySelectorAll('td')[3].textContent.includes('192.168.1.20'));
	assert.ok(rows[2].querySelectorAll('td')[3].textContent.includes('192.168.1.100'));

	// Second click: Sort by IP descending (192.168.1.100 -> 192.168.1.20 -> 192.168.1.5)
	await ipTh.querySelector('button').click();
	assert.equal(page.sortKey, 'ip');
	assert.equal(page.sortDir, 'desc');
	assert.equal(ipTh.classes.has('sorted-desc'), true);
	assert.equal(ipTh.getAttribute('aria-sort'), 'descending');

	tbody = viewNode.querySelector('#device_manager_tbody');
	rows = tbody.querySelectorAll('tr');
	assert.ok(rows[0].querySelectorAll('td')[3].textContent.includes('192.168.1.100'));
	assert.ok(rows[1].querySelectorAll('td')[3].textContent.includes('192.168.1.20'));
	assert.ok(rows[2].querySelectorAll('td')[3].textContent.includes('192.168.1.5'));
	assert.deepEqual(rows.map(row => row.querySelector('.dm-index-column').textContent), ['1', '2', '3']);

	// Click Name header: switch sorting to Name
	const nameTh = thList.find(th => th.getAttribute('data-sort') === 'name');
	assert.ok(nameTh);
	await nameTh.querySelector('button').click();
	assert.equal(page.sortKey, 'name');
	assert.equal(page.sortDir, 'asc');
	assert.equal(ipTh.classes.has('sorted-asc'), false);
	assert.equal(ipTh.classes.has('sorted-desc'), false);
	assert.equal(ipTh.getAttribute('aria-sort'), 'none');
	assert.equal(nameTh.classes.has('sorted-asc'), true);
	assert.equal(nameTh.getAttribute('aria-sort'), 'ascending');

	page.filterText = 'host2';
	page.updateView();
	rows = tbody.querySelectorAll('tr');
	assert.equal(rows.length, 1);
	assert.equal(rows[0].querySelector('.dm-index-column').textContent, '1');
	assert.ok(rows[0].querySelectorAll('td')[3].textContent.includes('192.168.1.5'));
	page.filterText = 'no matching device';
	page.updateView();
	assert.equal(tbody.querySelector('td').getAttribute('colspan'), thList.length);
});

test('status indicator renders as a small dot without text, and default tab is Online followed by All', async () => {
	const initial = [
		{ '.type': 'device', '.name': 'dev_1', mac: '00:11:22:33:44:01', name: 'Dev-Online' }
	];

	const mocks = backend(initial);
	mocks.replies['luci.device-manager.get_online_status'] = {
		ok: true,
		neighbors: [{ mac: '00:11:22:33:44:01', state: 'REACHABLE' }]
	};
	mocks.replies['luci-rpc.getHostHints'] = {
		'00:11:22:33:44:01': { name: 'host1', ipaddrs: ['192.168.1.10'] }
	};

	const env = environment(mocks);
	const page = loadModule('view.device-manager.devices', env);

	const viewNode = await renderLoadedPage(page);

	// Check tabs order: 0 is online, 1 is all
	const tabs = viewNode.querySelector('#dm-tabs-container').children;
	assert.equal(tabs[0].getAttribute('data-tab'), 'online');
	assert.equal(tabs[1].getAttribute('data-tab'), 'all');
	assert.equal(page.activeTab, 'online');
	assert.equal(tabs[0].classes.has('active'), true);

	// Check row has dot and no badge text
	const row = viewNode.querySelector('#device_manager_tbody').querySelectorAll('tr')[0];
	const dot = row.querySelector('.dm-status-dot');
	assert.ok(dot);
	assert.equal(dot.classes.has('dm-status-dot-online'), true);
	assert.equal(dot.textContent, ''); // No text displayed inside the dot!
	assert.ok(dot.attrs.title.includes('Online') || dot.attrs.title.includes('REACHABLE'));
});

test('table row display omits no-hostname subtitle, prefix from hostname subtitle, and leaves ungrouped and remark blank', async () => {
	const initial = [
		{ '.type': 'device', '.name': 'dev_1', mac: '00:11:22:33:44:01', name: 'My-Server', group: 'ungrouped', remark: '' },
		{ '.type': 'device', '.name': 'dev_2', mac: '00:11:22:33:44:02', name: '', group: 'ungrouped', remark: '' }
	];
	const mocks = backend(initial);
	mocks.replies['luci.device-manager.get_online_status'] = {
		ok: true,
		neighbors: [
			{ mac: '00:11:22:33:44:01', state: 'REACHABLE' },
			{ mac: '00:11:22:33:44:02', state: 'REACHABLE' }
		]
	};
	mocks.replies['luci-rpc.getHostHints'] = {
		'00:11:22:33:44:01': { name: 'NAS', ipaddrs: ['192.168.1.10'] },
		'00:11:22:33:44:02': { name: '', ipaddrs: ['192.168.1.11'] }
	};

	const env = environment(mocks);
	const page = loadModule('view.device-manager.devices', env);

	const viewNode = await renderLoadedPage(page);

	const rows = viewNode.querySelector('#device_manager_tbody').querySelectorAll('tr');
	assert.equal(rows.length, 2);

	// dev_1 has customName 'My-Server' and hostname 'NAS'
	const row1 = rows[0];
	const row1Tds = row1.querySelectorAll('td');
	const titleRow1 = row1Tds[2].querySelector('.dm-device-title-row');
	assert.ok(titleRow1.textContent.includes('My-Server'));
	const subtitle1 = row1Tds[2].querySelector('.dm-device-subtitle');
	assert.ok(subtitle1);
	assert.equal(subtitle1.textContent, 'NAS'); // Only NAS, no "Hostname: " or "主机名: " prefix
	assert.equal(row1Tds[5].textContent, '');
	assert.equal(row1Tds[6].textContent, '');

	// dev_2 has no customName and no hostname
	const row2 = rows[1];
	const row2Tds = row2.querySelectorAll('td');
	const subtitle2 = row2Tds[2].querySelector('.dm-device-subtitle');
	assert.equal(subtitle2, null); // No "No hostname detected" or "无检测主机名"
	assert.equal(row2Tds[5].textContent, '');
	assert.equal(row2Tds[6].textContent, '');
});

test('mask/show info button toggles MAC and IPv6 masking with asterisks and remembers preference', async () => {
	let stored = null;
	const initial = [
		{ '.type': 'device', '.name': 'dev_1', mac: '00:11:22:33:44:01', name: 'PC' }
	];
	const mocks = backend(initial);
	mocks.replies['luci.device-manager.get_online_status'] = {
		ok: true,
		neighbors: [{ mac: '00:11:22:33:44:01', state: 'REACHABLE' }]
	};
	mocks.replies['luci-rpc.getHostHints'] = {
		'00:11:22:33:44:01': { name: 'PC', ipaddrs: ['192.168.1.10'], ip6addrs: ['fe80::1234:5678:9abc:def0'] }
	};

	const env = environment(Object.assign({}, mocks, {
		window: {
			localStorage: {
				getItem: () => stored,
				setItem: (k, v) => { stored = v; }
			}
		}
	}));
	const page = loadModule('view.device-manager.devices', env);

	const viewNode = await renderLoadedPage(page);

	// By default maskInfo is false: MAC and IPv6 are unmasked
	let row = viewNode.querySelector('#device_manager_tbody').querySelectorAll('tr')[0];
	let rowTds = row.querySelectorAll('td');
	assert.ok(rowTds[3].textContent.includes('192.168.1.10')); // IPv4
	assert.ok(rowTds[3].textContent.includes('fe80::1234:5678:9abc:def0')); // IPv6 unmasked
	assert.ok(rowTds[4].textContent.includes('00:11:22:33:44:01')); // MAC unmasked

	// Click mask toggle button
	const maskBtn = viewNode.querySelector('#dm-btn-mask');
	assert.ok(maskBtn);
	await maskBtn.click();

	// After clicking, maskInfo is true
	assert.equal(page.maskInfo, true);
	assert.deepEqual(JSON.parse(stored), { tab: 'online', group: 'all', maskInfo: true });

	row = viewNode.querySelector('#device_manager_tbody').querySelectorAll('tr')[0];
	rowTds = row.querySelectorAll('td');
	// IPv4 remains completely unchanged
	assert.ok(rowTds[3].textContent.includes('192.168.1.10'));
	// IPv6 is masked with asterisks
	assert.ok(rowTds[3].textContent.includes('****::****:****:****:****'));
	assert.ok(!rowTds[3].textContent.includes('fe80'));
	// MAC is masked with asterisks
	assert.ok(rowTds[4].textContent.includes('**:**:**:**:**:**'));
	assert.ok(!rowTds[4].textContent.includes('00:11:22'));

	// Test persistence on page reload
	const pageReload = loadModule('view.device-manager.devices', env);
	const reloadedView = await renderLoadedPage(pageReload);
	assert.equal(pageReload.maskInfo, true);

	row = reloadedView.querySelector('#device_manager_tbody').querySelectorAll('tr')[0];
	rowTds = row.querySelectorAll('td');
	assert.ok(rowTds[3].textContent.includes('192.168.1.10'));
	assert.ok(rowTds[3].textContent.includes('****::****:****:****:****'));
	assert.ok(rowTds[4].textContent.includes('**:**:**:**:**:**'));
});
