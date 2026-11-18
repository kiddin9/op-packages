const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('typescript');
const diff = require('diff');
const context = vm.createContext({ exports: {}, require: name => {
    assert.equal(name, 'diff'); return diff;
} });
vm.runInContext(ts.transpileModule(fs.readFileSync(require('node:path').join(__dirname, '../utils/feature/config/diff.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, context);
const { fileDiff } = context.exports;

for (const [name, before, after] of [
    ['new file', '', 'one\ntwo'],
    ['cleared file', 'one\ntwo', ''],
    ['separate edits with unchanged context', 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven',
        'changed\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\nlast'],
    ['literal markup and whitespace', '<script>alert(1)</script>\n  keep spaces', '<img src=x onerror=alert(1)>\n keep spaces'],
]) test(`line diff reproduces ${name}`, () => {
    const result = fileDiff(before, after);
    assert.equal(result.truncated, false);
    const patch = '--- original\n+++ draft\n' + result.lines.join('\n') + '\n';
    assert.equal(diff.applyPatch(before, patch), after);
});

test('5 MiB file with one change shows its nearby context instead of the entire file', () => {
    const line = 'x'.repeat(100) + '\n', prefix = line.repeat(26000), suffix = line.repeat(26000);
    const result = fileDiff(prefix + 'before\n' + suffix, prefix + 'after\n' + suffix);
    assert.equal(result.truncated, false);
    assert.ok(result.lines.includes('-before'));
    assert.ok(result.lines.includes('+after'));
    assert.ok(result.lines.length < 15);
});

test('large replacements and long lines cannot create unbounded preview DOM', () => {
    const replacement = fileDiff('a\n'.repeat(20000), 'b\n'.repeat(20000));
    assert.equal(replacement.truncated, true);
    assert.ok(replacement.lines.length <= 500);
    const longLine = fileDiff('a'.repeat(100000), 'b'.repeat(100000));
    assert.equal(longLine.truncated, true);
    assert.ok(longLine.lines.every(line => line.length <= 2001));
    const manyLines = fileDiff('', 'new\n'.repeat(700));
    assert.equal(manyLines.truncated, true);
    assert.equal(manyLines.lines.length, 500);
});
