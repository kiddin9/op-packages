'use strict';
/*
 * Theme settings backend (root/usr/libexec/rpcd/luci.carbon_update): custom
 * logo. The real shell functions run with a minimal jshn stand-in and
 * temporary paths.
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
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
