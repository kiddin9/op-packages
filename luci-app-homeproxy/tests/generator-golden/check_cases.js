#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const casesPath = path.join(__dirname, 'cases.json');
const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
const fixturesDir = path.join(__dirname, 'fixtures');
const requiredCases = [
  'shadowsocks-basic',
  'shadowsocks-shadowtls',
  'selector-manual-nodes',
  'selector-regex-nodes',
  'selector-references-urltest',
  'disabled-routing-node',
  'routing-cycle',
  'selector-cycle',
  'routing-rule-direct-node',
  'gfwlist-default-outbound-fallback',
  'duplicate-label',
  'reserved-tag-label',
  'unsupported-certificate-pin',
  'remove-subscription-node-references'
];

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exitCode = 1;
  }
}

function renameTagValue(value, rename) {
  if (typeof value === 'string')
    return Object.prototype.hasOwnProperty.call(rename, value) ? rename[value] : value;

  if (Array.isArray(value))
    return value.map((item) => (
      item && typeof item === 'object' && !Array.isArray(item)
        ? renameTags(item, rename)
        : renameTagValue(item, rename)
    ));

  return value;
}

function renameTags(value, rename) {
  if (Array.isArray(value))
    return value.map((item) => renameTags(item, rename));

  if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      if (['tag', 'outbound', 'outbounds', 'detour', 'default', 'final', 'download_detour'].includes(key))
        value[key] = renameTagValue(value[key], rename);
      else
        value[key] = renameTags(value[key], rename);
    }
  }

  return value;
}

assert(Array.isArray(cases), 'cases.json must contain an array');

const names = new Set();
for (const item of cases) {
  assert(item && typeof item === 'object', 'each case must be an object');
  assert(typeof item.name === 'string' && item.name.length > 0, 'case must have a name');
  assert(!names.has(item.name), `duplicate case name: ${item.name}`);
  names.add(item.name);
  assert(typeof item.description === 'string' && item.description.length > 0, `${item.name}: missing description`);
  assert(item.expects && typeof item.expects === 'object' && !Array.isArray(item.expects), `${item.name}: missing expects object`);

  if (item.generator_fixture) {
    const fixtureDir = path.join(fixturesDir, item.name);
    const caseMetaPath = path.join(fixtureDir, 'case.json');
    const configPath = path.join(fixtureDir, 'homeproxy');
    const diagnosticsPath = path.join(fixtureDir, 'expected', 'config-diagnostics.json');

    assert(fs.existsSync(configPath), `${item.name}: missing generator fixture homeproxy config`);
    assert(fs.existsSync(caseMetaPath), `${item.name}: missing generator fixture case.json`);
    assert(fs.existsSync(diagnosticsPath), `${item.name}: missing expected config diagnostics`);

    if (fs.existsSync(caseMetaPath)) {
      const meta = JSON.parse(fs.readFileSync(caseMetaPath, 'utf8'));
      assert(typeof meta.success === 'boolean', `${item.name}: case.json must define boolean success`);
      if (meta.success)
        assert(fs.existsSync(path.join(fixtureDir, 'expected', 'sing-box-c.json')), `${item.name}: missing expected sing-box-c.json`);
    }
  }
}

for (const name of requiredCases)
  assert(names.has(name), `missing required generator golden case: ${name}`);

const renameRegression = renameTags({
  outbounds: [
    { type: 'selector', tag: 'Proxy_Selector', outbounds: ['Proxy_Auto', 'direct-out'] },
    { type: 'urltest', tag: 'Proxy_Auto', outbounds: ['node-a'] }
  ],
  route: {
    final: 'Proxy_Selector',
    rules: [{ outbound: 'Proxy_Auto' }]
  }
}, {
  Proxy_Selector: '♻️ 节点选择',
  Proxy_Auto: 'Proxy_Auto 标签',
  'node-a': '节点 A'
});

assert(renameRegression.route.final === '♻️ 节点选择', 'rename_tags regression: route.final not renamed');
assert(renameRegression.outbounds[0].tag === '♻️ 节点选择', 'rename_tags regression: top-level outbound tag not renamed');
assert(renameRegression.outbounds[0].outbounds[0] === 'Proxy_Auto 标签', 'rename_tags regression: selector outbound list not renamed');
assert(renameRegression.outbounds[1].tag === 'Proxy_Auto 标签', 'rename_tags regression: nested outbound object not renamed');

if (!process.exitCode)
  console.log(`generator golden cases: ${cases.length} ok`);
