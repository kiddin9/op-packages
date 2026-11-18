const assert = require('node:assert/strict');
const { test } = require('node:test');
const vm = require('node:vm');
const path = require('node:path');
const { buildSync } = require('esbuild');
const { highlightTree, classHighlighter } = require('@lezer/highlight');

const moduleContext = { exports: {} };
vm.runInNewContext(buildSync({
    entryPoints: [path.join(__dirname, '../utils/feature/firewall/syntax.ts')],
    bundle: true, format: 'cjs', platform: 'node', write: false,
}).outputFiles[0].text, { module: moduleContext, exports: moduleContext.exports, require, console, setTimeout, clearTimeout });
const language = moduleContext.exports.firewallTemplateLanguage;

function highlights(source) {
    const tokens = [];
    highlightTree(language.parser.parse(source), classHighlighter,
        (start, end, style) => tokens.push([source.slice(start, end), style]));
    return tokens;
}

test('nft rules and ucode tags use separate syntax tokens', () => {
    const tokens = highlights('{% if (options.proxyPort): %}\nchain proxy { tcp dport {{ options.proxyPort }} accept }\n{# note #}');
    for (const keyword of ['if', 'chain', 'tcp', 'dport', 'accept']) assert.ok(tokens.some(([text, style]) => text === keyword && style === 'tok-keyword'));
    for (const delimiter of ['{%', '%}', '{{', '}}']) assert.ok(tokens.some(([text, style]) => text === delimiter && style === 'tok-meta'));
    assert.ok(tokens.some(([text, style]) => text === '{# note #}' && style === 'tok-comment'));
});

test('strings and multiline comments containing closing tags do not end the ucode block', () => {
    const source = '{% let x = "%}"; /*\n%} ignored\n*/ return true; %}\nchain next {}';
    const tokens = highlights(source);
    assert.ok(tokens.some(([text, style]) => text === '"%}"' && style === 'tok-string'));
    assert.ok(tokens.some(([text, style]) => text.includes('%} ignored') && style === 'tok-comment'));
    assert.equal(tokens.filter(([text, style]) => text === '%}' && style === 'tok-meta').length, 1);
    assert.ok(tokens.some(([text, style]) => text === 'chain' && style === 'tok-keyword'));
});

test('nft quoted strings can include expressions and resume string highlighting afterwards', () => {
    const tokens = highlights('counter comment "port {{ options.proxyPort }} here"\nct mark 0x3 return');
    assert.ok(tokens.some(([text, style]) => text === '{{' && style === 'tok-meta'));
    assert.ok(tokens.some(([text, style]) => text === ' here"' && style === 'tok-string'));
    assert.ok(tokens.some(([text, style]) => text === '0x3' && style === 'tok-number'));
    assert.ok(tokens.some(([text, style]) => text === 'return' && style === 'tok-keyword'));
});
