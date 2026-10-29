#!/usr/bin/env node
/* wwand.modemsid — the interface form's redirect onto the shared wwand_modem
 * section. Evaluated the same way as test-format.js: the file is a LuCI module
 * body, so it is run as a function with the globals LuCI would have given it.
 *
 * The rule under test is narrow and has been got wrong three times
 * (openwrt/packages#30185, ddimension/luci-app-wwand#7 and #11), always in the
 * same place: what remove() is allowed to do to a section it does not own.
 */

'use strict';

const fs = require('fs');
const path = require('path');

let checks = 0, failures = 0;

function eq(got, want, label) {
	checks++;
	if (got === want || JSON.stringify(got) === JSON.stringify(want))
		return;
	failures++;
	console.log(`FAIL: ${label}\n      got:  ${JSON.stringify(got)}\n      want: ${JSON.stringify(want)}`);
}

/* a uci stand-in: package -> section -> { option: value } */
function fakeUci(state) {
	return {
		state: state,
		get: function (conf, sid, opt) {
			var s = (this.state[conf] || {})[sid];
			if (s == null) return null;
			return (opt == null) ? s : (s[opt] != null ? s[opt] : null);
		},
		set: function (conf, sid, opt, val) {
			this.state[conf] = this.state[conf] || {};
			this.state[conf][sid] = this.state[conf][sid] || {};
			this.state[conf][sid][opt] = val;
		},
		unset: function (conf, sid, opt) {
			var s = (this.state[conf] || {})[sid];
			if (s) delete s[opt];
		},
		add: function (conf, type, name) {
			this.state[conf] = this.state[conf] || {};
			this.state[conf][name] = { '.type': type };
		},
	};
}

const body = fs.readFileSync(
	path.join(__dirname, '..', 'htdocs', 'luci-static', 'resources', 'wwand', 'modemsid.js'), 'utf8');

const baseclass = { extend: (o) => o };

function load(uci) {
	return new Function('baseclass', 'uci', body)(baseclass, uci);
}

/* a stand-in for a form.Flag bound to a modem option. `disabled` is what marks
   it as a checkbox — form.Flag sets enabled/disabled in its constructor. */
function flag(option) {
	return { option: option, enabled: '1', disabled: '0' };
}

function value(option) {
	return { option: option };
}

/* --- the case that was broken: unchecking a modem-level flag ---------------
 *
 * form.Flag has default == disabled (form.js:3998-4003), so unchecking always
 * reaches parse()'s remove branch (form.js:4109) rather than write(). remove()
 * used to touch only the interface section, where the option does not live, so
 * the box sprang back and LuCI reported "no changes to apply".
 */
{
	const uci = fakeUci({ network: {
		wan: { '.type': 'interface', proto: 'wwand', modem: 'modem0' },
		modem0: { '.type': 'wwand_modem', gnss: '1' },
	} });
	const m = load(uci);
	const o = m.bindModem(flag('gnss'));

	eq(o.cfgvalue('wan'), '1', 'flag: reads through to the modem section');

	o.remove('wan');
	eq(uci.get('network', 'modem0', 'gnss'), '0',
		'flag: unchecking writes the off value where the option lives');
	eq(uci.get('network', 'wan', 'gnss'), null,
		'flag: ...and leaves no copy on the interface');
}

/* --- ...and the case that must stay broken, deliberately -------------------
 *
 * Adding a SECOND interface on an existing modem: `option modem` is not set
 * when the form renders, so every widget draws from its default and every flag
 * looks unchecked. Acting on that cleared the first interface's settings
 * (openwrt/packages#30185). The render-time reading is what tells the two
 * apart, and the save-time cfgvalue call must not be able to change it.
 */
{
	const uci = fakeUci({ network: {
		wan2: { '.type': 'interface', proto: 'wwand' },
		modem0: { '.type': 'wwand_modem', gnss: '1' },
	} });
	const m = load(uci);
	const o = m.bindModem(flag('gnss'));

	o.cfgvalue('wan2');                       /* the render: no modem yet */
	uci.set('network', 'wan2', 'modem', 'modem0');   /* an earlier option writes it */
	o.cfgvalue('wan2');                       /* form.js:2148, inside save() */
	o.remove('wan2');

	eq(uci.get('network', 'modem0', 'gnss'), '1',
		'unresolved: a flag that was never shown resolved does not clear the modem');
}

/* --- a flag the form did not change writes nothing ------------------------- */
{
	const uci = fakeUci({ network: {
		wan: { '.type': 'interface', proto: 'wwand', modem: 'modem0' },
		modem0: { '.type': 'wwand_modem' },
	} });
	const m = load(uci);
	const o = m.bindModem(flag('gnss'));

	o.cfgvalue('wan');
	o.remove('wan');
	eq(uci.get('network', 'modem0', 'gnss'), null,
		'untouched: an option that was never set is not written as 0');
}

/* --- and a TEXT field keeps the blanket refusal ----------------------------
 *
 * A Value has a blank state and "the user cleared it" cannot be told from "the
 * form had nothing to show", so nothing about it changes here.
 */
{
	const uci = fakeUci({ network: {
		wan: { '.type': 'interface', proto: 'wwand', modem: 'modem0' },
		modem0: { '.type': 'wwand_modem', path: 'platform/soc/usb1' },
	} });
	const m = load(uci);
	const o = m.bindModem(value('path'));

	o.cfgvalue('wan');
	o.remove('wan');
	eq(uci.get('network', 'modem0', 'path'), 'platform/soc/usb1',
		'value: a cleared text field still never deletes on the modem section');
}

/* --- write() still redirects, and still migrates a legacy inline copy ------ */
{
	const uci = fakeUci({ network: {
		wan: { '.type': 'interface', proto: 'wwand', modem: 'modem0', gnss: '1' },
		modem0: { '.type': 'wwand_modem' },
	} });
	const m = load(uci);
	const o = m.bindModem(flag('gnss'));

	o.write('wan', '1');
	eq(uci.get('network', 'modem0', 'gnss'), '1', 'write: lands on the modem section');
	eq(uci.get('network', 'wan', 'gnss'), null, 'write: ...and clears the legacy inline copy');
}

/* --- `device` is the daemon's L3 handle and is never migrated or cleared --- */
{
	const uci = fakeUci({ network: {
		wan: { '.type': 'interface', proto: 'wwand', modem: 'modem0', device: 'wwan0_1' },
		modem0: { '.type': 'wwand_modem' },
	} });
	const m = load(uci);
	const o = m.bindModem(value('device'));

	o.write('wan', 'wwan0_1');
	eq(uci.get('network', 'wan', 'device'), 'wwan0_1',
		'device: the interface copy survives a write');
	o.remove('wan');
	eq(uci.get('network', 'wan', 'device'), 'wwan0_1',
		'device: ...and a remove');
}

console.log(`test-modemsid: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
