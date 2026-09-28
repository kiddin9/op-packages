const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('htdocs/luci-static/resources/view/tailscale/log.js', 'utf8');
const helperSource = source.split('return view.extend')[0]
	.split('\n')
	.filter(line => !line.startsWith("'require ") && !line.startsWith("'use strict'"))
	.join('\n');

const context = {
	module: { exports: {} },
	console
};

vm.runInNewContext(`${helperSource}\nmodule.exports = { formatLogLines, formatLogError };`, context);

const { formatLogLines, formatLogError } = context.module.exports;

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
}

let result = formatLogLines('');
assert(result.value === 'Log is empty.', `unexpected empty log value: ${result.value}`);
assert(result.rows === 2, `unexpected empty log rows: ${result.rows}`);

result = formatLogError(new Error('Failed to find log object: Not found'));
assert(
	result.value === 'Unable to load log data: Failed to find log object: Not found',
	`unexpected log error value: ${result.value}`
);
assert(result.rows === 2, `unexpected log error rows: ${result.rows}`);

const sample = 'Thu Jul 16 00:21:29 2026 daemon.notice tailscaled[123]: active\\n';
result = formatLogLines(sample);
assert(result.value.includes('[ Info ]'), `expected notice to map to Info: ${result.value}`);
assert(result.value.includes('active'), `expected message body: ${result.value}`);

console.log('log view tests passed');
