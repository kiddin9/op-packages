'use strict';
/*
 * Theme settings backend (root/usr/libexec/rpcd/luci.carbon_update): custom
 * logo. The real shell functions run with a minimal jshn stand-in and
 * temporary paths.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const SCRIPT = fs.readFileSync(path.join(__dirname, '..', 'root/usr/libexec/rpcd/luci.carbon_update'), 'utf8');

const JSHN = path.join(__dirname, 'shell-stubs', 'jshn.sh');

function backend() {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-logo-'));
	const body = SCRIPT
		.replace('. /usr/share/libubox/jshn.sh', `. "${JSHN}"`)
		.replace(/\ncase "\$1" in\n\tlist\)[\s\S]*$/, '\n');
	assert.notEqual(body, SCRIPT, 'dispatch block stripped');
	const lib = path.join(dir, 'backend.sh');
	fs.writeFileSync(lib, body + `\nlogo_dir="${dir}/www/custom"\nlogo_upload="${dir}/upload"\n`);
	const call = (action) => JSON.parse(execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; input='{"action":"${action}"}'; logo`], { encoding: 'utf8' }));
	const upload = (data) => fs.writeFileSync(path.join(dir, 'upload'), data);
	const files = () => fs.existsSync(path.join(dir, 'www/custom')) ? fs.readdirSync(path.join(dir, 'www/custom')).sort() : [];
	return { dir, call, upload, files, uploaded: () => fs.existsSync(path.join(dir, 'upload')) };
}

const PNG = Buffer.concat([Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex'), Buffer.alloc(64)]);
const JPEG = Buffer.concat([Buffer.from('ffd8ffe000104a464946', 'hex'), Buffer.alloc(64)]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.from('24000000', 'hex'), Buffer.from('WEBPVP8 '), Buffer.alloc(32)]);
const SVG = '<?xml version="1.0"?>\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n' +
	'<SVG xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="16" fill="#4F5BEA"/>' +
	'<text font-family="Montserrat" x="8" y="40">Carbon one</text></SVG>';

test('a PNG upload becomes the logo; a later JPEG replaces it', () => {
	const b = backend();
	b.upload(PNG);
	const r = b.call('set');
	assert.match(r.logo, /^\/luci-static\/carbon\/custom\/logo\.png(\?v=\d+)?$/);
	assert.deepEqual(b.files(), ['logo.png']);
	assert.equal(b.uploaded(), false, 'upload is consumed');
	b.upload(JPEG);
	assert.match(b.call('set').logo, /logo\.jpg/);
	assert.deepEqual(b.files(), ['logo.jpg']);
	assert.equal(fs.statSync(path.join(b.dir, 'www/custom/logo.jpg')).mode & 0o777, 0o644);
	b.upload(WEBP);
	assert.match(b.call('set').logo, /logo\.webp/);
});

test('the image type comes from the content, never the file name', () => {
	const b = backend();
	b.upload('GIF89a' + '\0'.repeat(40));
	assert.match(b.call('set').logo, /logo\.gif/);
	b.upload('<html><body>not an image</body></html>');
	assert.deepEqual(b.call('set'), { error: 'logo_type' });
	assert.deepEqual(b.files(), ['logo.gif'], 'a rejected upload keeps the current logo');
	assert.equal(b.uploaded(), false);
});

test('size limits: empty and over 256 KB are rejected', () => {
	const b = backend();
	b.upload('');
	assert.deepEqual(b.call('set'), { error: 'logo_size' });
	b.upload(Buffer.concat([PNG, Buffer.alloc(262144)]));
	assert.deepEqual(b.call('set'), { error: 'logo_size' });
	assert.deepEqual(b.call('set'), { error: 'logo_missing' }, 'nothing left to apply');
});

test('plain SVG logos are accepted, including DOCTYPE and raster data: images', () => {
	const b = backend();
	b.upload(SVG);
	assert.match(b.call('set').logo, /logo\.svg/);
	b.upload(fs.readFileSync('htdocs/luci-static/carbon/logo.svg'));
	assert.match(b.call('set').logo, /logo\.svg/);
	b.upload('<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,iVBORw0KGgo="/></svg>');
	assert.match(b.call('set').logo, /logo\.svg/);
});

test('SVG that could run script on the LuCI origin is rejected', () => {
	const unsafe = [
		'<svg><script>alert(1)</script></svg>',
		'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>',
		'<svg>\n<rect\n\tONCLICK = "x()"/></svg>',
		'<svg><foreignObject><iframe src="x"/></foreignObject></svg>',
		'<svg><a href="javascript:alert(1)"><rect/></a></svg>',
		'<svg><a xlink:href="https://example.com"><rect/></a></svg>',
		'<svg><set attributeName="href" to="x"/></svg>',
		'<svg><animate attributeName="href" values="x"/></svg>',
		'<svg><image href="&#106;avascript:x"/></svg>',
		'<!DOCTYPE svg [<!ENTITY x "y">]><svg>&x;</svg>',
		'<svg><use href="data:image/svg+xml;base64,PHN2Zz4="/></svg>',
		'<svg><embed src="x"/></svg>'
	];
	const b = backend();
	unsafe.forEach((svg) => {
		b.upload(svg);
		assert.deepEqual(b.call('set'), { error: 'logo_unsafe' }, svg);
	});
	assert.deepEqual(b.files(), []);
});

test('reset restores the default logo and removes the directory', () => {
	const b = backend();
	b.upload(PNG);
	b.call('set');
	assert.deepEqual(b.call('reset'), { logo: '' });
	assert.equal(fs.existsSync(path.join(b.dir, 'www/custom')), false);
	assert.deepEqual(b.call('reset'), { logo: '' }, 'idempotent');
	assert.deepEqual(b.call('bogus'), { error: 'invalid' });
});

test('a symlinked upload is refused', () => {
	const b = backend();
	fs.writeFileSync(path.join(b.dir, 'secret'), PNG);
	fs.symlinkSync(path.join(b.dir, 'secret'), path.join(b.dir, 'upload'));
	assert.deepEqual(b.call('set'), { error: 'logo_missing' });
	assert.deepEqual(b.files(), []);
});

function dashboardBackend() {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-dash-'));
	const uciDir = path.join(dir, 'uci');
	fs.mkdirSync(uciDir);
	const body = SCRIPT
		.replace('. /usr/share/libubox/jshn.sh', `. "${JSHN}"`)
		.replace(/\ncase "\$1" in\n\tlist\)[\s\S]*$/, '\n');
	const lib = path.join(dir, 'backend.sh');
	const uciStub = `
uci_dir="${uciDir}"
carbon_config="${dir}/carbon.cfg"
uci() {
	[ "$1" = -q ] && shift
	case "$1" in
		get)
			[ -f "$uci_dir/$2" ] || return 1
			cat "$uci_dir/$2"
			;;
		set)
			k=\${2%%=*}; v=\${2#*=}
			printf '%s\\n' "$v" > "$uci_dir/$k"
			;;
		delete)
			rm -f "$uci_dir/$2" "$uci_dir/$2."*
			;;
		commit)
			printf '%s\\n' "$2" >> "$uci_dir/.commits"
			;;
	esac
}
`;
	fs.writeFileSync(lib, uciStub + body.replaceAll('/etc/config/carbon', '${carbon_config}') + '\n');
	const call = (payload) => JSON.parse(execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; input='${JSON.stringify(payload).replace(/'/g, "'\\''")}'; set_dashboard`], { encoding: 'utf8' }));
	const readUci = (k) => fs.existsSync(path.join(uciDir, k)) ? fs.readFileSync(path.join(uciDir, k), 'utf8').trim() : null;
	const isCustom = () => execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; dashboard_custom`], { encoding: 'utf8' }).trim();
	return { dir, call, readUci, isCustom };
}

test('set_dashboard saves validated UCI options, supports empty sections via none, and resets cleanly', () => {
	const b = dashboardBackend();
	assert.equal(b.isCustom(), '0');

	const res = b.call({
		action: 'set',
		hero: '1',
		sections: 'tiles monitor details',
		monitor: 'traffic:auto traffic:br-lan resources',
		tiles: 'wifi temp',
		details: 'none'
	});
	assert.deepEqual(res, {
		dashboard_custom: true,
		hero: '1',
		sections: 'tiles monitor details',
		monitor: 'traffic:auto traffic:br-lan resources',
		tiles: 'wifi temp',
		details: 'none'
	});
	assert.equal(b.isCustom(), '1');
	assert.equal(b.readUci('carbon.dashboard'), 'dashboard');
	assert.equal(b.readUci('carbon.dashboard.hero'), '1');
	assert.equal(b.readUci('carbon.dashboard.sections'), 'tiles monitor details');
	assert.equal(b.readUci('carbon.dashboard.monitor'), 'traffic:auto traffic:br-lan resources');
	assert.equal(b.readUci('carbon.dashboard.tiles'), 'wifi temp');
	assert.equal(b.readUci('carbon.dashboard.details'), 'none');

	const reset = b.call({ action: 'reset' });
	assert.deepEqual(reset, { dashboard_custom: false });
	assert.equal(b.isCustom(), '0');
	assert.equal(b.readUci('carbon.dashboard'), null);
	assert.equal(b.readUci('carbon.dashboard.hero'), null);
});

test('set_dashboard rejects invalid tokens, duplicates, >4 traffic panels, unsafe names and all-empty layouts', () => {
	const b = dashboardBackend();
	const base = { action: 'set', hero: '1', sections: 'monitor tiles details', monitor: 'traffic:auto resources', tiles: 'devices', details: 'clients' };
	const invalid = [
		{ ...base, hero: '2' },
		{ ...base, sections: 'monitor tiles' },
		{ ...base, sections: 'monitor monitor details' },
		{ ...base, sections: 'monitor tiles bogus' },
		{ ...base, monitor: 'traffic:auto traffic:br-lan traffic:wan traffic:wg0 traffic:eth0' },
		{ ...base, monitor: 'resources resources' },
		{ ...base, monitor: 'traffic:bad/dev' },
		{ ...base, monitor: 'traffic:;rm' },
		{ ...base, monitor: 'traffic:auto\nrm' },
		{ ...base, monitor: 'traffic:' },
		{ ...base, monitor: 'unknown' },
		{ ...base, tiles: 'devices devices' },
		{ ...base, tiles: 'devices bogus' },
		{ ...base, details: 'clients clients' },
		{ ...base, details: 'clients bogus' },
		{ action: 'set', hero: '0', sections: 'monitor tiles details', monitor: 'none', tiles: 'none', details: 'none' },
		{ action: 'bogus' }
	];
	for (const payload of invalid) {
		assert.deepEqual(b.call(payload), { error: 'invalid_dashboard' }, JSON.stringify(payload));
	}
	assert.equal(b.isCustom(), '0');
});

test('settings ACL grants write access to set_dashboard only under luci.carbon_update', () => {
	const acl = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'root/usr/share/rpcd/acl.d/luci-theme-carbon-update.json'), 'utf8'))['luci-theme-carbon-update'];
	assert.ok(acl.write.ubus['luci.carbon_update'].includes('set_dashboard'));
	assert.equal(acl.read.ubus['luci.carbon_update'].includes('set_dashboard'), false);
});

function simpleMenuBackend() {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-menu-'));
	const uciDir = path.join(dir, 'uci');
	fs.mkdirSync(uciDir);
	const body = SCRIPT
		.replace('. /usr/share/libubox/jshn.sh', `. "${JSHN}"`)
		.replace(/\ncase "\$1" in\n\tlist\)[\s\S]*$/, '\n');
	const lib = path.join(dir, 'backend.sh');
	const uciStub = `
uci_dir="${uciDir}"
carbon_config="${dir}/carbon.cfg"
uci() {
	[ "$1" = -q ] && shift
	case "$1" in
		get)
			[ -f "$uci_dir/$2" ] || return 1
			cat "$uci_dir/$2"
			;;
		set)
			k=\${2%%=*}; v=\${2#*=}
			printf '%s\\n' "$v" > "$uci_dir/$k"
			;;
		delete)
			rm -f "$uci_dir/$2" "$uci_dir/$2."*
			;;
		commit)
			printf '%s\\n' "$2" >> "$uci_dir/.commits"
			;;
	esac
}
`;
	fs.writeFileSync(lib, uciStub + body.replaceAll('/etc/config/carbon', '${carbon_config}') + '\n');
	const call = (payload) => JSON.parse(execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; input='${JSON.stringify(payload).replace(/'/g, "'\\''")}'; set_simple_menu`], { encoding: 'utf8' }));
	const readUci = (k) => fs.existsSync(path.join(uciDir, k)) ? fs.readFileSync(path.join(uciDir, k), 'utf8').trim() : null;
	const isCustom = () => execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; simple_menu_custom`], { encoding: 'utf8' }).trim();
	return { dir, call, readUci, isCustom };
}

test('set_simple_menu saves validated UCI options, supports an empty group via none, and resets cleanly', () => {
	const b = simpleMenuBackend();
	assert.equal(b.isCustom(), '0');

	const res = b.call({
		action: 'set',
		common: 'status/overview network/network services/openclash network/dhcp',
		system: 'system/package-manager system/carbon-update system/reboot'
	});
	assert.deepEqual(res, {
		simple_menu_custom: true,
		common: 'status/overview network/network services/openclash network/dhcp',
		system: 'system/package-manager system/carbon-update system/reboot'
	});
	assert.equal(b.isCustom(), '1');
	assert.equal(b.readUci('carbon.simple_menu'), 'simple_menu');
	assert.equal(b.readUci('carbon.simple_menu.common'), 'status/overview network/network services/openclash network/dhcp');
	assert.equal(b.readUci('carbon.simple_menu.system'), 'system/package-manager system/carbon-update system/reboot');

	const singleGroup = b.call({
		action: 'set',
		common: 'status/overview docker services/v2rayA services/luci.app_1',
		system: 'none'
	});
	assert.deepEqual(singleGroup, {
		simple_menu_custom: true,
		common: 'status/overview docker services/v2rayA services/luci.app_1',
		system: 'none'
	});

	const reset = b.call({ action: 'reset' });
	assert.deepEqual(reset, { simple_menu_custom: false });
	assert.equal(b.isCustom(), '0');
	assert.equal(b.readUci('carbon.simple_menu'), null);
	assert.equal(b.readUci('carbon.simple_menu.common'), null);
});

test('set_simple_menu rejects invalid paths, logout, duplicates, >32 items, oversized payloads and all-empty menus', () => {
	const b = simpleMenuBackend();
	const tooMany = Array.from({ length: 33 }, (_, i) => `services/p${i}`).join(' ');
	const tooLong = Array.from({ length: 20 }, (_, i) => `services/${'a'.repeat(55)}${i}`).join(' ');
	const invalid = [
		{ action: 'set', common: 'none', system: 'none' },
		{ action: 'set', common: '', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview', system: '' },
		{ action: 'set', common: 'logout', system: 'system/reboot' },
		{ action: 'set', common: 'logout/sub', system: 'system/reboot' },
		{ action: 'set', common: '../etc', system: 'system/reboot' },
		{ action: 'set', common: 'status/..', system: 'system/reboot' },
		{ action: 'set', common: '.hidden/page', system: 'system/reboot' },
		{ action: 'set', common: 'status/.hidden', system: 'system/reboot' },
		{ action: 'set', common: 'a/b/c', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview none', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview;rm', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview\nrm', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview status/overview', system: 'system/reboot' },
		{ action: 'set', common: 'status/overview', system: 'status/overview' },
		{ action: 'set', common: tooMany, system: 'none' },
		{ action: 'set', common: tooLong, system: 'none' },
		{ action: 'bogus', common: 'status/overview', system: 'none' }
	];
	for (const payload of invalid) {
		assert.deepEqual(b.call(payload), { error: 'invalid_simple_menu' }, JSON.stringify(payload));
	}
	assert.equal(b.isCustom(), '0');
});

test('settings ACL grants write access to set_simple_menu only under luci.carbon_update', () => {
	const acl = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'root/usr/share/rpcd/acl.d/luci-theme-carbon-update.json'), 'utf8'))['luci-theme-carbon-update'];
	assert.ok(acl.write.ubus['luci.carbon_update'].includes('set_simple_menu'));
	assert.equal(acl.read.ubus['luci.carbon_update'].includes('set_simple_menu'), false);
});

function updaterEnv({ withSetsid = false, manager = 'opkg', installedVersion = '1.1.8-1' } = {}) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-updater-'));
	const bin = path.join(dir, 'bin');
	fs.mkdirSync(bin);
	const log = path.join(dir, 'calls.log');
	fs.writeFileSync(log, '');
	const makeStub = (name, content) => {
		const p = path.join(bin, name);
		fs.writeFileSync(p, content);
		fs.chmodSync(p, 0o755);
	};
	// Copy or link standard POSIX utilities needed by the script, explicitly controlling setsid/flock/curl/sha256sum.
	for (const cmd of ['sh', 'awk', 'sed', 'grep', 'cat', 'cp', 'mv', 'rm', 'mkdir', 'chmod', 'ls', 'head', 'tail', 'tr', 'wc', 'df', 'date', 'mktemp', 'sort']) {
		for (const sysdir of ['/bin', '/usr/bin']) {
			const src = path.join(sysdir, cmd);
			if (fs.existsSync(src)) { fs.symlinkSync(src, path.join(bin, cmd)); break; }
		}
	}
	makeStub('curl', '#!/bin/sh\necho "curl $*" >> "' + log + '"\nexit 0\n');
	makeStub('sha256sum', '#!/bin/sh\necho "0000  $1"\n');
	makeStub('flock', '#!/bin/sh\necho "flock $*" >> "' + log + '"\nexit 0\n');
	if (withSetsid) {
		makeStub('setsid', '#!/bin/sh\necho "setsid $*" >> "' + log + '"\nexec "$@"\n');
	}
	if (manager === 'opkg') {
		// Mirror real OpenWrt 23.05 opkg compare-versions: without normalizing -N to -rN,
		// opkg treats -r1 as greater than -1 and -2 because letters sort after digits.
		makeStub('opkg', `#!/bin/sh
echo "opkg $*" >> "${log}"
case "$1" in
	status)
		printf 'Package: luci-theme-carbon\\nVersion: %s\\nStatus: install user installed\\n' "${installedVersion}"
		;;
	compare-versions)
		a=$2; op=$3; b=$4
		[ "$op" = ">>" ] || exit 2
		if [ "$a" = "$b" ]; then exit 1; fi
		# Emulate Debian/opkg revision ordering: non-digit 'r' > digit when upstream matches.
		av=\${a%-*}; ar=\${a#*-}; bv=\${b%-*}; br=\${b#*-}
		if [ "$av" != "$bv" ]; then
			[ "$(printf '%s\\n%s\\n' "$av" "$bv" | sort -V | tail -n 1)" = "$av" ]
			exit $?
		fi
		case "$ar:$br" in
			r*:r*) [ "\${ar#r}" -gt "\${br#r}" ] ;;
			r*:*) exit 0 ;;
			*:r*) exit 1 ;;
			*:*) [ "$ar" -gt "$br" ] ;;
		esac
		;;
esac
`);
	}
	const body = SCRIPT
		.replace('. /usr/share/libubox/jshn.sh', `. "${JSHN}"`)
		.replace(/\ncase "\$1" in\n\tlist\)[\s\S]*$/, '\n');
	const lib = path.join(dir, 'backend.sh');
	fs.writeFileSync(lib, body + `\nstate_dir="${dir}/state"\nmkdir -p "$state_dir"\n`);
	const run = (snippet) => execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; ${snippet}`], {
		encoding: 'utf8',
		stdio: ['ignore', 'pipe', 'pipe'],
		env: { PATH: bin }
	});
	return { dir, bin, log, run, readLog: () => fs.readFileSync(log, 'utf8') };
}

test('tools_ready and start_job work without setsid (OpenWrt 23.05) while preserving setsid when present', () => {
	const noSetsid = updaterEnv({ withSetsid: false, installedVersion: '1.1.8-r1' });
	const withSetsid = updaterEnv({ withSetsid: true, installedVersion: '1.1.8-r1' });
	try {
		assert.equal(noSetsid.run('manager=opkg; tools_ready && echo READY || echo MISSING').trim(), 'READY');

		const patchScript = (env) => {
			const scriptCopy = path.join(env.dir, 'rpc.sh');
			fs.writeFileSync(scriptCopy, SCRIPT
				.replace('. /usr/share/libubox/jshn.sh', `. "${JSHN}"`)
				.replace('state_dir=/tmp/carbon-update', `state_dir="${env.dir}/state"`)
				.replace('[ "$(ls -nd "$state_dir" | awk \'{print $3}\')" = 0 ] && ', '')
				.replace('check_release() {', 'check_release() { echo "RAN_CHECK" > "' + env.dir + '/worker.ran"; return 0; }\norig_check_release() {'));
			fs.chmodSync(scriptCopy, 0o755);
			return scriptCopy;
		};

		const waitWorkerDone = (env) => {
			const marker = path.join(env.dir, 'worker.ran');
			const stateDir = path.join(env.dir, 'state');
			const statusFile = path.join(stateDir, 'status.json');
			for (let i = 0; i < 60; i++) {
				const done = fs.existsSync(marker) &&
					fs.existsSync(statusFile) &&
					fs.readFileSync(statusFile, 'utf8').includes('"state":"idle"') &&
					!fs.readdirSync(stateDir).some(name => name.startsWith('job.'));
				if (done) return true;
				Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
			}
			return false;
		};

		const rpcNoSetsid = patchScript(noSetsid);
		const outNoSetsid = execFileSync(rpcNoSetsid, ['call', 'check'], { input: '{}', encoding: 'utf8', env: { PATH: noSetsid.bin } });
		assert.deepEqual(JSON.parse(outNoSetsid), { started: true });
		assert.equal(waitWorkerDone(noSetsid), true, 'detached worker should complete and clean up without setsid');

		const rpcWithSetsid = patchScript(withSetsid);
		const outWithSetsid = execFileSync(rpcWithSetsid, ['call', 'check'], { input: '{}', encoding: 'utf8', env: { PATH: withSetsid.bin } });
		assert.deepEqual(JSON.parse(outWithSetsid), { started: true });
		assert.equal(waitWorkerDone(withSetsid), true, 'worker with setsid should complete and clean up');
		assert.match(withSetsid.readLog(), /setsid /, 'existing 24.10/25.12 path still uses setsid when available');
	} finally {
		fs.rmSync(noSetsid.dir, { recursive: true, force: true });
		fs.rmSync(withSetsid.dir, { recursive: true, force: true });
	}
});

test('opkg recognizes OpenWrt 23.05 SDK versions without -r prefix and compares revisions accurately', () => {
	const env = updaterEnv({ installedVersion: '1.1.8-1' });
	try {
		assert.equal(env.run('installed; printf "%s %s %s" "$manager" "$managed" "$current"'), 'opkg 1 1.1.8-1');

		const cases = [
			['1.1.8-r1', '1.1.8-1', false],
			['1.1.8-r1', '1.1.8-2', false],
			['1.1.7-r1', '1.1.8-1', false],
			['1.1.8-r2', '1.1.8-1', true],
			['1.1.9-r1', '1.1.8-1', true],
			['1.1.9-r1', '1.1.8-r1', true],
			['1.1.8-r1', '1.1.8-r1', false],
			['1.1.8-1', '1.1.7-1', false], // release target must still strictly use -rN
		];
		for (const [target, current, expected] of cases) {
			const res = env.run(`manager=opkg; target='${target}'; current='${current}'; newer && echo YES || echo NO`).trim();
			assert.equal(res, expected ? 'YES' : 'NO', `target=${target} current=${current}`);
		}

		// APK remains strict: versions without -r are never accepted as managed APK installs
		assert.equal(env.run(`manager=apk; valid_installed_version '1.1.8-1' && echo YES || echo NO`).trim(), 'NO');
		assert.equal(env.run(`manager=apk; valid_installed_version '1.1.8-r1' && echo YES || echo NO`).trim(), 'YES');
	} finally {
		fs.rmSync(env.dir, { recursive: true, force: true });
	}
});

test('settings view treats 23.05 SDK 1.1.8-1 as matching latest 1.1.8-r1', () => {
	const nodes = [];
	function E(tag, attrs = {}, children) {
		const node = { tag, attrs, children, hidden: false, disabled: false, textContent: '', innerHTML: '' };
		nodes.push(node);
		return node;
	}
	const renderState = (data) => {
		nodes.length = 0;
		const subject = new Function('view', 'rpc', 'poll', 'ui', 'markdown', 'document', 'E', 'L', 'window', '_',
			fs.readFileSync(path.join(__dirname, '..', 'htdocs/luci-static/resources/view/system/carbon-update.js'), 'utf8'))(
			{ extend: v => v }, { declare: () => async () => data }, { add() {} }, {}, { render: s => s },
			{ documentElement: { lang: 'en' }, querySelectorAll: () => [] }, E, { hasViewPermission: () => true }, {}, s => s);
		subject.render(data);
		const statusP = nodes.find(n => n.tag === 'p' && n.attrs && n.attrs.role === 'status');
		return statusP && statusP.textContent;
	};
	assert.equal(renderState({ current: '1.1.8-1', latest: '1.1.8-r1', manager: 'opkg', state: 'idle', can_upgrade: false }),
		'You are using the latest version.');
	assert.equal(renderState({ current: '1.1.8-r1', latest: '1.1.8-r1', manager: 'opkg', state: 'idle', can_upgrade: false }),
		'You are using the latest version.');
	assert.equal(renderState({ current: '1.1.7-1', latest: '1.1.8-r1', manager: 'opkg', state: 'idle', can_upgrade: true }),
		'A new version is available.');
});

function releaseFallbackEnv({ manager = 'opkg', mirror = '' } = {}) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-fallback-'));
	const bin = path.join(dir, 'bin');
	const stateDir = path.join(dir, 'state');
	const jobDir = path.join(stateDir, 'job.test');
	const fixtures = path.join(dir, 'fixtures');
	fs.mkdirSync(bin, { recursive: true });
	fs.mkdirSync(jobDir, { recursive: true });
	fs.mkdirSync(fixtures, { recursive: true });

	const makeStub = (name, content) => {
		const p = path.join(bin, name);
		fs.writeFileSync(p, content);
		fs.chmodSync(p, 0o755);
	};
	for (const cmd of ['sh', 'awk', 'sed', 'grep', 'cat', 'cp', 'mv', 'rm', 'mkdir', 'chmod', 'ls', 'head', 'tail', 'tr', 'df', 'date', 'mktemp', 'sort']) {
		for (const sysdir of ['/bin', '/usr/bin']) {
			const src = path.join(sysdir, cmd);
			if (fs.existsSync(src)) { fs.symlinkSync(src, path.join(bin, cmd)); break; }
		}
	}
	// Normalize wc -c output (macOS BSD wc pads with leading spaces; OpenWrt BusyBox/GNU wc does not).
	const sysWc = ['/usr/bin/wc', '/bin/wc'].find((p) => fs.existsSync(p));
	makeStub('wc', `#!/bin/sh\n"${sysWc}" "$@" | awk '{print $1}'\n`);
	makeStub('sha256sum', `#!/bin/sh\n"${process.execPath}" -e 'const fs=require("fs"),c=require("crypto");const p=process.argv[1];console.log(c.createHash("sha256").update(fs.readFileSync(p)).digest("hex")+"  "+p);' "$1"\n`);
	makeStub('flock', '#!/bin/sh\nexit 0\n');
	makeStub('uci', `#!/bin/sh
[ "$1" = -q ] && shift
if [ "$1" = get ] && [ "$2" = carbon.update.mirror ]; then
	[ -n "${mirror}" ] && printf '%s\\n' "${mirror}" || exit 1
	exit 0
fi
exit 0
`);

	const pkgName = manager === 'apk' ? 'luci-theme-carbon-1.2.0-r1.apk' : 'luci-theme-carbon_1.2.0-r1_all.ipk';
	const pkgBytes = Buffer.from(`fake-${manager}-package-bytes-1.2.0-r1`);
	const pkgHash = crypto.createHash('sha256').update(pkgBytes).digest('hex');
	fs.writeFileSync(path.join(fixtures, 'pkg.bin'), pkgBytes);
	fs.writeFileSync(path.join(fixtures, 'release.json'), JSON.stringify({
		tag_name: 'v1.2.0',
		draft: false,
		prerelease: false,
		body: 'Release 1.2.0',
		assets: [
			{ name: 'luci-theme-carbon-1.2.0-r1.apk', size: pkgBytes.length, digest: 'sha256:' + pkgHash },
			{ name: 'luci-theme-carbon_1.2.0-r1_all.ipk', size: pkgBytes.length, digest: 'sha256:' + pkgHash }
		]
	}));

	const urlLog = path.join(dir, 'urls.log');
	fs.writeFileSync(urlLog, '');
	makeStub('curl', `#!/bin/sh
out=''; url=''
while [ "$#" -gt 0 ]; do
	case "$1" in -o) out=$2; shift ;; https://*) url=$1 ;; esac
	shift
done
printf '%s\\n' "$url" >> "${urlLog}"
case "$url" in
	https://mirror.test/https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/${pkgName})
		[ ! -f "${dir}/mirror-fail" ] || { echo 'mirror timeout' >&2; exit 28; }
		if [ -f "${dir}/mirror-corrupt" ]; then printf corrupt > "$out"; else cp "${fixtures}/pkg.bin" "$out"; fi ;;
	https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest)
		[ ! -f "${dir}/github-api-fail" ] || { echo 'HTTP 403 rate limit' >&2; exit 22; }
		if [ -f "${dir}/github-api-bad" ]; then printf '<html>blocked</html>' > "$out"
		elif [ -f "${dir}/github-api-prerelease" ]; then printf '{"tag_name":"v1.2.0","draft":false,"prerelease":true,"assets":[]}' > "$out"
		else cp "${fixtures}/release.json" "$out"; fi ;;
	https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/${pkgName})
		[ ! -f "${dir}/github-pkg-fail" ] || { echo 'github timeout' >&2; exit 28; }
		if [ -f "${dir}/github-pkg-corrupt" ]; then printf corrupt > "$out"; else cp "${fixtures}/pkg.bin" "$out"; fi ;;
	https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json)
		[ ! -f "${dir}/pages-api-fail" ] || { echo 'pages error' >&2; exit 7; }
		if [ -f "${dir}/pages-api-bad" ]; then printf 'not-json' > "$out"; else cp "${fixtures}/release.json" "$out"; fi ;;
	https://mrjoechen.github.io/luci-theme-carbon/updates/v1.2.0/${pkgName})
		[ ! -f "${dir}/pages-pkg-fail" ] || { echo 'pages pkg error' >&2; exit 7; }
		if [ -f "${dir}/pages-pkg-corrupt" ]; then printf corrupt > "$out"; else cp "${fixtures}/pkg.bin" "$out"; fi ;;
	*) echo "unexpected url: $url" >&2; exit 22 ;;
esac
`);

	// Full OpenWrt jshn.sh subset needed by parse_release / check_release / install_release.
	const jshnHelper = path.join(dir, 'jshn.js');
	fs.writeFileSync(jshnHelper, `
const fs = require('fs');
const stateFile = process.argv[2];
const op = process.argv[3];
const args = process.argv.slice(4);
const loadState = () => fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : { root: {}, stack: [] };
const saveState = (s) => fs.writeFileSync(stateFile, JSON.stringify(s));
const current = (s) => s.stack.reduce((node, k) => node == null ? undefined : node[k], s.root);
const shQuote = (v) => "'" + String(v).replace(/'/g, "'\\\\''") + "'";
if (op === 'init') {
	saveState({ root: {}, stack: [] });
} else if (op === 'add_string') {
	const s = loadState(); s.root[args[0]] = String(args[1] ?? ''); saveState(s);
} else if (op === 'add_int') {
	const s = loadState(); s.root[args[0]] = Number(args[1]); saveState(s);
} else if (op === 'add_boolean') {
	const s = loadState(); s.root[args[0]] = args[1] === '1' || args[1] === 'true'; saveState(s);
} else if (op === 'dump') {
	console.log(JSON.stringify(loadState().root));
} else if (op === 'load_file') {
	try {
		const data = JSON.parse(fs.readFileSync(args[0], 'utf8'));
		if (!data || typeof data !== 'object') process.exit(1);
		saveState({ root: data, stack: [] });
	} catch { process.exit(1); }
} else if (op === 'select') {
	const s = loadState();
	if (args[0] === '..') { s.stack.pop(); saveState(s); }
	else {
		const node = current(s);
		if (node == null || !(args[0] in node) || typeof node[args[0]] !== 'object' || node[args[0]] === null) process.exit(1);
		s.stack.push(args[0]); saveState(s);
	}
} else if (op === 'keys') {
	const node = current(loadState());
	const keys = Array.isArray(node) ? node.map((_, i) => String(i)) : Object.keys(node || {});
	console.log(args[0] + '=' + shQuote(keys.join(' ')));
} else if (op === 'vars') {
	const node = current(loadState()) || {};
	for (const k of args) {
		if (!(k in node) || node[k] === null || node[k] === undefined) continue;
		const val = typeof node[k] === 'boolean' ? (node[k] ? '1' : '0') : String(node[k]);
		console.log(k + '=' + shQuote(val));
	}
}
`);
	const jshnSh = path.join(dir, 'jshn.sh');
	fs.writeFileSync(jshnSh, `
_JSHN_STATE="${dir}/jshn.state.json"
json_init() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" init; }
json_add_string() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" add_string "$1" "$2"; }
json_add_int() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" add_int "$1" "$2"; }
json_add_boolean() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" add_boolean "$1" "$2"; }
json_dump() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" dump; }
json_load_file() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" load_file "$1"; }
json_select() { "${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" select "$1"; }
json_get_keys() { eval "$("${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" keys "$1")"; }
json_get_vars() { eval "$("${process.execPath}" "${jshnHelper}" "$_JSHN_STATE" vars "$@")"; }
`);

	const body = SCRIPT
		.replace('. /usr/share/libubox/jshn.sh', `. "${jshnSh}"`)
		.replace(/\ncase "\$1" in\n\tlist\)[\s\S]*$/, '\n');
	const lib = path.join(dir, 'backend.sh');
	fs.writeFileSync(lib, body + `\nstate_dir="${stateDir}"\njob="${jobDir}"\nmanager="${manager}"\nmanaged=1\ncurrent="1.1.8-r1"\n`);

	const run = (snippet) => execFileSync(process.env.CARBON_TEST_SH || 'sh', ['-c', `. "${lib}"; ${snippet}`], {
		encoding: 'utf8',
		stdio: ['ignore', 'pipe', 'pipe'],
		env: { PATH: bin }
	});
	const touch = (flag) => fs.writeFileSync(path.join(dir, flag), '');
	const urls = () => fs.readFileSync(urlLog, 'utf8').trim().split('\n').filter(Boolean);
	const cleanup = () => fs.rmSync(dir, { recursive: true, force: true });
	return { dir, stateDir, jobDir, pkgName, pkgBytes, pkgHash, run, touch, urls, cleanup };
}

test('check_release prefers GitHub API and falls back to GitHub Pages on rate-limit, timeout, or invalid HTTP 200 payload', () => {
	// 1. Primary path: GitHub API succeeds, Pages is not queried.
	let env = releaseFallbackEnv({ manager: 'opkg' });
	try {
		const out = env.run('check_release && echo OK');
		assert.match(out, /Checking release from github/);
		assert.doesNotMatch(out, /Checking release from pages/);
		assert.deepEqual(env.urls(), ['https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest']);
		const checked = JSON.parse(fs.readFileSync(path.join(env.stateDir, 'release.json'), 'utf8'));
		assert.equal(checked.target, '1.2.0-r1');
		assert.equal(checked.filename, 'luci-theme-carbon_1.2.0-r1_all.ipk');
	} finally { env.cleanup(); }

	// 2. GitHub API rate-limited / failed -> falls back to Pages latest.json.
	env = releaseFallbackEnv({ manager: 'apk' });
	try {
		env.touch('github-api-fail');
		const out = env.run('check_release && echo OK');
		assert.match(out, /Release check from github failed/);
		assert.match(out, /Checking release from pages/);
		assert.deepEqual(env.urls(), [
			'https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest',
			'https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json'
		]);
		const checked = JSON.parse(fs.readFileSync(path.join(env.stateDir, 'release.json'), 'utf8'));
		assert.equal(checked.target, '1.2.0-r1');
		assert.equal(checked.filename, 'luci-theme-carbon-1.2.0-r1.apk');
	} finally { env.cleanup(); }

	// 3. GitHub API returns HTTP 200 HTML/invalid metadata -> falls back to Pages latest.json.
	env = releaseFallbackEnv({ manager: 'opkg' });
	try {
		env.touch('github-api-bad');
		const out = env.run('check_release && echo OK');
		assert.match(out, /Invalid release metadata from github/);
		assert.match(out, /Checking release from pages/);
		assert.deepEqual(env.urls(), [
			'https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest',
			'https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json'
		]);
	} finally { env.cleanup(); }

	// 4. Both sources return invalid metadata -> fails with failure=metadata.
	env = releaseFallbackEnv({ manager: 'opkg' });
	try {
		env.touch('github-api-prerelease');
		env.touch('pages-api-bad');
		const out = env.run('check_release && echo OK || echo "FAIL:$failure"');
		assert.match(out, /FAIL:metadata/);
	} finally { env.cleanup(); }
});

test('install_release tries mirror -> GitHub Releases -> GitHub Pages fallback across failures and checksum mismatches', () => {
	// Helper snippet that exercises install_release download/checksum loop up to package verification.
	const installSnippet = (verifyStub) => `
		newer() { return 0; }
		installed() { manager=opkg; managed=1; current=1.2.0-r1; }
		save_preferences() { return 0; }
		restore_preferences() { return 0; }
		opkg_call() { return 0; }
		${verifyStub}
		check_release && requested=1.2.0-r1 && install_release && echo INSTALLED
	`;

	// 1. No mirror, GitHub Releases succeeds -> Pages is not requested.
	let env = releaseFallbackEnv({ manager: 'opkg' });
	try {
		const out = env.run(installSnippet(`tar() { printf 'Package: luci-theme-carbon\\nVersion: 1.2.0-r1\\n'; }`));
		assert.match(out, /Downloading from github:/);
		assert.doesNotMatch(out, /Downloading from pages:/);
		assert.match(out, /INSTALLED/);
		assert.deepEqual(env.urls(), [
			'https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest',
			'https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk'
		]);
	} finally { env.cleanup(); }

	// 2. GitHub API rate-limited + GitHub Releases timeout -> falls back to Pages for both manifest and package.
	env = releaseFallbackEnv({ manager: 'opkg' });
	try {
		env.touch('github-api-fail');
		env.touch('github-pkg-fail');
		const out = env.run(installSnippet(`tar() { printf 'Package: luci-theme-carbon\\nVersion: 1.2.0-r1\\n'; }`));
		assert.match(out, /Downloading from github:/);
		assert.match(out, /Download from github failed/);
		assert.match(out, /Downloading from pages:/);
		assert.match(out, /INSTALLED/);
		assert.deepEqual(env.urls(), [
			'https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest',
			'https://mrjoechen.github.io/luci-theme-carbon/updates/latest.json',
			'https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk',
			'https://mrjoechen.github.io/luci-theme-carbon/updates/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk'
		]);
	} finally { env.cleanup(); }

	// 3. Mirror corrupt + GitHub Releases corrupt -> falls back to Pages.
	env = releaseFallbackEnv({ manager: 'opkg', mirror: 'https://mirror.test/' });
	try {
		env.touch('mirror-corrupt');
		env.touch('github-pkg-corrupt');
		const out = env.run(installSnippet(`tar() { printf 'Package: luci-theme-carbon\\nVersion: 1.2.0-r1\\n'; }`));
		assert.match(out, /Size or SHA-256 mismatch from mirror/);
		assert.match(out, /Size or SHA-256 mismatch from github/);
		assert.match(out, /Downloading from pages:/);
		assert.match(out, /INSTALLED/);
		assert.deepEqual(env.urls(), [
			'https://api.github.com/repos/mrjoechen/luci-theme-carbon/releases/latest',
			'https://mirror.test/https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk',
			'https://github.com/mrjoechen/luci-theme-carbon/releases/download/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk',
			'https://mrjoechen.github.io/luci-theme-carbon/updates/v1.2.0/luci-theme-carbon_1.2.0-r1_all.ipk'
		]);
	} finally { env.cleanup(); }
});
