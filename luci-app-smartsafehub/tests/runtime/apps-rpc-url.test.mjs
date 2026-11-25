// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const rpc = readFileSync(new URL('../../root/usr/share/rpcd/ucode/smartsafehub/apps.uc', import.meta.url), 'utf8');

// The router's ucode regex engine uses POSIX ERE, not JavaScript RegExp.
// Test the literal validator expressions with POSIX grep -E, without npm or ucode.
function posixMatch(pattern, value) {
  const result = spawnSync('grep', ['-E', '-q', pattern], {
    input: `${value}\n`, encoding: 'utf8',
  });
  assert.notEqual(result.status, 2, result.stderr);
  assert.equal(result.error, undefined);
  return result.status === 0;
}

function literalAfter(marker) {
  const tail = rpc.slice(rpc.indexOf(marker) + marker.length);
  assert.ok(rpc.includes(marker), `missing URL validator branch: ${marker}`);
  const found = tail.match(/^(\/(?:\\.|[^/])*\/)/) ?? tail.match(/match\(url, (\/(?:\\.|[^/])*\/)\)/);
  assert.ok(found, `missing regex literal after: ${marker}`);
  return found[1].slice(1, -1);
}

test('Router RPC accepts precisely the uploaded PNG icon URLs without running the general homepage validator first', () => {
  const branch = rpc.indexOf('if (image)');
  const generic = rpc.indexOf('Use the POSIX space class', branch);
  assert.ok(branch >= 0 && generic > branch);
  const iconPattern = literalAfter('if (image)');
  const icon = 'https://www.smartsafehub.com/media/app-icons/5753c7ece71e407791b50a62909fcb59.png';
  assert.equal(posixMatch(iconPattern, icon), true);
  for (const unsafe of [
    icon.replace('https:', 'http:'),
    icon.replace('www.smartsafehub.com', 'cdn.example.com'),
    icon.replace('.png', '.svg'),
    `${icon}?v=1`,
    `${icon}#fragment`,
    icon.replace('5753c7ece71e407791b50a62909fcb59', 'id'),
  ]) {
    assert.equal(posixMatch(iconPattern, unsafe), false, unsafe);
  }
});

test('Router developer website URL validator uses portable POSIX ERE whitespace and blocks private hosts', () => {
  const accept = literalAfter('if (match(url, ');
  assert.match(accept, /\[:space:\]/);
  assert.doesNotMatch(accept, /\\s|\\b/);
  const deny = literalAfter('        match(url, ');
  for (const url of ['https://github.com/Junatum/arcdrop', 'https://developer.example.org/apps/project']) {
    assert.equal(posixMatch(accept, url), true, url);
    assert.equal(posixMatch(deny, url), false, url);
  }
  for (const url of ['https://bad.local/about', 'https://bad.internal/docs', 'https://bad.localhost/']) {
    assert.equal(posixMatch(deny, url), true, url);
  }
  for (const url of ['http://github.com/Junatum/arcdrop', 'https://user@github.com/project',
    'https://github.com/hello world', 'https://github.com/a#fragment']) {
    assert.equal(posixMatch(accept, url), false, url);
  }
});
