const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('typescript');

const context = vm.createContext({ exports: {}, require: () => ({ Backend: {} }) });
const source = fs.readFileSync(path.join(__dirname, '../utils/feature/log/panel.ts'), 'utf8');
vm.runInContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
} }).outputText, context);
const filter = context.exports.filterLogEntries;

test('log filtering keeps complete multiline entries and matches header severity', () => {
    const content = '[2026-10-29 22:00:00]   INFO    WARN appears in a message\n' +
        '[2026-10-29 22:00:01]   WARN    Hook diagnostics\n' +
        '                               service missing\n' +
        '                               ERROR is just part of this warning\n' +
        '[2026-10-29 22:00:02]   ERROR   different entry\n' +
        '                               continuation of error';
    assert.equal(filter(content, 'WARN'), '[2026-10-29 22:00:01]   WARN    Hook diagnostics\n' +
        '                               service missing\n' +
        '                               ERROR is just part of this warning');
    assert.equal(filter(content, 'ERROR'), '[2026-10-29 22:00:02]   ERROR   different entry\n' +
        '                               continuation of error');
    assert.equal(filter(content, ''), content);
});

test('log filtering recognizes colored sing-box, Xray and unknown timestamped entries', () => {
    const warning = '\x1b[33m+0800 2026-10-29 22:00:00 WARN\x1b[0m [123] warning';
    const error = '2026/10/29 22:00:01.123456 [Error] transport failed';
    const content = [warning, 'warning detail', error, 'error detail',
        '2026/10/29 22:00:02 [Trace] unrelated', 'trace detail'].join('\n');
    assert.equal(filter(content, 'WARNING'), warning + '\nwarning detail');
    assert.equal(filter(content, 'ERROR'), error + '\nerror detail');
    assert.equal(filter(content, 'INFO'), '');
});
