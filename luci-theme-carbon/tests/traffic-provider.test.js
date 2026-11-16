'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('htdocs/luci-static/resources/carbon/traffic.js', 'utf8');

function load(values, result = { columns: ['mac', 'rx_bytes', 'tx_bytes'], data: [] }) {
	const calls = [];
	const subject = vm.runInNewContext('(function() {\n' + source + '\n})()', {
		baseclass: { extend: (x) => x },
		rpc: { declare: (spec) => async (...args) => { calls.push([spec.object, spec.method, ...args]); return values; } },
		fs: { exec_direct: async (...args) => { calls.push(['exec', ...args]); if (result instanceof Error) throw result; return result; } }
	});
	return { subject, calls };
}

test('traffic adapter follows the collector cadence and only invokes the fixed read command', async () => {
	for (const [input, expected] of [['30s', 30], ['2m', 120], ['1', 5], [undefined, 30]]) {
		const f = load({ config: { '.type': 'nlbwmon', refresh_interval: input } });
		assert.equal((await f.subject.read()).interval, expected);
		await f.subject.read();
		assert.deepEqual(JSON.parse(JSON.stringify(f.calls)), [
			['uci', 'get', 'nlbwmon'],
			['exec', '/usr/sbin/nlbw', ['-c', 'json', '-g', 'mac', '-n'], 'json'],
			['exec', '/usr/sbin/nlbw', ['-c', 'json', '-g', 'mac', '-n'], 'json']
		]);
	}
});

test('missing, ambiguous or invalid collector configuration never starts a command', async () => {
	for (const config of [{}, { one: { '.type': 'nlbwmon', refresh_interval: '0' } },
		{ one: { '.type': 'nlbwmon', refresh_interval: '30;reboot' } },
		{ one: { '.type': 'nlbwmon' }, two: { '.type': 'nlbwmon' } }]) {
		const f = load(config);
		assert.equal(await f.subject.read(), null);
		assert.equal(f.calls.length, 1);
	}
});

test('unavailable collector is propagated for the dashboard to handle without changing configuration', async () => {
	const f = load({ cfg: { '.type': 'nlbwmon' } }, new Error('not running'));
	await assert.rejects(f.subject.read(), /not running/);
	assert.equal(f.calls.length, 2);
});

test('traffic permissions grant only the fixed counter read and read-only collector configuration', () => {
	const acl = JSON.parse(fs.readFileSync('root/usr/share/rpcd/acl.d/luci-theme-carbon.json'))['luci-theme-carbon'];
	assert.deepEqual(acl.read.file['/usr/sbin/nlbw -c json -g mac -n'], ['exec']);
	assert.deepEqual(Object.entries(acl.read.file).filter(([, rights]) => rights.includes('exec')).map(([name]) => name),
		['/usr/sbin/nlbw -c json -g mac -n']);
	assert.ok(acl.read.uci.includes('nlbwmon'));
	assert.deepEqual(acl.write.uci, ['luci']);
});
