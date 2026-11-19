'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('htdocs/luci-static/resources/carbon/traffic.js', 'utf8');
const empty = { columns: ['mac', 'rx_bytes', 'tx_bytes'], data: [] };
const plain = (x) => JSON.parse(JSON.stringify(x));

function load({ config = {}, nlbw = empty, nft = new Error('no table'), now = Date.now } = {}) {
	const calls = [];
	const resolve = (v) => { v = typeof v === 'function' ? v() : v; if (v instanceof Error) throw v; return v; };
	const subject = vm.runInNewContext('(function() {\n' + source + '\n})()', {
		Date: { now }, baseclass: { extend: (x) => x },
		rpc: { declare: (spec) => async (...args) => { calls.push([spec.object, spec.method, ...args]); return resolve(config); } },
		fs: { exec_direct: async (...args) => { calls.push(['exec', ...args]); return resolve(args[0] === '/usr/sbin/nft' ? nft : nlbw); } }
	});
	return { subject, calls };
}
function counter(direction, bytes, extra = {}) {
	return { counter: { family: 'inet', table: 'carbon_acct', name: 'carbon_' + direction + '_001122334455',
		bytes, packets: 100, handle: direction === 'up' ? 1 : 2, ...extra } };
}
const validNft = () => ({ nftables: [counter('up', 1234), counter('down', 343000000)] });

test('nlbwmon is preferred, follows collector cadence and never probes nft when available', async () => {
	for (const [input, expected] of [['30s', 30], ['2m', 120], ['1', 5], [undefined, 30]]) {
		const f = load({ config: { cfg: { '.type': 'nlbwmon', refresh_interval: input } }, nft: validNft() });
		const sample = await f.subject.read();
		assert.equal(sample.interval, expected);
		assert.equal(sample.source, 'nlbwmon');
		await f.subject.read();
		assert.deepEqual(plain(f.calls), [
			['uci', 'get', 'nlbwmon'],
			['exec', '/usr/sbin/nlbw', ['-c', 'json', '-g', 'mac', '-n'], 'json'],
			['exec', '/usr/sbin/nlbw', ['-c', 'json', '-g', 'mac', '-n'], 'json']
		]);
	}
});

test('missing or invalid source and absent nlbwmon never probe nft', async () => {
	for (const source of [undefined, '', 'auto', 'nlbwmon']) {
		const f = load({ nft: validNft() });
		assert.equal(await f.subject.read(source), null);
		assert.deepEqual(plain(f.calls), [['uci', 'get', 'nlbwmon']]);
	}
});

test('nlbwmon preserves mixed device and placeholder rows for the existing rate tracker', async () => {
	const rows = [['00:00:00:00:00:00', null, null], ['00:11:22:33:44:55', 100, 200]];
	const f = load({ config: { cfg: { '.type': 'nlbwmon' } }, nlbw: { ...empty, data: rows } });
	assert.deepEqual(plain((await f.subject.read()).data), rows);
});

test('nft counter read maps directions and tracks object identities per device', async () => {
	const nft = validNft();
	nft.nftables.push({ metainfo: {} }, counter('up', 999, { table: 'other' }), counter('up', 999, { name: 'unrelated' }));
	const f = load({ nft });
	const sample = await f.subject.read('nftables');
	assert.equal(sample.interval, 5);
	assert.equal(sample.source, 'nftables');
	assert.deepEqual(plain(sample.columns), ['mac', 'rx_bytes', 'tx_bytes', 'identity']);
	assert.deepEqual(plain(sample.data), [['00:11:22:33:44:55', 343000000, 1234, '[2,1]']]);
	nft.nftables.reverse();
	assert.deepEqual(plain((await f.subject.read('nftables')).data), plain(sample.data));
	nft.nftables.find((e) => e.counter?.name === 'carbon_down_001122334455').counter.handle = 9;
	const next = await f.subject.read('nftables');
	assert.equal(next.source, sample.source);
	assert.equal(next.data[0][3], '[9,1]');
	assert.deepEqual(plain(f.calls[0]), ['exec', '/usr/sbin/nft', ['-j', 'list', 'counters', 'table', 'inet', 'carbon_acct'], 'json']);
	assert.equal(f.calls.filter((c) => c[0] === 'uci').length, 0);
});

test('empty, incomplete, duplicate and invalid nft counters cannot select a source', async () => {
	for (const nft of [{}, { nftables: [] }, { nftables: [counter('up', 20)] },
		{ nftables: [counter('up', -1), counter('down', 20)] },
		{ nftables: [counter('up', Number.MAX_SAFE_INTEGER + 1), counter('down', 20)] },
		{ nftables: [counter('up', 1), counter('up', 2), counter('down', 20)] }]) {
		assert.equal(await load({ nft }).subject.read('nftables'), null);
	}
	const nft = validNft();
	nft.nftables.push(counter('up', -1, { name: 'carbon_up_001122334466' }));
	assert.equal((await load({ nft }).subject.read('nftables')).data.length, 1, 'one bad device does not hide others');
});

test('explicit nftables queries only nft even when nlbwmon is available', async () => {
	let nft = validNft();
	const f = load({ config: { cfg: { '.type': 'nlbwmon' } }, nft: () => nft });
	assert.equal((await f.subject.read('nftables')).source, 'nftables');
	nft = new Error('no table');
	await assert.rejects(f.subject.read('nftables'), /no table/);
	assert.ok(f.calls.every((c) => c[0] === 'exec' && c[1] === '/usr/sbin/nft'));
});

test('selected nlbwmon failure does not switch to nft counters', async () => {
	let nlbw = empty;
	const f = load({ config: { cfg: { '.type': 'nlbwmon' } }, nlbw: () => nlbw, nft: validNft() });
	assert.equal((await f.subject.read()).source, 'nlbwmon');
	nlbw = new Error('temporary failure');
	await assert.rejects(f.subject.read(), /temporary failure/);
	nlbw = empty;
	assert.equal((await f.subject.read()).source, 'nlbwmon');
	assert.equal(f.calls.some((c) => c[1] === '/usr/sbin/nft'), false);
});

test('traffic permissions grant only fixed counter reads and read-only collector configuration', () => {
	const acl = JSON.parse(fs.readFileSync('root/usr/share/rpcd/acl.d/luci-theme-carbon.json'))['luci-theme-carbon'];
	assert.deepEqual(acl.read.file['/usr/sbin/nlbw -c json -g mac -n'], ['exec']);
	assert.deepEqual(acl.read.file['/usr/sbin/nft -j list counters table inet carbon_acct'], ['exec']);
	assert.deepEqual(Object.entries(acl.read.file).filter(([, rights]) => rights.includes('exec')).map(([name]) => name),
		['/usr/sbin/nlbw -c json -g mac -n', '/usr/sbin/nft -j list counters table inet carbon_acct']);
	assert.ok(acl.read.uci.includes('nlbwmon'));
	assert.deepEqual(acl.write.uci, ['luci']);
});
