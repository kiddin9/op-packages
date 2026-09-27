#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * The package's JSON and UCI assets.
 *
 * Nothing validated any of these. A malformed acl.d file makes rpcd refuse the
 * whole ACL, so every RPC the app makes is denied - and the browser shows only
 * a failed request. A menu.d action pointing at a view that was renamed drops
 * the page out of the menu. Neither is visible to any other test, because the
 * form tests render the views directly and never go through the menu or the
 * ACL at all.
 *
 * Checked here:
 *   - every .json under root/ parses;
 *   - menu.d entries carry title/order/action, and a `view` action names a
 *     view file that exists;
 *   - the ACL declares the same name menu.d depends on, has read and write
 *     sections, lists only string method names, and contains no wildcard;
 *   - capabilities/homeproxy.json has all five sets, with identical contents
 *     (they describe one privilege set, not five);
 *   - etc/config/homeproxy is valid UCI: every significant line is a config,
 *     option or list statement with a balanced quoted value.
 *
 * Usage: node tests/json-assets.js <repo-root>
 */

'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || '.');

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

function walk(dir, out) {
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) walk(p, out);
		else out.push(p);
	}
	return out;
}

/* --- every JSON asset parses -------------------------------------------- */

const jsonFiles = walk(path.join(root, 'root'), []).filter((f) => f.endsWith('.json'));
check('found the JSON assets', jsonFiles.length >= 3, `${jsonFiles.length} found`);

const parsed = {};
for (const f of jsonFiles) {
	const rel = path.relative(root, f);
	try {
		parsed[rel] = JSON.parse(fs.readFileSync(f, 'utf8'));
		check(`${rel} parses`, true);
	}
	catch (e) {
		check(`${rel} parses`, false, e.message);
	}
}

/* --- menu.d ------------------------------------------------------------- */

const MENU = 'root/usr/share/luci/menu.d/luci-app-homeproxy.json';
const menu = parsed[MENU];

if (!menu) {
	check(`${MENU} is usable`, false, 'missing or unparseable');
}
else {
	const entries = Object.entries(menu);
	check('menu.d has entries', entries.length > 0, `${entries.length}`);

	for (const [key, e] of entries) {
		check(`menu '${key}' has a title`, typeof e.title === 'string' && e.title.length > 0);
		check(`menu '${key}' has a numeric order`, typeof e.order === 'number');
		check(`menu '${key}' has an action`, e.action && typeof e.action === 'object');

		if (e.action && e.action.type === 'view') {
			const view = path.join(root, 'htdocs/luci-static/resources/view', e.action.path + '.js');
			check(`menu '${key}' points at an existing view`, fs.existsSync(view),
				path.relative(root, view));
		}
	}
}

/* --- the ACL ------------------------------------------------------------ */

const ACL = 'root/usr/share/rpcd/acl.d/luci-app-homeproxy.json';
const acl = parsed[ACL];

if (!acl) {
	check(`${ACL} is usable`, false, 'missing or unparseable');
}
else {
	const names = Object.keys(acl);
	check('the ACL declares exactly one grant', names.length === 1, names.join(','));

	/* menu.d gates the page on an ACL name; if they disagree the pages vanish
	 * for a non-root user even though the ACL itself is fine. */
	const dependsAcl = menu && menu['admin/services/homeproxy']?.depends?.acl;
	if (Array.isArray(dependsAcl)) {
		for (const d of dependsAcl)
			check(`menu.d's depends.acl '${d}' exists in acl.d`, names.indexOf(d) !== -1,
				names.join(','));
	}

	for (const name of names) {
		const g = acl[name];
		check(`acl '${name}' has a description`, typeof g.description === 'string');
		check(`acl '${name}' has a read section`, g.read && typeof g.read === 'object');
		check(`acl '${name}' has a write section`, g.write && typeof g.write === 'object');

		for (const side of ['read', 'write']) {
			const ubus = g[side]?.ubus;
			if (!ubus) continue;

			for (const [obj, methods] of Object.entries(ubus)) {
				check(`acl ${side}.ubus.${obj} is an array`, Array.isArray(methods));

				if (!Array.isArray(methods)) continue;

				for (const m of methods) {
					check(`acl ${side}.ubus.${obj} lists string methods`,
						typeof m === 'string' && m.length > 0, JSON.stringify(m));
					check(`acl ${side}.ubus.${obj} has no wildcard method`, m !== '*', m);
				}

				check(`acl ${side}.ubus.${obj} has no duplicate methods`,
					new Set(methods).size === methods.length, methods.join(','));
			}
		}
	}
}

/* --- capabilities ------------------------------------------------------- */

const CAPS = 'root/etc/capabilities/homeproxy.json';
const caps = parsed[CAPS];

if (!caps) {
	check(`${CAPS} is usable`, false, 'missing or unparseable');
}
else {
	const sets = ['bounding', 'effective', 'ambient', 'permitted', 'inheritable'];
	for (const s of sets)
		check(`capabilities has '${s}'`, Array.isArray(caps[s]), typeof caps[s]);

	/* The four non-inheritable sets (bounding / effective / ambient / permitted)
	 * describe one privilege set; a capability in `bounding` but not in
	 * `effective` is silently dropped by procd, which is the kind of thing
	 * nobody notices until the service cannot bind.  `inheritable` is
	 * allowed to be empty (and indeed should be): the review H2 hardened it
	 * to `[]` because nothing the orchestrator spawns needs to inherit caps,
	 * and an empty inheritable prevents accidental propagation to children. */
	const present = sets.filter((s) => Array.isArray(caps[s]));
	if (present.length > 1) {
		const nonInheritable = present.filter((s) => s !== 'inheritable');
		if (nonInheritable.length > 1) {
			const first = JSON.stringify([...caps[nonInheritable[0]]].sort());
			for (const s of nonInheritable.slice(1))
				check(`capabilities '${s}' matches '${nonInheritable[0]}'`,
					JSON.stringify([...caps[s]].sort()) === first,
					`${JSON.stringify(caps[s])} vs ${JSON.stringify(caps[nonInheritable[0]])}`);
		}
		/* inheritable stays independent of the other four - assert only that
		 * it is well-formed (already done by the has-set check above). */
	}
}

/* --- the factory UCI config --------------------------------------------- */

const CFG = 'root/etc/config/homeproxy';
const cfgLines = fs.readFileSync(path.join(root, CFG), 'utf8').split('\n');
let cfgStatements = 0;

cfgLines.forEach((line, i) => {
	const t = line.replace(/\s+$/, '');
	if (/^\s*$/.test(t) || /^\s*#/.test(t)) return;

	cfgStatements++;

	/* config <type> [<name>] | option <key> <value> | list <key> <value> */
	const m = /^\s*(config|option|list)\s+(\S+)(?:\s+(.*))?$/.exec(t);
	if (!m) {
		check(`${CFG}:${i + 1} is a valid UCI statement`, false, JSON.stringify(t));
		return;
	}

	if (m[1] === 'config') {
		if (m[3] && !/^'[^']*'$/.test(m[3]))
			check(`${CFG}:${i + 1} section name is single-quoted`, false, m[3]);
		return;
	}

	if (!m[3] || !/^'[^']*'$/.test(m[3]))
		check(`${CFG}:${i + 1} value is single-quoted`, false, JSON.stringify(m[3]));
});

check(`${CFG} has statements`, cfgStatements > 0, `${cfgStatements}`);
check(`${CFG} declares the main section`,
	/^\s*config\s+\S+\s+'config'/m.test(cfgLines.join('\n')));

console.log(`json assets: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
