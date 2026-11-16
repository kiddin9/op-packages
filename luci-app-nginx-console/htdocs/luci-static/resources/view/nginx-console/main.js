// SPDX-License-Identifier: Apache-2.0
//
// luci-app-nginx-console
//
// Master-detail console for the nginx setup on this router:
//
//   * the server sections of /etc/config/nginx (listen, server_name, include,
//     certificates) — rendered by nginx-util into uci.conf;
//   * the fragments in /etc/nginx/conf.d/*.locations, which those servers pull
//     in with `include conf.d/*.locations`.
//
// Every save goes through /usr/libexec/nginx-console, which backs the old
// content up, installs the new one, re-renders uci.conf where needed, runs
// `nginx -t` and rolls back when the test fails.  A syntax error therefore
// arrives with its file and line number instead of a summary.

'use strict';
'require view';
'require fs';
'require uci';
'require ui';
'require dom';
'require rpc';

// Two entry points on the router: the read-only one and the one that may
// change the configuration.  The rpcd ACL grants exec on the read entry to
// a read grant and on the write entry to a write grant, so a session that
// only reads cannot reach the write commands at all.
var HELPER_RO = '/usr/libexec/nginx-console';
var HELPER_RW = '/usr/libexec/nginx-console-write';

// The staged input and, in the access control view, a plain text password.  A
// fixed path is not safe: two browser tabs stage into the same file, and the
// later write wins while the earlier command still reads it, so one tab's
// content lands under the other tab's name.  Each call therefore stages into
// its own file, and the backend takes that exact path as an argument.
var PENDING_DIR = '/tmp';
var PENDING_PREFIX = 'nginx-console.pending.';
var PENDING_MODE = 384; // 0600

// Sequence for the per-call staged file name: the pid-free part is the browser
// tick so two rapid saves in the same tab still get distinct names.
var pendingSeq = 0;

function pendingPath() {
	pendingSeq++;
	return PENDING_DIR + '/' + PENDING_PREFIX + Date.now().toString(36) +
		'-' + pendingSeq + '-' + Math.floor(Math.random() * 1e6).toString(36);
}

// The commands that change something.  Everything else only reports.
var WRITE_COMMANDS = {
	'server-save': 1,
	'server-add': 1,
	'server-delete': 1,
	'frag-save': 1,
	'frag-delete': 1,
	'backup-restore': 1,
	'upload': 1
};

function helperFor(args) {
	var cmd = String((args && args[0]) || '');

	if (cmd === 'auth')
		return (args[1] === 'list') ? HELPER_RO : HELPER_RW;

	return WRITE_COMMANDS[cmd] ? HELPER_RW : HELPER_RO;
}

// Whether this session may change the configuration.  The ACL grants exec on
// the read-only entry point to a read grant and on the write entry point to a
// write grant, so the session itself knows which one it holds.
var callSessionAccess = rpc.declare({
	object: 'session',
	method: 'access',
	params: [ 'scope', 'object', 'function' ]
});

function probeWriteAccess() {
	var answer = function(r) { return { known: true, canWrite: !!(r && r.access) }; };

	return callSessionAccess('access-group', 'luci-app-nginx-console', 'write')
		.then(answer)
		.catch(function() {
			// Failing open showed the delete and save buttons to a read-only
			// session, and every click was then refused by rpcd with a message
			// that pointed at the ACL.  Failing closed keeps the page honest:
			// a session whose grant cannot be read is treated as read-only,
			// and the backend refuses writes anyway.
			return { known: false, canWrite: false };
		});
}

var CONF_DIR = '/etc/nginx/conf.d';
var UPLOAD_DIR = '/etc/luci-uploads';
var ACME_DIR = '/etc/ssl/acme';
var CERT_DIRS = [ ACME_DIR, '/etc/nginx/certs', UPLOAD_DIR ];

var SYSTEM_SECTIONS = { '_lan': true, '_redirect2ssl': true };
var FRAG_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*\.locations$/;

// Display names for the two sections the router ships with.  The uci section
// names themselves cannot change, so they stay visible in the detail header
// and in the chip tooltip.
var SECTION_LABELS = {
	'_lan': 'HTTPS 监听端口',
	'_redirect2ssl': 'HTTP 监听端口'
};

// Security headers the console can switch on per section.
var SECURITY_HEADERS = [
	{ name: 'Strict-Transport-Security',
	  value: 'Strict-Transport-Security "max-age=31536000; includeSubDomains" always',
	  label: 'HSTS（强制浏览器走 HTTPS）' },
	{ name: 'X-Frame-Options',
	  value: 'X-Frame-Options "SAMEORIGIN" always',
	  label: 'X-Frame-Options（防点击劫持）' },
	{ name: 'X-Content-Type-Options',
	  value: 'X-Content-Type-Options "nosniff" always',
	  label: 'X-Content-Type-Options（防类型嗅探）' },
	{ name: 'Referrer-Policy',
	  value: 'Referrer-Policy "strict-origin-when-cross-origin" always',
	  label: 'Referrer-Policy（控制 Referer 外泄）' }
];

// The zones live in conf.d/nginx-console-limits.conf; these are the presets
// the form can pick from.
var RATE_LIMITS = [
	{ zone: 'ncs_rl_5', rate: '5r/s', burst: 10, label: '5 请求/秒' },
	{ zone: 'ncs_rl_20', rate: '20r/s', burst: 40, label: '20 请求/秒' },
	{ zone: 'ncs_rl_100', rate: '100r/s', burst: 200, label: '100 请求/秒' }
];

// LuCI hands a UCI list back as an array, a single value as a string.
// Display name for a server section: the two built-ins get a readable label.
function serverLabel(name) {
	return SECTION_LABELS[name] || name;
}

// The router ships a fragment that redirects every plain-http request to
// https.  It is not a location block, so instead of showing it as "an
// unrecognised fragment" the redirect tab drives it with one checkbox.
// Values shared by more than one place.  Keeping them here stops the label in
// the page from drifting away from the limit the backend enforces.
var LOG_LINES = 200;              // nginx-console-lib.sh caps at 500
var MAX_FRAG_KIB = 128;           // nginx-console-lib.sh MAX_FRAG_BYTES
var MAX_UPLOAD_KIB = 256;         // nginx-console-lib.sh MAX_UPLOAD_BYTES
var TEST_OUTPUT_PREVIEW = 200;    // characters shown inline for nginx -t output
var CERT_WARN_DAYS = 30;
var CERT_CRIT_DAYS = 7;

var HTTPS_REDIRECT_FILE = '000-https-redirect.locations';
var HTTPS_REDIRECT_LINE = 'if ($scheme = http) { return 301 https://$host$request_uri; }';
var HTTPS_REDIRECT_RE = /^if\s*\(\s*\$scheme\s*=\s*http\s*\)\s*\{\s*return\s+30[0-9]\s+https:\/\/\$host\$request_uri\s*;\s*\}$/;

// Whether a file is the redirect the checkbox drives.  Comments and blank
// lines around the directive do not change what it does, so they are dropped
// before the test: an exact whole-file match reported a commented file as "not
// enabled" and the checkbox then overwrote the comment.
function isHttpsRedirect(content) {
	var meaningful = String(content || '')
		.split('\n')
		.map(function(l) { return l.trim(); })
		.filter(function(l) { return l && l.charAt(0) !== '#'; })
		.join('');

	return HTTPS_REDIRECT_RE.test(meaningful);
}

function buildHttpsRedirect() {
	return HTTPS_REDIRECT_LINE + '\n';
}

// Tabs that are a whole view of their own rather than a list of fragments.
var TOOL_TABS = { logs: 1, certs: 1, backups: 1, auth: 1, audit: 1 };

// The fragment side of the page is split by what the snippets actually do.
var FRAG_KINDS = [
	{ id: 'proxy', label: '反向代理' },
	{ id: 'forward', label: '转发' },
	{ id: 'redirect', label: '重定向' },
	{ id: 'other', label: '其他' }
];

function isCertFile(name) { return /\.(crt|cer|pem)$/i.test(name); }
function isKeyFile(name) { return /\.key$/i.test(name); }

// Colours follow the dark LuCI theme the router is currently using.
var CSS = [
	'.ncs-head{display:flex;align-items:center;gap:12px;margin-bottom:12px}',
	'.ncs-head h2{margin:0;font-size:21px;font-weight:600;line-height:1.3;border:none;padding:0}',
	'.ncs-head .ncs-sub{color:#8d8d8d;font-size:13px}',
	'.ncs-spacer{flex:1}',
	'.ncs-status{display:flex;align-items:center;gap:22px;background:#232323;border:1px solid #3a3a3a;',
	'border-radius:6px;padding:9px 14px;margin-bottom:14px;font-size:13px;color:#e2e2e2}',
	'.ncs-dot{width:9px;height:9px;border-radius:50%;display:inline-block;margin-right:7px}',
	'.ncs-dot.on{background:#4caf50}',
	'.ncs-dot.off{background:#e05252}',
	'.ncs-status .k{color:#8d8d8d}',
	'.ncs-tabs{display:flex;gap:2px;border-bottom:1px solid #3a3a3a;margin-bottom:16px}',
	'.ncs-tab{padding:8px 18px;cursor:pointer;color:#9a9a9a;font-size:14px;',
	'border-bottom:2px solid transparent;margin-bottom:-1px;user-select:none}',
	'.ncs-tab:hover{color:#cfcfcf}',
	'.ncs-tab.on{color:#3fa7d6;border-bottom-color:#3fa7d6}',
	'.ncs-tab .cnt{color:#6f6f6f;font-size:12px;margin-left:6px}',
	'.ncs-subtabs{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:14px}',
	'.ncs-subtab{padding:5px 13px;border:1px solid #3a3a3a;border-radius:14px;cursor:pointer;',
	'font-size:13px;color:#c0c0c0;background:#232323;user-select:none;',
	'display:flex;align-items:center;gap:6px}',
	'.ncs-subtab:hover{border-color:#4a4a4a}',
	'.ncs-subtab.on{background:#26343d;border-color:#3fa7d6;color:#8fc7e0}',
	'.ncs-subtab-add{border-style:dashed;color:#9a9a9a}',
	'.ncs-global{background:#232323;border:1px solid #3a3a3a;border-radius:6px;padding:12px 15px;',
	'margin-bottom:14px}',
	'.ncs-global label{display:flex;align-items:center;gap:9px;font-size:14px;cursor:pointer}',
	'.ncs-global label span.t{font-weight:600;color:#e2e2e2}',
	'.ncs-global .ncs-hint{margin-top:8px}',
	'.ncs-global code{background:#1b1b1b;padding:1px 5px;border-radius:3px;',
	'font:11.5px Menlo,Consolas,monospace;color:#a8c9d8}',
	'.ncs-cert{border:1px solid #3a3a3a;border-left:3px solid #4caf50;border-radius:5px;',
	'padding:10px 13px;margin-bottom:9px}',
	'.ncs-cert.warn{border-left-color:#d6a13f}',
	'.ncs-cert.bad{border-left-color:#c0504d}',
	'.ncs-cert .row{display:flex;align-items:baseline;gap:12px}',
	'.ncs-cert .cn{font-size:14px;font-weight:600}',
	'.ncs-cert .days{margin-left:auto;font-size:13px;color:#8d8d8d}',
	'.ncs-cert.warn .days{color:#d6a13f}',
	'.ncs-cert.bad .days{color:#e08585}',
	'.ncs-cert .sub{color:#8d8d8d;font-size:12px;margin-top:3px}',
	'.ncs-cert .mono div{font-family:Menlo,Consolas,monospace}',
	'.ncs-row{display:flex;align-items:center;gap:12px;padding:8px 0;border-bottom:1px solid #2c2c2c}',
	'.ncs-row:last-child{border-bottom:none}',
	'.ncs-row .when{color:#8d8d8d;font-size:12.5px;min-width:152px}',
	'.ncs-row .nm{font-size:12.5px}',
	'.ncs-row .sz{color:#8d8d8d;font-size:12px;margin-left:auto}',
	'.ncs-find{display:flex;gap:11px;padding:10px 0;border-bottom:1px solid #2c2c2c}',
	'.ncs-find:last-child{border-bottom:none}',
	'.ncs-find .ic{width:20px;height:20px;border-radius:50%;flex:0 0 auto;text-align:center;',
	'line-height:20px;font-size:12px;font-weight:700;background:#3a3a3a;color:#c0c0c0}',
	'.ncs-find.warn .ic{background:#4a3a1e;color:#d6a13f}',
	'.ncs-find.error .ic{background:#4a2424;color:#e08585}',
	'.ncs-find .ti{font-size:13.5px;font-weight:600}',
	'.ncs-find .de{color:#8d8d8d;font-size:12px;margin-top:2px;word-break:break-all}',
	'.ncs-sys{font-size:10.5px;padding:0 6px;border-radius:8px;background:#33414a;color:#8fc7e0}',
	'.ncs-main{background:#232323;border:1px solid #3a3a3a;border-radius:6px}',
	'.ncs-main .top{display:flex;align-items:center;gap:10px;padding:12px 16px;border-bottom:1px solid #3a3a3a}',
	'.ncs-main .top .t{font-size:16px;font-weight:600;color:#e2e2e2}',
	'.ncs-main .top .meta{color:#8d8d8d;font-size:12px;font-family:Menlo,Consolas,monospace}',
	'.ncs-sec{padding:14px 16px;border-bottom:1px solid #2c2c2c}',
	'.ncs-sec:last-child{border-bottom:none}',
	'.ncs-sec h3{font-size:13px;margin:0 0 11px;color:#c8c8c8;font-weight:600}',
	'.ncs-field{display:grid;grid-template-columns:132px 1fr;gap:12px;margin-bottom:10px;align-items:start}',
	'.ncs-field:last-child{margin-bottom:0}',
	'.ncs-lbl{font-size:13px;color:#c0c0c0;padding-top:2px}',
	'.ncs-lbl .d{display:block;color:#7f7f7f;font-size:11.5px;font-family:Menlo,Consolas,monospace}',
	'.ncs-val{font-size:13px;color:#dcdcdc}',
	'.ncs-val .mono{font-family:Menlo,Consolas,monospace;font-size:12.5px}',
	'.ncs-val div{padding:1px 0}',
	'.ncs-size{color:#7f7f7f;font-size:12px}',
	'.ncs-empty{color:#6f6f6f}',
	'.ncs-note{color:#8d8d8d;font-size:12px;margin:12px 0 0;line-height:1.6}',
	'.ncs-hint{color:#7f7f7f;font-size:12px;margin:6px 0 0;line-height:1.5}',
	'.ncs-badge{font-size:11px;padding:1px 7px;border-radius:9px;background:#33414a;color:#8fc7e0}',
	'.ncs-btn{border:1px solid #3a3a3a;background:#2c2c2c;color:#e2e2e2;padding:5px 12px;',
	'border-radius:4px;font-size:13px;cursor:pointer;font-family:inherit}',
	'.ncs-btn:hover:not([disabled]){background:#353535}',
	'.ncs-btn[disabled]{opacity:.55;cursor:default}',
	'.ncs-btn.primary{background:#2f6f8f;border-color:#2f6f8f;color:#fff}',
	'.ncs-btn.primary:hover:not([disabled]){background:#357ba0}',
	'.ncs-btn.danger{border-color:#5c2e2e;color:#e08585}',
	'.ncs-btn.danger:hover:not([disabled]){background:#2a1d1d}',
	'.ncs-input{flex:1;background:#1c1c1c;border:1px solid #3a3a3a;border-radius:4px;color:#e2e2e2;',
	'padding:5px 9px;font:12.5px Menlo,Consolas,monospace;outline:none;min-width:0}',
	'.ncs-input:focus{border-color:#3fa7d6}',
	'.ncs-inrow{display:flex;align-items:center;gap:7px;margin-bottom:5px}',
	'.ncs-x{background:transparent;border:1px solid #5c2e2e;color:#e08585;border-radius:4px;',
	'padding:4px 9px;font-size:12px;cursor:pointer;line-height:1;font-family:inherit}',
	'.ncs-x:hover{background:#2a1d1d}',
	'.ncs-add{background:transparent;border:1px dashed #4a4a4a;color:#9a9a9a;border-radius:4px;',
	'padding:4px 11px;font-size:12.5px;cursor:pointer;margin-top:2px;font-family:inherit}',
	'.ncs-add:hover{border-color:#5f5f5f;color:#c0c0c0}',
	'.ncs-filebtn{width:100%;text-align:left;background:#1c1c1c;border:1px solid #3a3a3a;',
	'border-radius:4px;color:#e2e2e2;padding:6px 10px;font:12.5px Menlo,Consolas,monospace;',
	'cursor:pointer;word-break:break-all}',
	'.ncs-filebtn:hover{border-color:#4a4a4a}',
	'.ncs-filebtn.empty{color:#7f7f7f}',
	'.ncs-picklist{max-height:230px;overflow:auto;border:1px solid #3a3a3a;border-radius:4px;background:#1c1c1c}',
	'.ncs-pickrow{display:flex;align-items:center;gap:10px;padding:7px 10px;border-bottom:1px solid #2a2a2a;cursor:pointer}',
	'.ncs-pickrow:last-child{border-bottom:none}',
	'.ncs-pickrow:hover{background:#262626}',
	'.ncs-pickrow .mono{flex:1;font-family:Menlo,Consolas,monospace;font-size:12px;word-break:break-all}',
	'.ncs-pick-empty{padding:12px;color:#7f7f7f;font-size:12.5px;text-align:center}',
	'.ncs-modal-row{margin-bottom:14px}',
	'.ncs-modal-row .lbl{font-size:12.5px;color:#9a9a9a;margin-bottom:6px}',
	'.ncs-frag{margin:0;padding:12px 14px;background:#1b1b1b;border-radius:4px;',
	'font:12px/1.6 Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-word;',
	'color:#cfcfcf;max-height:520px;overflow:auto}',
	'.ncs-frag-edit{width:100%;min-height:360px;background:#1b1b1b;border:1px solid #3a3a3a;',
	'border-radius:4px;color:#e2e2e2;padding:12px 14px;font:12px/1.6 Menlo,Consolas,monospace;',
	'white-space:pre;tab-size:4;outline:none}',
	'.ncs-frag-edit:focus{border-color:#3fa7d6}',
	'.ncs-result{margin-bottom:14px;border:1px solid #3a3a3a;border-radius:6px;padding:10px 13px}',
	'.ncs-result.ok{border-color:#2e5c33;background:#1d2a1e}',
	'.ncs-result.err{border-color:#5c2e2e;background:#2a1d1d}',
	'.ncs-result-head{display:flex;align-items:center;gap:10px;font-size:13px}',
	'.ncs-result-head .t{font-weight:600}',
	'.ncs-result.ok .t{color:#8bd48b}',
	'.ncs-result.err .t{color:#e08585}',
	'.ncs-pre{margin:9px 0 0;padding:9px 11px;background:#161616;border-radius:4px;',
	'font:12px/1.5 Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-all;',
	'max-height:220px;overflow:auto;color:#cfcfcf}',
	'.ncs-switch{display:inline-flex;align-items:center;gap:9px;cursor:pointer;font-size:13px;',
	'color:#dcdcdc;user-select:none;line-height:1.4}',
	'.ncs-switch input{position:absolute;opacity:0;width:0;height:0}',
	'.ncs-switch .tr{width:38px;height:21px;border-radius:11px;background:#454545;position:relative;',
	'transition:background .15s;flex:0 0 auto;border:1px solid #565656}',
	'.ncs-switch .kn{position:absolute;top:2px;left:2px;width:15px;height:15px;border-radius:50%;',
	'background:#e2e2e2;transition:left .15s}',
	'.ncs-switch input:checked + .tr{background:#2f6f8f;border-color:#2f6f8f}',
	'.ncs-switch input:checked + .tr .kn{left:20px;background:#fff}',
	'.ncs-switch input:focus-visible + .tr{outline:2px solid #3fa7d6;outline-offset:2px}',
	'.ncs-switch input:disabled + .tr{opacity:.45}',
	'.ncs-switchlist{display:flex;flex-direction:column;gap:9px}',
	'.ncs-seg{display:inline-flex;border:1px solid #3a3a3a;border-radius:4px;overflow:hidden;',
	'background:#1c1c1c;max-width:100%;flex-wrap:wrap}',
	'.ncs-seg button{background:transparent;border:none;border-right:1px solid #3a3a3a;color:#b8b8b8;',
	'padding:5px 12px;font-size:12.5px;cursor:pointer;font-family:inherit;white-space:nowrap}',
	'.ncs-seg button:last-child{border-right:none}',
	'.ncs-seg button:hover{background:#2a2a2a}',
	'.ncs-seg button.on{background:#2f6f8f;color:#fff}',
	'.ncs-rangewrap{display:flex;align-items:center;gap:12px;max-width:440px}',
	'.ncs-range{-webkit-appearance:none;appearance:none;flex:1;height:4px;border-radius:2px;',
	'background:#3f3f3f;outline:none;min-width:80px}',
	'.ncs-range::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;width:16px;height:16px;',
	'border-radius:50%;background:#3fa7d6;border:none;cursor:pointer}',
	'.ncs-range::-moz-range-thumb{width:16px;height:16px;border-radius:50%;background:#3fa7d6;',
	'border:none;cursor:pointer}',
	'.ncs-rangeedit{flex:0 0 96px;width:96px}',
	'.ncs-rangecustom{color:#8d8d8d;font-size:11.5px;margin-top:4px}',
	'.ncs-rangecustom b{color:#dcdcdc;font-weight:600}',
	'.ncs-ro{background:#2b2a1e;border:1px solid #5b5230;border-radius:6px;padding:9px 14px;',
	'margin-bottom:14px;font-size:13px;color:#e2d6a8}'
].join('');

// ---------------------------------------------------------------- widgets
//
// The settings that are a plain "on or off" or a small fixed set of choices
// are drawn as switches, sliders and segmented buttons instead of dropdowns:
// the current state is visible without opening anything, and the alternatives
// are on screen instead of hidden behind a click.

// A switch.  The knob carries the state, the label says what it is.
function toggleSwitch(label, checked, onChange) {
	var box = E('input', { 'type': 'checkbox' });

	box.checked = !!checked;

	var el = E('label', { 'class': 'ncs-switch' }, [
		box,
		E('span', { 'class': 'tr' }, [ E('span', { 'class': 'kn' }) ]),
		E('span', {}, [ label ])
	]);

	if (onChange)
		box.addEventListener('change', function() { onChange(box.checked); });

	return {
		el: el,
		inputs: [ box ],
		value: function() { return !!box.checked; }
	};
}

// A slider over a fixed list of values, with the raw value next to it.
//
// The value that is on the disk wins as long as the user does not touch the
// control: a value that is not on the list (an unusual timeout, a hand tuned
// connection count) is shown as it is and stays as it is until the slider or
// the text field is used.  Nothing is silently replaced by a preset.
function valueSlider(values, current, opts) {
	var idx = -1, i;

	opts = opts || {};
	current = (current == null) ? '' : String(current);

	for (i = 0; i < values.length; i++) {
		if (values[i].value === current) {
			idx = i;
			break;
		}
	}

	var range = E('input', {
		'type': 'range',
		'class': 'ncs-range',
		'min': '0',
		'max': String(values.length - 1),
		'step': '1'
	});
	var text = E('input', {
		'class': 'ncs-input ncs-rangeedit',
		'value': current,
		'placeholder': opts.empty || '自定义'
	});
	var note = E('div', { 'class': 'ncs-rangecustom' }, [ '' ]);

	var dirty = false, typed = false;

	range.value = String(idx < 0 ? 0 : idx);

	function refresh() {
		var at = Number(range.value);

		if (dirty && !typed)
			dom.content(note, [ '当前档位：', E('b', {}, [ values[at].label ]) ]);
		else if (idx < 0 && !dirty)
			dom.content(note, [ '原值 ', E('b', {}, [ current ]),
				' 不在档位里，移动滑块或直接改右边才会写入新值' ]);
		else
			note.textContent = '';
	}

	range.addEventListener('input', function() {
		var at = Number(range.value);

		dirty = true;
		typed = false;
		text.value = values[at].value;
		refresh();
	});

	text.addEventListener('input', function() {
		dirty = true;
		typed = true;
		refresh();
	});

	refresh();

	return {
		el: E('div', {}, [
			E('div', { 'class': 'ncs-rangewrap' }, [ range, text ]),
			opts.hint ? E('div', { 'class': 'ncs-rangecustom' }, [ opts.hint ]) : '',
			note
		]),
		inputs: [ range, text ],
		value: function() {
			if (typed)
				return String(text.value || '').trim();
			if (!dirty)
				return current;
			return values[Number(range.value)].value;
		}
	};
}

// A row of buttons where exactly one is active.  For a small fixed set of
// choices this shows all of them at once, which a dropdown does not.
function segmented(options, current, onPick) {
	var host = E('div', { 'class': 'ncs-seg' }, []);

	options.forEach(function(o) {
		var b = E('button', { 'type': 'button', 'data-value': o.value }, [ o.label ]);

		b.addEventListener('click', function() {
			Array.prototype.forEach.call(host.querySelectorAll('button'), function(x) {
				x.classList.remove('on');
			});
			b.classList.add('on');

			if (onPick)
				onPick(o.value);
		});

		if (o.value === current)
			b.classList.add('on');

		host.appendChild(b);
	});

	return {
		el: host,
		value: function() {
			var on = host.querySelector('button.on');
			return on ? on.getAttribute('data-value') : (current || '');
		}
	};
}

var ERR_TEXT = {
	invalid_name: '文件名不合法',
	invalid_section: '段名不合法',
	no_such_section: '该 server 段不存在',
	not_found: '文件不存在',
	empty: '内容为空',
	too_large: '内容超过 ' + MAX_FRAG_KIB + ' KiB',
	pending_missing: '编辑内容没有传达到后端',
	invalid_value: '提交的值不被接受（include 只能是配置目录内的路径，日志只能是 logd/syslog/off 或 /var/log/nginx/ 下的文件）',
	snapshot_failed: '快照失败，已取消保存',
	write_failed: '写入失败',
	commit_failed: '写入 /etc/config/nginx 失败',
	guard_failed: '改动被安全校验拦下',
	test_failed: 'nginx 拒绝了新配置，已回滚',
	reload_failed: 'nginx 重载失败，已回滚',
	exec_failed: '无法执行后端脚本（检查 ACL 或 /usr/libexec/nginx-console）',
	bad_reply: '后端返回内容无法解析',
	unknown_command: '未知命令',
	already_exists: '同名的段已存在',
	protected_section: '该段受保护，不能删除',
	invalid_user: '用户名不合法（只允许字母、数字和 _ . -）',
	empty_password: '密码不能为空',
	hash_failed: '密码哈希生成失败',
	permission_denied: '当前账号没有写权限',
	no_such_user: '该用户不存在',
	no_such_backup: '该备份不存在',
	bad_backup_path: '备份路径不合法',
	bad_backup_name: '备份文件名不合法',
	bad_source: '日志来源不合法',
	unknown_action: '未知操作'
};

function errText(r) {
	r = r || {};
	return ERR_TEXT[r.error] || r.error || '未知错误';
}

// The helper is called through rpcd's file.exec.  The ACL grants exec on the
// exact path of the entry point that the command belongs to, so a session that
// only holds the read grant cannot run the write entry point at all - the
// permission is checked against the path, not against the arguments.
function callHelper(args) {
	function parse(out) {
		var txt = String(out == null ? '' : out).trim();
		try {
			return JSON.parse(txt);
		} catch (e) {
			return { ok: false, error: 'bad_reply', output: txt };
		}
	}

	return fs.exec(helperFor(args), args).then(function(res) {
		return parse(res && res.stdout);
	}).catch(function(e) {
		return {
			ok: false,
			error: 'exec_failed',
			output: (e && e.message) || String(e)
		};
	});
}

function asList(value) {
	if (value == null || value === '')
		return [];
	return Array.isArray(value) ? value : [ value ];
}

// Stages one command's input into its own file and runs the helper against that
// exact path.  The file is removed in both outcomes, so a password or a key is
// not left behind when the command is refused or the page goes away.
function stageAndCall(content, args) {
	var path = pendingPath();
	var argv = args.concat([ path ]);

	return fs.write(path, String(content == null ? '' : content), PENDING_MODE)
		.catch(function() {
			// A leftover from an earlier run may exist with another mode:
			// remove it and write again, so the mode is the one asked for.
			return fs.remove(path).then(function() {
				return fs.write(path, String(content == null ? '' : content), PENDING_MODE);
			});
		})
		.then(function() { return callHelper(argv); })
		.then(function(r) {
			fs.remove(path).catch(function() {});
			return r;
		}, function(e) {
			fs.remove(path).catch(function() {});
			return { ok: false, error: 'exec_failed', output: (e && e.message) || String(e) };
		});
}

function fmtSize(n) {
	n = Number(n) || 0;
	return n < 1024 ? n + ' B' : (n / 1024).toFixed(1) + ' KiB';
}

function fmtTime(ts) {
	ts = Number(ts) || 0;
	if (!ts)
		return '';

	var d = new Date(ts * 1000);
	var p = function(v) { return (v < 10 ? '0' : '') + v; };

	return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) +
		' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}

// Whether an add_header value starts with exactly this header name.  A prefix
// test would also match X-Frame-Options-Report-Only, which is a different
// header, so the name has to end at a space or at the end of the value.
function isHeaderNamed(value, name) {
	var v = String(value || '').trim();

	if (v.length < name.length || v.slice(0, name.length).toLowerCase() !== name.toLowerCase())
		return false;

	return v.length === name.length || /\s/.test(v.charAt(name.length));
}

// Ports of one section, for the chip label.  The port is the number that
// follows the last colon (or the only number when no address is given): taking
// the first number in the value printed 127 for "127.0.0.1:8080".
// The audit level decides the icon and colour, so an unexpected value from the
// backend is mapped to a known one instead of being used as a class name.
function findingLevel(f) {
	var l = String((f && f.level) || '');

	return (l === 'warn' || l === 'error') ? l : 'info';
}

function portsOf(section) {
	var seen = {};

	asList(section.listen).forEach(function(l) {
		var v = String(l);
		var m = /:(\d{1,5})(?:\s|$)/.exec(v) || /^(\d{1,5})(?:\s|$)/.exec(v);

		if (m)
			seen[m[1]] = true;
	});

	return Object.keys(seen).join(' ');
}

// ---------------------------------------------------------------- fragments

// A fragment is a location-level nginx snippet.  Which tab it shows up in is
// decided by the directives it contains, not by its name.
function classifyFragment(content) {
	var c = String(content || '');

	if (/(^|\s)proxy_pass\s/.test(c))
		return 'proxy';
	if (/(^|\s)(uwsgi_pass|fastcgi_pass|scgi_pass|grpc_pass)\s/.test(c))
		return 'forward';
	if (/(^|\s)return\s+30[0-9](\s|;)/.test(c))
		return 'redirect';

	return 'other';
}

// The lines inside a proxy block that the form models itself.  Everything else
// is carried over untouched, so opening a fragment in the form and saving it
// again does not throw directives away.
var PROXY_MODELLED = [
	/^proxy_pass\s/,
	/^proxy_set_header\s+host\b/i,
	/^proxy_connect_timeout\s/,
	/^proxy_send_timeout\s/,
	/^proxy_read_timeout\s/
];

// The WebSocket switch owns these: they are written as one block and removed
// again when the switch is turned off.
var PROXY_WS = [
	/^proxy_set_header\s+upgrade\b/i,
	/^proxy_set_header\s+connection\b/i,
	/^proxy_http_version\s/
];

// Finds the end of a block by counting braces, so a nested block (an "if" for
// example) does not cut the fragment in half.
function balancedBlock(text, open) {
	var depth = 0, i;

	for (i = open; i < text.length; i++) {
		var ch = text.charAt(i);

		if (ch === '{')
			depth++;
		else if (ch === '}') {
			depth--;
			if (depth === 0)
				return { inner: text.slice(open + 1, i), end: i };
		}
	}

	return null;
}

// Strips a `#` comment from one line.  A `#` inside a quoted string is content,
// not a comment, so the quotes are tracked.
function stripComment(line) {
	var out = '', quote = '';

	for (var i = 0; i < line.length; i++) {
		var ch = line.charAt(i);

		if (quote) {
			out += ch;
			if (ch === quote)
				quote = '';
		}
		else if (ch === '"' || ch === "'") {
			quote = ch;
			out += ch;
		}
		else if (ch === '#')
			break;
		else
			out += ch;
	}

	return out;
}

// Net brace count of one line, ignoring braces inside quoted strings.
function braceDelta(line) {
	var d = 0, quote = '';

	for (var i = 0; i < line.length; i++) {
		var ch = line.charAt(i);

		if (quote) {
			if (ch === quote)
				quote = '';
			continue;
		}
		if (ch === '"' || ch === "'") {
			quote = ch;
			continue;
		}
		if (ch === '{')
			d++;
		else if (ch === '}')
			d--;
	}

	return d;
}

// Splits a location body into its first-level lines and its nested blocks.
// Nested blocks (an "if", a nested location) are kept whole as one entry so a
// scan for a directive never reaches inside them: a proxy_pass under an `if`
// belongs to that condition and is not the block's own backend.
// Returns null when a block never closes, so the caller can fall back instead
// of guessing at the structure.
function splitTopLevel(inner) {
	var lines = String(inner || '').split('\n');
	var out = [];
	var block = null, depth = 0;

	for (var i = 0; i < lines.length; i++) {
		var raw = lines[i];
		var l = stripComment(raw).trim();

		if (block !== null) {
			block.push(raw);
			depth += braceDelta(l);

			if (depth <= 0) {
				out.push({ block: block.join('\n').trim() });
				block = null;
				depth = 0;
			}
			continue;
		}

		if (!l)
			continue;

		var d = braceDelta(l);

		if (d > 0) {
			block = [ raw ];
			depth = d;
			continue;
		}

		out.push({ line: l });
	}

	if (block !== null)
		return null;

	return out;
}

// True when the text holds nothing but blank lines and comments.
function onlyComments(text) {
	var lines = String(text || '').split('\n');

	for (var i = 0; i < lines.length; i++) {
		var l = lines[i].trim();

		if (l && l.charAt(0) !== '#')
			return false;
	}

	return true;
}

// The comment lines of a text, in order.
function commentLines(text) {
	return String(text || '').split('\n').map(function(l) { return l.trim(); })
		.filter(function(l) { return l.charAt(0) === '#'; });
}

// The lines of a block that the form does not model.  With firstOnly the
// first matching line is the modelled one and later ones are kept.
function unmodelledLines(inner, isModelled, firstOnly) {
	var out = [], seen = false;

	String(inner || '').split('\n').forEach(function(line) {
		var l = line.trim();

		if (!l)
			return;

		if (!seen && isModelled(l)) {
			seen = true;
			return;
		}

		out.push(l);
	});

	return out;
}

// A fragment the structured forms can edit: exactly one location block with
// nothing but comments around it.  Everything the form does not model is
// handed back as `extra` (inside the block), `head` and `tail` (around it), so
// a save never throws content away.
function parseLocationFragment(content) {
	var c = String(content || '');
	// Count every location block, whatever modifier it carries, so a file with
	// two of them is refused instead of being treated as one.
	var blocks = c.match(/location\s*(?:=[ \t]*|\^~[ \t]*|~\*[ \t]*|~[ \t]*)?[^\s{]*\s*\{/g);

	if (!blocks || blocks.length !== 1)
		return null;

	// The modifier is part of the matching rule, not decoration: `= /x` is an
	// exact match while `/x` is a prefix match that also catches /x/anything.
	// It is captured so a rebuild writes the same rule back; dropping it would
	// silently widen the scope of the block with `nginx -t` still passing.
	var m = /location\s*(=[ \t]*|\^~[ \t]*|~\*[ \t]*|~[ \t]*)?([^\s{]+)\s*\{/.exec(c);

	if (!m)
		return null;

	var open = c.indexOf('{', m.index);

	if (open < 0)
		return null;

	var blk = balancedBlock(c, open);

	if (!blk)
		return null;

	var head = c.slice(0, m.index);
	var tail = c.slice(blk.end + 1);

	// Anything but a comment around the block means the file is more than the
	// form can describe: the text editor handles it instead.
	if (!onlyComments(head) || !onlyComments(tail))
		return null;

	return {
		modifier: (m[1] || '').replace(/[ \t]+$/, ''),
		path: m[2],
		inner: blk.inner,
		head: head,
		tail: tail
	};
}

// "location = /x {" / "location /x {" depending on whether the parsed block
// carried a modifier.  Every build*Fragment writes its block through this so no
// kind can lose the modifier on its own.
function locationHead(loc, path) {
	var modifier = String(loc && loc.modifier || '').trim();

	return 'location ' + (modifier ? modifier + ' ' : '') + path + ' {';
}

function directiveValue(body, name) {
	var m = new RegExp('(^|\\n)[ \\t]*' + name + '[ \\t]+([^;]+);').exec(body);
	return m ? m[2].trim() : '';
}

// A fragment made of exactly one location block with proxy_pass can be edited
// as a form.  Anything richer (several locations, directives the form does not
// model) stays in the text editor, so opening it in the form never throws
// content away.
function parseProxyFragment(content) {
	var loc = parseLocationFragment(content);

	if (!loc)
		return null;

	// Only the block's own directives count.  A proxy_pass inside an `if` is
	// conditional and must not be mistaken for the backend of the whole block,
	// so the body is split into first-level lines and opaque nested blocks.
	var parts = splitTopLevel(loc.inner);

	if (!parts)
		return null;

	var passes = parts.filter(function(p) {
		return p.line && /^proxy_pass\s/.test(p.line);
	});

	// Two first-level proxy_pass directives cannot be described by a single
	// form field: the text editor keeps them instead of guessing.
	if (passes.length !== 1)
		return null;

	var pm = /^proxy_pass\s+([^;]+);/.exec(passes[0].line);

	if (!pm)
		return null;

	var websocket = parts.some(function(p) {
		return p.line && /^proxy_set_header\s+upgrade\b/i.test(p.line);
	});

	// The Host header is a form field of its own: it is read here so a hand
	// written value survives a save instead of being replaced by the default.
	var host = '$host';

	parts.forEach(function(p) {
		var hm = p.line && /^proxy_set_header\s+host\s+(.+);$/i.exec(p.line);
		if (hm)
			host = hm[1].trim();
	});

	var extra = [], wsLines = [];

	parts.forEach(function(p) {
		// A nested block is never modelled: it goes back out unchanged.
		if (p.block) {
			extra.push(p.block);
			return;
		}

		var l = p.line;

		if (PROXY_MODELLED.some(function(re) { return re.test(l); }))
			return;

		if (websocket && (PROXY_WS.some(function(re) { return re.test(l); }) ||
			/^proxy_buffering\s/.test(l))) {
			wsLines.push(l);
			return;
		}

		extra.push(l);
	});

	return {
		modifier: loc.modifier,
		path: loc.path,
		target: pm[1].trim(),
		host: host,
		websocket: websocket,
		wsLines: wsLines,
		connectTimeout: directiveValue(loc.inner, 'proxy_connect_timeout'),
		sendTimeout: directiveValue(loc.inner, 'proxy_send_timeout'),
		readTimeout: directiveValue(loc.inner, 'proxy_read_timeout'),
		extra: extra.join('\n'),
		head: loc.head,
		tail: loc.tail
	};
}

function buildProxyFragment(f) {
	var lines = [];

	commentLines(f.head).forEach(function(l) { lines.push(l); });

	lines.push(locationHead(f, f.path));
	lines.push('\tproxy_pass ' + f.target + ';');
	lines.push('\tproxy_set_header Host ' + (f.host || '$host') + ';');

	if (f.websocket) {
		var ws = (f.wsLines && f.wsLines.length) ? f.wsLines : [
			'proxy_set_header Upgrade $http_upgrade;',
			'proxy_set_header Connection "upgrade";',
			'proxy_http_version 1.1;',
			'proxy_buffering off;'
		];

		ws.forEach(function(l) { lines.push('\t' + l); });
	}

	if (f.connectTimeout)
		lines.push('\tproxy_connect_timeout ' + f.connectTimeout + ';');
	if (f.sendTimeout)
		lines.push('\tproxy_send_timeout ' + f.sendTimeout + ';');
	if (f.readTimeout)
		lines.push('\tproxy_read_timeout ' + f.readTimeout + ';');

	String(f.extra || '').split('\n').forEach(function(l) {
		l = l.trim();
		if (l)
			lines.push('\t' + l);
	});

	lines.push('}');

	commentLines(f.tail).forEach(function(l) { lines.push(l); });

	return lines.join('\n') + '\n';
}

function fragmentNameFromPath(path) {
	var s = String(path || '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
	return (s || 'proxy') + '.locations';
}

function parseRedirectFragment(content) {
	var loc = parseLocationFragment(content);

	if (!loc)
		return null;

	var rm = /return\s+(30[0-9])\s+([^;]+);/.exec(loc.inner);

	if (!rm)
		return null;

	return {
		modifier: loc.modifier,
		path: loc.path,
		code: rm[1],
		target: rm[2].trim(),
		extra: unmodelledLines(loc.inner, function(l) {
			return /^return\s+30[0-9]\s/.test(l);
		}, true).join('\n'),
		head: loc.head,
		tail: loc.tail
	};
}

function buildRedirectFragment(f) {
	var lines = [];

	commentLines(f.head).forEach(function(l) { lines.push(l); });

	lines.push(locationHead(f, f.path));
	lines.push('\treturn ' + f.code + ' ' + f.target + ';');

	String(f.extra || '').split('\n').forEach(function(l) {
		l = l.trim();
		if (l)
			lines.push('\t' + l);
	});

	lines.push('}');

	commentLines(f.tail).forEach(function(l) { lines.push(l); });

	return lines.join('\n') + '\n';
}

var FORWARD_PROTOS = [
	{ value: 'uwsgi', label: 'uwsgi', include: 'uwsgi_params' },
	{ value: 'fastcgi', label: 'fastcgi', include: 'fastcgi_params' },
	{ value: 'scgi', label: 'scgi', include: 'scgi_params' },
	{ value: 'grpc', label: 'grpc', include: '' }
];

function parseForwardFragment(content) {
	var loc = parseLocationFragment(content);

	if (!loc)
		return null;

	var pm = /(uwsgi_pass|fastcgi_pass|scgi_pass|grpc_pass)\s+([^;]+);/.exec(loc.inner);

	if (!pm)
		return null;

	var proto = pm[1].replace('_pass', '');
	var passRe = new RegExp('^' + proto + '_pass\\s');

	// The include belongs to the form: a file that brings its own keeps it,
	// instead of getting the default one of the protocol.
	var include = '';
	var im = /(^|\n)[ \t]*include[ \t]+([^;]+);/.exec(loc.inner);

	if (im)
		include = im[2].trim();

	var extra = [], seenPass = false, seenInclude = false;

	String(loc.inner || '').split('\n').forEach(function(line) {
		var l = line.trim();

		if (!l)
			return;

		if (!seenPass && passRe.test(l)) {
			seenPass = true;
			return;
		}

		if (!seenInclude && /^include\s/.test(l)) {
			seenInclude = true;
			return;
		}

		extra.push(l);
	});

	return {
		modifier: loc.modifier,
		path: loc.path,
		proto: proto,
		target: pm[2].trim(),
		include: include,
		extra: extra.join('\n'),
		head: loc.head,
		tail: loc.tail
	};
}

function buildForwardFragment(f) {
	var proto = FORWARD_PROTOS.filter(function(p) { return p.value === f.proto; })[0];
	var lines = [];

	commentLines(f.head).forEach(function(l) { lines.push(l); });

	lines.push(locationHead(f, f.path));

	var include = f.include || (proto ? proto.include : '');

	if (include)
		lines.push('\tinclude ' + include + ';');

	lines.push('\t' + f.proto + '_pass ' + f.target + ';');

	String(f.extra || '').split('\n').forEach(function(l) {
		l = l.trim();
		if (l)
			lines.push('\t' + l);
	});

	lines.push('}');

	commentLines(f.tail).forEach(function(l) { lines.push(l); });

	return lines.join('\n') + '\n';
}

function listFragments() {
	return fs.list(CONF_DIR).then(function(entries) {
		var files = (entries || []).filter(function(e) {
			return e && (e.type === 'file' || e.type === 'symlink') && FRAG_NAME_RE.test(e.name);
		}).sort(function(a, b) {
			return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
		});

		// The content is needed to tell the kinds apart and to fill the form,
		// and fragments are small, so all of them are read up front.
		return Promise.all(files.map(function(e) {
			return fs.read(CONF_DIR + '/' + e.name).then(function(c) {
				var content = String(c == null ? '' : c);

				return {
					name: e.name,
					size: e.size,
					mtime: e.mtime,
					content: content,
					kind: classifyFragment(content)
				};
			}).catch(function() {
				return {
					name: e.name, size: e.size, mtime: e.mtime,
					content: '', kind: 'other'
				};
			});
		}));
	}).catch(function() { return []; });
}

// A read-only row of the detail pane.
function readField(label, directive, values, opts) {
	var list = asList(values);
	var body;

	if (list.length) {
		body = list.map(function(v) {
			return E('div', { 'class': 'mono' }, [ String(v) ]);
		});
	} else {
		body = [ E('span', { 'class': 'ncs-empty' }, [ '—' ]) ];
	}

	var cell = E('div', { 'class': 'ncs-val' }, body);
	if (opts && opts.sizeOf)
		cell.appendChild(E('span', { 'class': 'ncs-size' }, [ '' ]));

	return E('div', { 'class': 'ncs-field' }, [
		E('div', { 'class': 'ncs-lbl' }, [ label, E('span', { 'class': 'd' }, [ directive ]) ]),
		cell
	]);
}

function decorateSize(cell, path) {
	var tail = cell.querySelector('.ncs-size');
	if (!tail || !path)
		return;

	fs.stat(path).then(function(st) {
		if (st && st.size != null)
			tail.textContent = ' (' + fmtSize(st.size) + ')';
	}).catch(function() {});
}

// Editable list of values: one input per entry plus a trailing empty one.
function listEditor(values) {
	var host = E('div');

	function addRow(value) {
		var input = E('input', { 'class': 'ncs-input', 'value': value == null ? '' : value });
		var row = E('div', { 'class': 'ncs-inrow' }, [
			input,
			E('button', {
				'class': 'ncs-x',
				'click': function() { host.removeChild(row); }
			}, [ '✕' ])
		]);

		host.appendChild(row);
		return input;
	}

	asList(values).forEach(addRow);
	addRow('');

	var addBtn = E('button', {
		'class': 'ncs-add',
		'click': function() { addRow('').focus(); }
	}, [ '+ 添加' ]);

	return {
		host: host,
		addBtn: addBtn,
		values: function() {
			return Array.prototype.slice.call(host.querySelectorAll('input'))
				.map(function(i) { return i.value.trim().replace(/\t/g, ' '); })
				.filter(function(v) { return v !== ''; });
		}
	};
}

// Opens a modal that picks a file: existing candidates, a typed path or a fresh
// upload.  Uploads are written as text (PEM certificates and keys are text).
function openPicker(title, filter, current, onPick) {
	var input = E('input', {
		'class': 'ncs-input',
		'style': 'width:100%',
		'value': current || '',
		'placeholder': ACME_DIR + '/example.com.fullchain.crt'
	});
	var listBox = E('div', { 'class': 'ncs-picklist' },
		[ E('div', { 'class': 'ncs-pick-empty' }, [ '读取中…' ]) ]);
	var note = E('span', { 'class': 'ncs-hint' }, [ '' ]);
	var fileInput = E('input', { 'type': 'file', 'style': 'display:none' });

	function renderCandidates(paths) {
		if (!paths.length) {
			dom.content(listBox, E('div', { 'class': 'ncs-pick-empty' }, [ '这些目录里没有匹配的文件' ]));
			return;
		}

		dom.content(listBox, paths.map(function(p) {
			var sizeEl = E('span', { 'class': 'ncs-size' }, [ '' ]);

			fs.stat(p).then(function(st) {
				if (st && st.size != null)
					sizeEl.textContent = fmtSize(st.size);
			}).catch(function() {});

			return E('div', {
				'class': 'ncs-pickrow',
				'click': function() { input.value = p; }
			}, [
				E('span', { 'class': 'mono' }, [ p ]),
				sizeEl
			]);
		}));
	}

	function loadCandidates() {
		Promise.all(CERT_DIRS.map(function(dir) {
			return fs.list(dir).then(function(entries) {
				return (entries || [])
					.filter(function(e) {
						return e && (e.type === 'file' || e.type === 'symlink') && filter(e.name);
					})
					.map(function(e) { return dir + '/' + e.name; });
			}).catch(function() { return []; });
		})).then(function(groups) {
			var all = [], seen = {};

			groups.forEach(function(g) {
				g.forEach(function(p) {
					if (!seen[p]) {
						seen[p] = true;
						all.push(p);
					}
				});
			});

			renderCandidates(all);
		});
	}

	fileInput.addEventListener('change', function() {
		var f = fileInput.files && fileInput.files[0];
		if (!f)
			return;

		var reader = new FileReader();

		reader.onload = function() {
			// The file name is not trusted: the backend checks it against a
			// whitelist, installs the file itself and picks the mode the
			// content asks for (a private key stays readable for root only).
			stageAndCall(String(reader.result), [ 'upload', String(f.name || '') ])
				.then(function(r) {
					r = r || {};

					if (!r.ok) {
						note.textContent = '上传失败：' + errText(r);
						return;
					}

					input.value = r.path || '';
					note.textContent = '已上传到 ' + (r.path || '');
					loadCandidates();
				})
				.catch(function(e) {
					note.textContent = '上传失败：' + ((e && e.message) || e);
				});
		};

		reader.onerror = function() { note.textContent = '读取文件失败'; };
		reader.readAsText(f);
	});

	ui.showModal(title, [
		E('div', { 'class': 'ncs-modal-row' }, [
			E('div', { 'class': 'lbl' }, [ '从这些目录里选（点一行即可填入）' ]),
			listBox
		]),
		E('div', { 'class': 'ncs-modal-row' }, [
			E('div', { 'class': 'lbl' }, [ '路径' ]),
			input
		]),
		E('div', { 'class': 'ncs-modal-row' }, [
			E('button', {
				'class': 'ncs-btn',
				'click': function() { fileInput.click(); }
			}, [ '上传文件…' ]),
			' ',
			note
		]),
		fileInput,
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
			' ',
			E('button', {
				'class': 'ncs-btn primary',
				'click': function() {
					ui.hideModal();
					onPick(String(input.value || '').trim());
				}
			}, [ '确定' ])
		])
	]);

	loadCandidates();
}

// Certificate path display / picker.
function fileField(label, value, filter) {
	var current = value || '';
	var btn = E('button', { 'class': 'ncs-filebtn' });

	function refresh() {
		if (!current) {
			btn.textContent = '选择文件…';
			btn.className = 'ncs-filebtn empty';
			return;
		}

		btn.className = 'ncs-filebtn';
		btn.textContent = current;

		fs.stat(current).then(function(st) {
			if (st && st.size != null)
				btn.textContent = current + ' (' + fmtSize(st.size) + ')';
		}).catch(function() {});
	}

	btn.addEventListener('click', function() {
		openPicker(label, filter, current, function(picked) {
			current = picked;
			refresh();
		});
	});

	refresh();

	return {
		host: btn,
		value: function() { return current; }
	};
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('nginx'),
			callHelper([ 'status' ]),
			listFragments(),
			probeWriteAccess()
		]);
	},

	render: function(data) {
		var status = data[1] || {};
		var servers = uci.sections('nginx', 'server') || [];
		var fragments = data[2] || [];
		// data[3] is the write probe: { known, canWrite }.  An unknown grant
		// counts as read-only, so the page never offers an action the backend
		// will refuse.
		var access = data[3] || {};
		var canWrite = access.canWrite === true;
		var accessUnknown = access.known === false;

		var activeTab = 'servers';            // 'servers' | 'fragments'
		var activeServer = servers.length ? servers[0]['.name'] : null;
		var activeFrag = fragments.length ? fragments[0].name : null;
		var editing = false;
		var lastLogSource = 'error';

		var tabHost = E('div');
		var subTabHost = E('div');
		var contentHost = E('div', { 'class': 'ncs-main' });

		// Rendering generation.  Tool views fetch asynchronously; switching
		// tabs while a fetch is in flight used to let the older answer paint
		// over the newer view.  Each paint takes a ticket and only the newest
		// ticket is allowed to write.
		var renderGen = 0;

		function nextGen() { return ++renderGen; }
		function isCurrent(gen) { return gen === renderGen; }
		var resultHost = E('div');
		var testBtn = E('button', { 'class': 'ncs-btn', 'click': function() { runTest(); } },
			[ '测试配置' ]);

		function findServer(name) {
			var found = null;
			servers.forEach(function(s) {
				if (s['.name'] === name)
					found = s;
			});
			return found;
		}

		function findFragment(name) {
			var found = null;
			fragments.forEach(function(f) {
				if (f.name === name)
					found = f;
			});
			return found;
		}

		function reloadAll() {
			uci.unload('nginx');
			return Promise.all([ uci.load('nginx'), listFragments() ]).then(function(res) {
				servers = uci.sections('nginx', 'server') || [];
				fragments = res[1] || [];
			});
		}

		// ------------------------------------------------------- 结果提示

		function renderResult(ok, title, note, output) {
			output = String(output == null ? '' : output).trim();

			dom.content(resultHost, E('div', {
				'class': 'ncs-result ' + (ok ? 'ok' : 'err')
			}, [
				E('div', { 'class': 'ncs-result-head' }, [
					E('span', { 'class': 't' }, [ title ]),
					note ? E('span', {
						'style': 'color:#8d8d8d;font-size:12px;font-family:Menlo,monospace'
					}, [ note ]) : '',
					E('span', { 'class': 'ncs-spacer' }),
					E('button', {
						'class': 'ncs-btn',
						'click': function() { resultHost.innerHTML = ''; }
					}, [ '关闭' ])
				]),
				output ? E('pre', { 'class': 'ncs-pre' }, [ output ]) : ''
			]));
		}

		function runTest() {
			if (testBtn.disabled)
				return;

			testBtn.disabled = true;
			testBtn.textContent = '测试中…';

			callHelper([ 'test' ]).then(function(r) {
				r = r || {};
				renderResult(!!r.ok, r.ok ? '配置语法正确' : '配置有错误', r.conf, r.output);
				testBtn.disabled = false;
				testBtn.textContent = '测试配置';
			});
		}

		// ------------------------------------------------------------ 标签页

		function tabButton(id, label, count) {
			return E('div', {
				'class': 'ncs-tab' + (activeTab === id ? ' on' : ''),
				'click': function() {
					if (activeTab === id)
						return;

					activeTab = id;
					editing = false;

					// Each fragment tab keeps its own selection: when the one
					// carried over from the previous tab is not in this kind,
					// pick the first of this kind instead of leaving nothing
					// highlighted.
					if (!TOOL_TABS[id] && id !== 'servers') {
						var list = visibleFragments(id);

						if (!list.some(function(f) { return f.name === activeFrag; }))
							activeFrag = list.length ? list[0].name : null;
					}

					renderAll();
				}
			}, [ label, count == null ? '' : E('span', { 'class': 'cnt' }, [ String(count) ]) ]);
		}

		function kindFragments(kind) {
			return fragments.filter(function(f) { return f.kind === kind; });
		}

		// Fragments that get their own chip.  The global http->https redirect is
		// driven by the checkbox instead, unless the user turned that file into
		// something else.
		function visibleFragments(kind) {
			return kindFragments(kind).filter(function(f) {
				if (f.name !== HTTPS_REDIRECT_FILE)
					return true;

				return !(isHttpsRedirect(f.content) || String(f.content || '').trim() === '');
			});
		}

		function renderHttpsRedirectCard() {
			var entry = findFragment(HTTPS_REDIRECT_FILE);
			var enabled = !!(entry && isHttpsRedirect(entry.content));
			var sw = toggleSwitch('将所有 HTTP 重定向到 HTTPS', enabled);
			var box = sw.inputs[0];
			var card = E('div', { 'class': 'ncs-global' }, [
				sw.el,
				E('p', { 'class': 'ncs-hint' }, [
					enabled ? '已启用，内容写在 ' : '勾选后会创建 ',
					E('code', {}, [ CONF_DIR + '/' + HTTPS_REDIRECT_FILE ]),
					'：',
					E('code', {}, [ HTTPS_REDIRECT_LINE ])
				])
			]);

			if (!canWrite)
				box.disabled = true;

			box.addEventListener('change', function() {
				if (box.disabled)
					return;

				box.disabled = true;

				// Enabling writes the line, disabling removes the file; the
				// checkbox is only ever on when the file holds exactly that
				// line, so neither direction can eat hand written content.
				var work = enabled
					? callHelper([ 'frag-delete', HTTPS_REDIRECT_FILE ])
					: stageAndCall(buildHttpsRedirect(), [ 'frag-save', HTTPS_REDIRECT_FILE ]);

				work.then(function(r) {
					r = r || {};

					if (!r.ok) {
						box.checked = enabled;
						box.disabled = false;
						renderResult(false, '操作失败', HTTPS_REDIRECT_FILE,
							errText(r) + (r.output ? '：' + String(r.output).trim() : ''));
						return;
					}

					return reloadAll().then(function() {
						renderAll();
						renderResult(true,
							enabled ? '已关闭 HTTP → HTTPS 跳转' : '已启用 HTTP → HTTPS 跳转',
							HTTPS_REDIRECT_FILE, '');
					});
				}).catch(function(e) {
					box.checked = enabled;
					box.disabled = false;
					renderResult(false, '操作失败', HTTPS_REDIRECT_FILE, (e && e.message) || String(e));
				});
			});

			return card;
		}

		function renderTopTabs() {
			var tabs = [ tabButton('servers', '服务器', servers.length) ];

			FRAG_KINDS.forEach(function(k) {
				var n = kindFragments(k.id).length;

				// "其他" only appears when something really is unclassified,
				// so a fragment never silently disappears from the page.
				if (k.id === 'other' && !n)
					return;

				tabs.push(tabButton(k.id, k.label, n));
			});

			tabs.push(tabButton('logs', '日志', null));
			tabs.push(tabButton('certs', '证书', null));
			tabs.push(tabButton('backups', '备份', null));
			tabs.push(tabButton('auth', '访问', null));
			tabs.push(tabButton('audit', '体检', null));

			dom.content(tabHost, E('div', { 'class': 'ncs-tabs' }, tabs));
		}

		// Second level: one chip per server section / fragment file.
		function renderSubTabs() {
			if (TOOL_TABS[activeTab]) {
				dom.content(subTabHost, '');
				return;
			}

			if (activeTab === 'servers') {
				var secChips = servers.map(function(sec) {
					var name = sec['.name'];

					return E('div', {
						'class': 'ncs-subtab' + (name === activeServer ? ' on' : ''),
						'click': function() {
							if (name === activeServer)
								return;
							activeServer = name;
							editing = false;
							renderAll();
						}
					}, [
						E('span', { 'title': 'nginx.' + name }, [ serverLabel(name) ]),
						SYSTEM_SECTIONS[name] ? E('span', { 'class': 'ncs-sys' }, [ '系统' ]) : '',
						E('span', { 'class': 'cnt', 'style': 'color:#6f6f6f;font-size:12px' },
							[ portsOf(sec) ])
					]);
				});

				if (canWrite)
					secChips.push(E('div', {
						'class': 'ncs-subtab ncs-subtab-add',
						'click': openNewServer
					}, [ '+ 新建服务器' ]));

				dom.content(subTabHost, E('div', { 'class': 'ncs-subtabs' }, secChips));

				return;
			}

			var chips = visibleFragments(activeTab).map(function(f) {
				return E('div', {
					'class': 'ncs-subtab' + (f.name === activeFrag ? ' on' : ''),
					'click': function() {
						if (f.name === activeFrag)
							return;
						activeFrag = f.name;
						editing = false;
						renderAll();
					}
				}, [ E('span', {}, [ f.name ]) ]);
			});

			if (canWrite)
				chips.push(E('div', {
					'class': 'ncs-subtab ncs-subtab-add',
					'click': openNewFragment
				}, [ activeTab === 'proxy' ? '+ 新建反向代理' : '+ 新建片段' ]));

			var parts = [];

			if (activeTab === 'redirect')
				parts.push(renderHttpsRedirectCard());

			parts.push(E('div', { 'class': 'ncs-subtabs' }, chips));

			dom.content(subTabHost, E('div', {}, parts));
		}

		function renderContent() {
			if (TOOL_TABS[activeTab]) {
				renderTool(activeTab);
				return;
			}

			if (activeTab === 'servers') {
				var sec = findServer(activeServer);

				if (!sec) {
					dom.content(contentHost, E('div', { 'class': 'top' }, [ '还没有 server 段' ]));
					return;
				}

				if (editing)
					renderServerEdit(activeServer, sec);
				else
					renderServerReadonly(activeServer, sec);

				return;
			}

			var entry = findFragment(activeFrag);

			if (!entry) {
				dom.content(contentHost, E('div', { 'class': 'top' }, [
					activeTab === 'redirect'
						? '还没有路径级重定向片段；全局的 HTTP → HTTPS 跳转由上面的勾选框管理。'
						: '这个分类下还没有片段，用上面的按钮新建一个。'
				]));
				return;
			}

			// The three structured kinds fall back to the text editor when the
			// file is not a single simple location block, so hand written
			// content is never silently replaced by generated content.
			if (activeTab === 'proxy') {
				if (editing)
					renderProxyEdit(entry);
				else
					renderProxyReadonly(entry);

				return;
			}

			if (activeTab === 'forward' || activeTab === 'redirect') {
				var spec = simpleSpec(activeTab);
				var parsed = spec.parse(entry.content);

				if (!parsed) {
					if (editing)
						renderFragEdit(entry);
					else
						renderFragReadonly(entry,
							'这个片段不是简单的「单 location + ' + spec.title +
							'」，所以按原文展示，编辑走文本编辑器。');
					return;
				}

				if (editing)
					renderSimpleEdit(entry, spec, parsed);
				else
					renderSimpleReadonly(entry, spec, parsed);

				return;
			}

			if (editing)
				renderFragEdit(entry);
			else
				renderFragReadonly(entry);
		}

		function renderAll() {
			renderTopTabs();
			renderSubTabs();
			renderContent();
		}

		// ------------------------------------------------------- server 详情

		function renderServerReadonly(name, sec) {
			var certCell = readField('证书', 'ssl_certificate', sec.ssl_certificate, { sizeOf: true });
			var keyCell = readField('私钥', 'ssl_certificate_key', sec.ssl_certificate_key, { sizeOf: true });

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ serverLabel(name) ]),
					SYSTEM_SECTIONS[name] ? E('span', { 'class': 'ncs-badge' }, [ '系统' ]) : '',
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ 'nginx.' + name ]),
					name === '_lan' ? '' : (canWrite ? E('button', {
						'class': 'ncs-btn danger',
						'click': function() { askDeleteServer(name); }
					}, [ '删除' ]) : ''),
					canWrite ? E('button', {
						'class': 'ncs-btn',
						'click': function() { editing = true; renderContent(); }
					}, [ '编辑' ]) : ''
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '常规设置' ]),
					readField('监听', 'listen', sec.listen),
					readField('服务器名', 'server_name', sec.server_name)
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '证书与 SSL' ]),
					readField('管理方式', 'uci_manage_ssl', sec.uci_manage_ssl),
					certCell,
					keyCell,
					readField('会话缓存', 'ssl_session_cache', sec.ssl_session_cache),
					readField('会话超时', 'ssl_session_timeout', sec.ssl_session_timeout)
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '高级设置' ]),
					readField('包含', 'include', sec.include),
					readField('访问日志', 'access_log', sec.access_log),
					readField('错误日志', 'error_log', sec.error_log)
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '安全与限流' ]),
					readField('响应头', 'add_header', asList(sec.add_header)),
					readField('版本号', 'server_tokens', sec.server_tokens),
					readField('请求限速', 'limit_req', sec.limit_req),
					readField('并发连接', 'limit_conn', sec.limit_conn)
				])
			]);

			decorateSize(certCell, sec.ssl_certificate);
			decorateSize(keyCell, sec.ssl_certificate_key);
		}

		function editField(label, directive, editor) {
			return E('div', { 'class': 'ncs-field' }, [
				E('div', { 'class': 'ncs-lbl' }, [ label, E('span', { 'class': 'd' }, [ directive ]) ]),
				E('div', { 'class': 'ncs-val' }, editor.addBtn ? [ editor.host, editor.addBtn ] : [ editor.host ])
			]);
		}

		function renderServerEdit(name, sec) {
			var listenEd = listEditor(sec.listen);
			var includeEd = listEditor(sec.include);
			var certEd = fileField('选择证书', sec.ssl_certificate, isCertFile);
			var keyEd = fileField('选择私钥', sec.ssl_certificate_key, isKeyFile);
			var nameInput = E('input', { 'class': 'ncs-input', 'value': sec.server_name || '' });
			var accessLogInput = E('input', {
				'class': 'ncs-input',
				'value': sec.access_log || '',
				'placeholder': 'logd openwrt'
			});
			var errorLogInput = E('input', {
				'class': 'ncs-input',
				'value': sec.error_log || '',
				'placeholder': 'logd'
			});

			// --- security headers, kept as an add_header list -------------
			var headerValues = asList(sec.add_header);
			var headerSwitches = SECURITY_HEADERS.map(function(h) {
				return {
					spec: h,
					sw: toggleSwitch(h.label, headerValues.some(function(v) {
						return isHeaderNamed(v, h.name);
					}))
				};
			});

			// Anything already there that the checkboxes do not model stays
			// visible and editable, so a save never drops it silently.
			var extraHeaders = headerValues.filter(function(v) {
				return !SECURITY_HEADERS.some(function(h) { return isHeaderNamed(v, h.name); });
			});
			var extraHeaderBox = E('textarea', {
				'class': 'ncs-frag-edit',
				'style': 'min-height:52px',
				'spellcheck': 'false',
				'placeholder': '每行一条 add_header，例如 X-Custom "v" always'
			}, [ extraHeaders.join('\n') ]);

			// --- server_tokens -------------------------------------------
			var tokensSwitch = toggleSwitch('隐藏 nginx 版本号（server_tokens off）',
				sec.server_tokens === 'off');

			// --- rate limiting -------------------------------------------
			// The rates come from the zones in conf.d/nginx-console-limits.conf.
			// There are only a few of them, so they are shown side by side
			// instead of hidden in a dropdown.
			var rateOptions = [ { value: '', label: '不限速' } ].concat(RATE_LIMITS.map(function(r) {
				return {
					value: 'zone=' + r.zone + ' burst=' + r.burst + ' nodelay',
					label: r.label
				};
			}));

			if (sec.limit_req && !rateOptions.some(function(o) { return o.value === sec.limit_req; }))
				rateOptions.push({ value: sec.limit_req, label: '自定义' });

			var limitReqSeg = segmented(rateOptions, sec.limit_req || '');

			// limit_conn needs a zone name too; the console owns ncs_cl.
			var CONN_LIMITS = [
				{ value: '', label: '不限' },
				{ value: '10', label: '10' },
				{ value: '20', label: '20' },
				{ value: '50', label: '50' },
				{ value: '100', label: '100' },
				{ value: '200', label: '200' },
				{ value: '500', label: '500' }
			];
			// Only a value that already uses the zone this console owns can be
			// edited here.  A hand written foreign zone is shown as-is and
			// left alone: rewriting it to ncs_cl would silently change which
			// zone is policed.
			var connValue = String(sec.limit_conn || '').trim();
			var connOwnZone = connValue === '' || /^ncs_cl\s+/.test(connValue);
			var connRaw = connOwnZone ? connValue.replace(/^ncs_cl\s+/, '') : '';
			var connSlider = valueSlider(CONN_LIMITS, connRaw, { empty: '不限' });

			function collectHeaders() {
				var out = [];

				headerSwitches.forEach(function(h) {
					if (h.sw.value())
						out.push(h.spec.value);
				});

				String(extraHeaderBox.value || '').split('\n').forEach(function(line) {
					line = line.trim();
					if (line)
						out.push(line);
				});

				return out;
			}
			var saveBtn = E('button', { 'class': 'ncs-btn primary' }, [ '保存并应用' ]);
			var cancelBtn = E('button', {
				'class': 'ncs-btn',
				'click': function() { editing = false; renderContent(); }
			}, [ '取消' ]);

			saveBtn.addEventListener('click', function() {
				if (saveBtn.disabled)
					return;

				saveBtn.disabled = true;
				cancelBtn.disabled = true;
				saveBtn.textContent = '保存中…';

				var lines = [];

				// listen, then server_name, then include, then the certificates:
				// the order a section is normally written in.  Every field is
				// staged, so a list the user emptied is written as an empty
				// value on purpose - the backend only touches the fields that
				// are in the staged file.
				function stageList(field, values) {
					if (!values.length) {
						lines.push(field + '\t');
						return;
					}

					values.forEach(function(v) { lines.push(field + '\t' + v); });
				}

				stageList('listen', listenEd.values());
				lines.push('server_name\t' + String(nameInput.value || '').trim().replace(/\t/g, ' '));
				stageList('include', includeEd.values());
				lines.push('ssl_certificate\t' + certEd.value().replace(/\t/g, ' '));
				lines.push('ssl_certificate_key\t' + keyEd.value().replace(/\t/g, ' '));
				lines.push('access_log\t' + String(accessLogInput.value || '').trim().replace(/\t/g, ' '));
				lines.push('error_log\t' + String(errorLogInput.value || '').trim().replace(/\t/g, ' '));

				stageList('add_header', collectHeaders());
				lines.push('server_tokens\t' + (tokensSwitch.value() ? 'off' : ''));

				lines.push('limit_req\t' + String(limitReqSeg.value() || ''));

				var connNum = connSlider.value().replace(/[^0-9]/g, '');

				// A foreign zone is not modelled: it is carried through
				// unchanged instead of being rewritten to ncs_cl.
				if (!connOwnZone)
					lines.push('limit_conn\t' + connValue);
				else
					lines.push('limit_conn\t' + (connNum ? 'ncs_cl ' + connNum : ''));

				stageAndCall(lines.join('\n') + '\n', [ 'server-save', name ])
					.then(function(r) {
						r = r || {};

						if (r.ok) {
							editing = false;
							return reloadAll().then(function() {
								renderAll();
								renderResult(true, '已保存并应用', name, '');
							});
						}

						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						saveBtn.textContent = '保存并应用';

						var detail = (r.error === 'guard_failed')
							? String(r.output || '')
							: errText(r) +
								(r.output ? '\n' + String(r.output).trim() : '');

						return reloadAll().then(function() {
							renderAll();
							renderResult(false, '保存失败', name, detail);
						});
					})
					.catch(function(e) {
						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						saveBtn.textContent = '保存并应用';
						renderResult(false, '保存失败', name, (e && e.message) || String(e));
					});
			});

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ serverLabel(name) ]),
					SYSTEM_SECTIONS[name] ? E('span', { 'class': 'ncs-badge' }, [ '系统' ]) : '',
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ 'nginx.' + name ]),
					cancelBtn,
					saveBtn
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '常规设置' ]),
					editField('监听', 'listen', listenEd),
					editField('服务器名', 'server_name', { host: nameInput }),
					E('p', { 'class': 'ncs-hint' }, [
						'监听里含 443 或 ssl 时，必须保留完整的证书配置，否则保存会被拦下。'
					])
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '证书与 SSL' ]),
					readField('管理方式', 'uci_manage_ssl', sec.uci_manage_ssl),
					editField('证书', 'ssl_certificate', certEd),
					editField('私钥', 'ssl_certificate_key', keyEd),
					E('p', { 'class': 'ncs-hint' }, [
						'点字段可以浏览 ' + CERT_DIRS.join('、') + ' 或上传新文件（PEM 文本格式）。'
					])
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '高级设置' ]),
					editField('包含', 'include', includeEd),
					editField('访问日志', 'access_log', { host: accessLogInput }),
					editField('错误日志', 'error_log', { host: errorLogInput }),
					E('p', { 'class': 'ncs-hint' }, [
						'值以 logd 开头时，nginx-util 会把它换成 stderr（access_log）或 /proc/self/fd/1（error_log）。'
					])
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '安全与限流' ]),
					editField('响应头', 'add_header', {
						host: E('div', { 'class': 'ncs-switchlist' }, headerSwitches.map(function(h) {
							return h.sw.el;
						}).concat([ extraHeaderBox ]))
					}),
					editField('版本号', 'server_tokens', { host: tokensSwitch.el }),
					editField('请求限速', 'limit_req', { host: limitReqSeg.el }),
					editField('并发连接', 'limit_conn', { host: connSlider.el }),
					E('p', { 'class': 'ncs-hint' }, [
						'限速用的 zone 定义在 conf.d/nginx-console-limits.conf 里，要改速率改那个文件。'
					])
				])
			]);
		}

		// ------------------------------------------------------- 片段详情

		function renderFragReadonly(entry, note) {
			fs.read(CONF_DIR + '/' + entry.name).then(function(content) {
				dom.content(contentHost, [
					E('div', { 'class': 'top' }, [
						E('span', { 'class': 't' }, [ entry.name ]),
						E('span', { 'class': 'ncs-spacer' }),
						E('span', { 'class': 'meta' }, [
							fmtSize(entry.size) + '　' + fmtTime(entry.mtime)
						]),
						canWrite ? E('button', {
							'class': 'ncs-btn',
							'click': function() { editing = true; renderContent(); }
						}, [ '编辑' ]) : '',
						canWrite ? E('button', {
							'class': 'ncs-btn danger',
							'click': function() { askDeleteFragment(entry.name); }
						}, [ '删除' ]) : ''
					]),
					E('div', { 'class': 'ncs-sec' }, [
						note ? E('p', { 'class': 'ncs-hint' }, [ note ]) : '',
						E('pre', { 'class': 'ncs-frag' }, [ String(content || '') ])
					])
				]);
			}).catch(function(e) {
				dom.content(contentHost, E('div', { 'class': 'top' }, [
					'无法读取 ' + entry.name + '：' + ((e && e.message) || e)
				]));
			});
		}

		function renderFragEdit(entry) {
			var content = '';

			var area = E('textarea', {
				'class': 'ncs-frag-edit',
				'spellcheck': 'false',
				'wrap': 'off'
			}, [ '' ]);
			var saveBtn = E('button', { 'class': 'ncs-btn primary' }, [ '保存并应用' ]);
			var cancelBtn = E('button', {
				'class': 'ncs-btn',
				'click': function() { editing = false; renderContent(); }
			}, [ '取消' ]);
			var deleteBtn = E('button', {
				'class': 'ncs-btn danger',
				'click': function() { askDeleteFragment(entry.name); }
			}, [ '删除' ]);

			saveBtn.addEventListener('click', function() {
				if (saveBtn.disabled)
					return;

				saveBtn.disabled = true;
				cancelBtn.disabled = true;
				deleteBtn.disabled = true;
				saveBtn.textContent = '保存中…';

				stageAndCall(area.value, [ 'frag-save', entry.name ])
					.then(function(r) {
						r = r || {};

						if (r.ok) {
							editing = false;
							return reloadAll().then(function() {
								renderAll();
								renderResult(true, '已保存并应用', entry.name, '');
							});
						}

						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						deleteBtn.disabled = false;
						saveBtn.textContent = '保存并应用';

						return reloadAll().then(function() {
							renderAll();
							renderResult(false, '保存失败', entry.name,
								errText(r) + (r.output ? '\n' + String(r.output).trim() : ''));
						});
					})
					.catch(function(e) {
						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						deleteBtn.disabled = false;
						saveBtn.textContent = '保存并应用';
						renderResult(false, '保存失败', entry.name, (e && e.message) || String(e));
					});
			});

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ entry.name ]),
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ CONF_DIR ]),
					deleteBtn,
					cancelBtn,
					saveBtn
				]),
				E('div', { 'class': 'ncs-sec' }, [
					area,
					E('p', { 'class': 'ncs-hint' }, [
						'片段由 _lan / _redirect2ssl 的 include conf.d/*.locations 引入。' +
						'保存时会先备份，再跑 nginx -t，失败自动回滚。'
					])
				])
			]);

			fs.read(CONF_DIR + '/' + entry.name).then(function(c) {
				content = String(c || '');
				area.value = content;
			}).catch(function() {
				area.value = '';
			});
		}

		// --------------------------------------------------- 反向代理的结构化表单

		// Built once and used by both the modal (new proxy) and the inline
		// editor (existing proxy).
		function proxyFormFields(initial) {
			initial = initial || {};

			function input(value, placeholder) {
				return E('input', {
					'class': 'ncs-input',
					'value': value || '',
					'placeholder': placeholder
				});
			}

			// The steps the timeout slider walks through.  A timeout that is not
			// on the list keeps its own value until the slider is used.
			var TIMEOUTS = [
				{ value: '', label: '不设置' },
				{ value: '5s', label: '5 秒' },
				{ value: '15s', label: '15 秒' },
				{ value: '30s', label: '30 秒' },
				{ value: '60s', label: '60 秒' },
				{ value: '120s', label: '2 分钟' },
				{ value: '300s', label: '5 分钟' }
			];

			var pathIn = input(initial.path, '/ttyd/');
			var targetIn = input(initial.target, 'http://127.0.0.1:7681/');
			var connSlider = valueSlider(TIMEOUTS, String(initial.connectTimeout || ''), { empty: '不设置' });
			var sendSlider = valueSlider(TIMEOUTS, String(initial.sendTimeout || ''), { empty: '不设置' });
			var readSlider = valueSlider(TIMEOUTS, String(initial.readTimeout || ''), { empty: '不设置' });
			var wsSwitch = toggleSwitch(
				'WebSocket（自动补 Upgrade / Connection / http_version 1.1）',
				initial.websocket
			);
			var extraIn = E('textarea', {
				'class': 'ncs-frag-edit',
				'style': 'min-height:64px',
				'spellcheck': 'false',
				'placeholder': '每行一条额外指令，例如 proxy_buffering off;'
			}, [ String(initial.extra || '') ]);

			// The lines the WebSocket switch owns are not editable here, but they
			// are kept: the user should know that they are there.
			var wsHint = (initial.wsLines && initial.wsLines.length)
				? E('p', { 'class': 'ncs-hint' }, [
					'随这个开关一起保留的指令：' + initial.wsLines.join('、')
				])
				: '';

			function row(label, directive, cell) {
				return E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [
						label,
						directive ? E('span', { 'class': 'd' }, [ directive ]) : ''
					]),
					E('div', { 'class': 'ncs-val' }, [ cell ])
				]);
			}

			var host = E('div', {}, [
				row('路径', 'location', pathIn),
				row('后端地址', 'proxy_pass', targetIn),
				row('选项', '', E('div', {}, [ wsSwitch.el, wsHint ])),
				row('连接超时', 'proxy_connect_timeout', connSlider.el),
				row('发送超时', 'proxy_send_timeout', sendSlider.el),
				row('读超时', 'proxy_read_timeout', readSlider.el),
				row('额外指令', '每行一条', extraIn)
			]);

			return {
				host: host,
				inputs: [ pathIn, targetIn, extraIn ]
					.concat(connSlider.inputs, sendSlider.inputs, readSlider.inputs, wsSwitch.inputs),
				values: function() {
					return {
						path: String(pathIn.value || '').trim(),
						target: String(targetIn.value || '').trim(),
						websocket: wsSwitch.value(),
						connectTimeout: connSlider.value(),
						sendTimeout: sendSlider.value(),
						readTimeout: readSlider.value(),
						extra: extraIn.value,
						wsLines: initial.wsLines || [],
						head: initial.head || '',
						tail: initial.tail || ''
					};
				}
			};
		}

		function proxyFormProblem(v) {
			if (!v.path)
				return '路径不能为空，例如 /ttyd/';
			if (v.path.charAt(0) !== '/')
				return '路径要以 / 开头';
			if (!v.target)
				return '后端地址不能为空，例如 http://127.0.0.1:7681/';
			if (!/^(https?:\/\/|\/)/.test(v.target))
				return '后端地址要以 http:// 或 https:// 开头';

			return null;
		}

		// ------------------------------------------- 重定向 / 转发的结构化表单

		// Both kinds are "one location block with one directive", so they share
		// the same form machinery and only differ in their spec.
		function simpleSpec(kind) {
			if (kind === 'redirect') {
				return {
					title: '重定向',
					parse: parseRedirectFragment,
					build: buildRedirectFragment,
					fields: [
						{ key: 'path', label: '路径', directive: 'location', placeholder: '/old/' },
						{ key: 'code', label: '状态码', directive: 'return', type: 'select', options: [
							{ value: '301', label: '301 永久' },
							{ value: '302', label: '302 临时' },
							{ value: '307', label: '307 临时（保留请求方法）' },
							{ value: '308', label: '308 永久（保留请求方法）' }
						] },
						{ key: 'target', label: '目标地址', placeholder: 'https://example.com/new/' },
						{ key: 'extra', label: '额外指令', directive: '每行一条', type: 'textarea',
						  placeholder: '每行一条额外指令，例如 default_type application/json;' }
					],
					problem: function(v) {
						if (!v.path)
							return '路径不能为空，例如 /old/';
						if (v.path.charAt(0) !== '/')
							return '路径要以 / 开头';
						if (!v.target)
							return '目标地址不能为空';
						return null;
					},
					rows: function(v) {
						return [
							[ '路径', 'location', v.path ],
							[ '状态码', 'return', v.code ],
							[ '目标地址', '', v.target ]
						];
					}
				};
			}

			return {
				title: '转发',
				parse: parseForwardFragment,
				build: buildForwardFragment,
				fields: [
					{ key: 'path', label: '路径', directive: 'location', placeholder: '/cgi-bin/app' },
					{ key: 'proto', label: '协议', directive: 'xxx_pass', type: 'select', options:
						FORWARD_PROTOS.map(function(p) { return { value: p.value, label: p.label }; }) },
					{ key: 'target', label: '后端', placeholder: 'unix:///var/run/app.sock 或 127.0.0.1:9000' },
					{ key: 'include', label: '包含', directive: 'include', placeholder: 'uwsgi_params' },
					{ key: 'extra', label: '额外指令', directive: '每行一条', type: 'textarea',
					  placeholder: '每行一条额外指令，例如 client_max_body_size 8m;' }
				],
				problem: function(v) {
					if (!v.path)
						return '路径不能为空，例如 /cgi-bin/app';
					if (v.path.charAt(0) !== '/')
						return '路径要以 / 开头';
					if (!v.target)
						return '后端地址不能为空';
					return null;
				},
				rows: function(v) {
					return [
						[ '路径', 'location', v.path ],
						[ '协议', v.proto + '_pass', v.proto ],
						[ '后端', '', v.target ]
					];
				}
			};
		}

		function simpleFormFields(fields, initial) {
			var controls = {};

			var host = E('div', {}, fields.map(function(f) {
				var el;

				if (f.type === 'select') {
					el = E('select', { 'class': 'ncs-input' }, f.options.map(function(o) {
						return E('option', { 'value': o.value }, [ o.label ]);
					}));
				} else if (f.type === 'textarea') {
					el = E('textarea', {
						'class': 'ncs-frag-edit',
						'style': 'min-height:64px',
						'spellcheck': 'false',
						'placeholder': f.placeholder || ''
					}, [ '' ]);
				} else {
					el = E('input', { 'class': 'ncs-input', 'placeholder': f.placeholder || '' });
				}

				if (initial && initial[f.key] != null)
					el.value = initial[f.key];

				controls[f.key] = el;

				return E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [
						f.label,
						f.directive ? E('span', { 'class': 'd' }, [ f.directive ]) : ''
					]),
					E('div', { 'class': 'ncs-val' }, [ el ])
				]);
			}));

			return {
				host: host,
				inputs: Object.keys(controls).map(function(k) { return controls[k]; }),
				values: function() {
					var out = {};

					// The parts of the fragment the form does not show are
					// carried over from the parsed file, so that a save does
					// not drop them.
					[ 'extra', 'head', 'tail', 'include' ].forEach(function(k) {
						if (initial && initial[k] != null)
							out[k] = initial[k];
					});

					Object.keys(controls).forEach(function(k) {
						out[k] = String(controls[k].value || '').trim();
					});

					return out;
				}
			};
		}

		// Saving a fragment is the same for every kind: stage it, let the
		// backend install + test + roll back, then reload what is on disk.
		function saveFragmentWith(entry, content, saveBtn, cancelBtn, feedback) {
			saveBtn.disabled = true;
			cancelBtn.disabled = true;
			saveBtn.textContent = '保存中…';

			stageAndCall(content, [ 'frag-save', entry.name ])
				.then(function(r) {
					r = r || {};

					if (r.ok) {
						editing = false;
						return reloadAll().then(function() {
							renderAll();
							renderResult(true, '已保存并应用', entry.name, '');
						});
					}

					saveBtn.disabled = false;
					cancelBtn.disabled = false;
					saveBtn.textContent = '保存并应用';
					feedback.style.display = '';
					feedback.textContent = errText(r) +
						(r.output ? '：' + String(r.output).trim() : '');

					return reloadAll().then(function() { renderAll(); });
				})
				.catch(function(e) {
					saveBtn.disabled = false;
					cancelBtn.disabled = false;
					saveBtn.textContent = '保存并应用';
					feedback.style.display = '';
					feedback.textContent = (e && e.message) || String(e);
				});
		}

		function renderSimpleReadonly(entry, spec, parsed) {
			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ entry.name ]),
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ fmtSize(entry.size) + '　' + fmtTime(entry.mtime) ]),
					E('button', {
						'class': 'ncs-btn',
						'click': function() { editing = true; renderContent(); }
					}, [ '编辑' ]),
					E('button', {
						'class': 'ncs-btn danger',
						'click': function() { askDeleteFragment(entry.name); }
					}, [ '删除' ])
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ spec.title ]),
					E('div', {}, spec.rows(parsed).map(function(r) {
						return readField(r[0], r[1], r[2]);
					}))
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '生成的配置' ]),
					E('pre', { 'class': 'ncs-frag' }, [ entry.content ])
				])
			]);
		}

		function renderSimpleEdit(entry, spec, parsed) {
			var form = simpleFormFields(spec.fields, parsed);
			var preview = E('pre', { 'class': 'ncs-frag' }, [ '' ]);
			var feedback = E('p', { 'class': 'ncs-hint', 'style': 'display:none;color:#e08585' }, [ '' ]);
			var saveBtn = E('button', { 'class': 'ncs-btn primary' }, [ '保存并应用' ]);
			var cancelBtn = E('button', {
				'class': 'ncs-btn',
				'click': function() { editing = false; renderContent(); }
			}, [ '取消' ]);

			function refreshPreview() {
				var v = form.values();

				preview.textContent = spec.problem(v)
					? '（填好必填项后，这里显示将要写入的配置）'
					: spec.build(v);
			}

			form.inputs.forEach(function(el) {
				el.addEventListener('input', refreshPreview);
				el.addEventListener('change', refreshPreview);
			});
			refreshPreview();

			saveBtn.addEventListener('click', function() {
				var v = form.values();
				var problem = spec.problem(v);

				if (problem) {
					feedback.style.display = '';
					feedback.textContent = problem;
					return;
				}

				feedback.style.display = 'none';
				saveFragmentWith(entry, spec.build(v), saveBtn, cancelBtn, feedback);
			});

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ entry.name ]),
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ CONF_DIR ]),
					cancelBtn,
					saveBtn
				]),
				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ spec.title ]),
					form.host,
					feedback,
					E('p', { 'class': 'ncs-hint' }, [
						'保存时会重新生成整个片段文件；表单没覆盖的指令和注释会原样保留，' +
						'结构超出表单的片段请用文本编辑器。'
					])
				]),
				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '将要写入' ]),
					preview
				])
			]);
		}

		// ---------------------------------------------------- 工具标签页的视图

		function toolHeader(title, subtitle, actions) {
			return E('div', { 'class': 'top' }, [
				E('span', { 'class': 't' }, [ title ]),
				subtitle ? E('span', { 'class': 'meta' }, [ subtitle ]) : '',
				E('span', { 'class': 'ncs-spacer' })
			].concat(actions || []));
		}

		function toolShell(title, subtitle, actions, body) {
			dom.content(contentHost, E('div', { 'class': 'ncs-main' }, [
				toolHeader(title, subtitle, actions),
				E('div', { 'class': 'ncs-sec' }, [ body ])
			]));
		}

		function toolLoading(title) {
			toolShell(title, '', [], E('p', { 'class': 'ncs-hint' }, [ '读取中…' ]));
		}

		function toolError(title, r) {
			toolShell(title, '', [], E('p', { 'class': 'ncs-hint', 'style': 'color:#e08585' }, [
				'读取失败：' + errText(r || {}) + (r && r.output ? '：' + String(r.output).trim() : '')
			]));
		}

		function renderTool(id) {
			// Every tool view fetches asynchronously.  The ticket is taken here
			// so a late answer from a view the user already left can tell it is
			// stale and drop itself instead of painting over the current one.
			var gen = nextGen();

			if (id === 'logs')
				renderLogsView(lastLogSource, gen);
			else if (id === 'certs')
				renderCertsView(gen);
			else if (id === 'backups')
				renderBackupsView(gen);
			else if (id === 'auth')
				renderAuthView(gen);
			else
				renderAuditView(gen);
		}

		// ---- 日志

		function renderLogsView(which, gen) {
			which = which || 'error';
			lastLogSource = which;

			toolLoading('日志');

			callHelper([ 'logs', which, String(LOG_LINES) ]).then(function(r) {
				if (gen != null && !isCurrent(gen))
					return;

				r = r || {};

				if (r.ok === false) {
					toolError('日志', r);
					return;
				}

				var content = String(r.content || '');

				function switchBtn(id, label) {
					return E('button', {
						'class': 'ncs-btn' + (which === id ? ' primary' : ''),
						'click': function() { renderLogsView(id); }
					}, [ label ]);
				}

				toolShell('日志', 'nginx 的日志走 syslog，这里读的是 logread', [
					switchBtn('error', '错误日志'),
					switchBtn('access', '访问日志'),
					E('button', { 'class': 'ncs-btn', 'click': function() { renderLogsView(which); } }, [ '刷新' ])
				], content
					? E('pre', { 'class': 'ncs-frag', 'style': 'max-height:62vh;overflow:auto' }, [ content ])
					: E('p', { 'class': 'ncs-hint' }, [
						which === 'error'
							? '没有错误日志。'
							: '没有访问日志。nginx 默认 access_log off；在服务器段的「访问日志」里填上 logd openwrt 才会记录。'
					]));
			});
		}

		// ---- 证书

		function renderCertsView(gen) {
			toolLoading('证书');

			callHelper([ 'certs' ]).then(function(r) {
				if (gen != null && !isCurrent(gen))
					return;

				r = r || {};

				if (r.ok === false) {
					toolError('证书', r);
					return;
				}

				// acme keeps the same certificate as .crt / .combined.crt /
				// .fullchain.crt: show the identity once and list the paths.
				var grouped = [];

				(r.certificates || []).forEach(function(c) {
					var key = c.subject + '|' + c.not_after;
					var hit = null;

					for (var i = 0; i < grouped.length; i++) {
						if (grouped[i].key === key) {
							hit = grouped[i];
							break;
						}
					}

					if (!hit) {
						hit = {
							key: key, subject: c.subject, not_after: c.not_after,
							days_left: c.days_left, sans: c.sans, paths: []
						};
						grouped.push(hit);
					}

					hit.paths.push(c.path);
				});

				grouped.sort(function(a, b) { return a.days_left - b.days_left; });

				toolShell('证书', '扫描 /etc/ssl/acme 与 /etc/nginx/certs', [
					E('button', { 'class': 'ncs-btn', 'click': renderCertsView }, [ '刷新' ])
				], grouped.length ? E('div', {}, grouped.map(function(g) {
					var cls = g.days_left < 7 ? 'bad' : (g.days_left < 30 ? 'warn' : 'ok');

					return E('div', { 'class': 'ncs-cert ' + cls }, [
						E('div', { 'class': 'row' }, [
							E('span', { 'class': 'cn' }, [ g.sans || g.subject ]),
							E('span', { 'class': 'days' }, [
								g.days_left > 0 ? ('剩余 ' + g.days_left + ' 天') : '已过期'
							])
						]),
						E('div', { 'class': 'sub' }, [ '到期 ' + g.not_after + '　' + g.subject ]),
						E('div', { 'class': 'sub mono' }, g.paths.map(function(p) {
							return E('div', {}, [ p ]);
						}))
					]);
				})) : E('p', { 'class': 'ncs-hint' }, [ '没有找到证书。' ]));
			});
		}

		// ---- 备份

		function renderBackupsView(gen) {
			toolLoading('备份');

			callHelper([ 'backups', 'list' ]).then(function(r) {
				if (gen != null && !isCurrent(gen))
					return;

				r = r || {};

				if (r.ok === false) {
					toolError('备份', r);
					return;
				}

				var items = r.backups || [];

				function group(kind, title, dir) {
					var rows = items.filter(function(b) { return b.kind === kind; });

					return [
						E('h3', {}, [ title ]),
						dir ? E('p', { 'class': 'ncs-hint mono' }, [ dir ]) : '',
						rows.length ? E('div', {}, rows.map(function(b) {
							return E('div', { 'class': 'ncs-row' }, [
								E('span', { 'class': 'when mono' }, [ b.time || '' ]),
								E('span', { 'class': 'nm mono' }, [ b.name ]),
								E('span', { 'class': 'sz' }, [ fmtSize(b.size) ]),
								canWrite ? E('button', {
									'class': 'ncs-btn',
									'click': function() { askRestore(b); }
								}, [ '恢复' ]) : ''
							]);
						})) : E('p', { 'class': 'ncs-hint' }, [ '还没有备份。每次保存都会自动生成一份。' ])
					];
				}

				dom.content(contentHost, E('div', { 'class': 'ncs-main' }, [
					toolHeader('备份', '每次保存前自动生成，各保留最近 10 份', [
						E('button', { 'class': 'ncs-btn', 'click': renderBackupsView }, [ '刷新' ])
					]),
					E('div', { 'class': 'ncs-sec' }, group('uci', 'UCI 配置', r.uci_dir)),
					E('div', { 'class': 'ncs-sec' }, group('fragment', '片段文件', r.frag_dir))
				]));
			});
		}

		function askRestore(b) {
			var btn = E('button', { 'class': 'ncs-btn primary' }, [ '恢复' ]);

			btn.addEventListener('click', function() {
				btn.disabled = true;
				btn.textContent = '恢复中…';

				callHelper([ 'backup-restore', b.path ]).then(function(r) {
					ui.hideModal();
					r = r || {};

					if (r.ok)
						renderResult(true, '已从备份恢复', b.name, '');
					else
						renderResult(false, '恢复失败', b.name,
							errText(r) + (r.output ? '：' + String(r.output).trim() : ''));

					return reloadAll().then(function() {
						renderAll();
						renderBackupsView();
					});
				});
			});

			ui.showModal('恢复备份', [
				E('p', {}, [ '用这份备份覆盖当前配置？' ]),
				E('p', { 'class': 'ncs-hint mono' }, [ b.name + '　' + (b.time || '') ]),
				E('p', { 'class': 'ncs-hint' }, [
					'恢复前会先把当前状态另存一份，而且只有通过 nginx -t 才会真正生效。'
				]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					btn
				])
			]);
		}

		// ---- 访问控制（htpasswd）

		function renderAuthView(gen) {
			toolLoading('访问控制');

			callHelper([ 'auth', 'list' ]).then(function(r) {
				if (gen != null && !isCurrent(gen))
					return;

				r = r || {};

				if (r.ok === false) {
					toolError('访问控制', r);
					return;
				}

				var users = r.users || [];

				dom.content(contentHost, E('div', { 'class': 'ncs-main' }, [
					toolHeader('访问控制', r.path || '/etc/nginx/htpasswd', [
						canWrite ? E('button', {
							'class': 'ncs-btn primary',
							'click': function() { askAuthUser(null); }
						}, [ '+ 新增用户' ]) : '',
						E('button', { 'class': 'ncs-btn', 'click': function() { renderAuthView(nextGen()); } }, [ '刷新' ])
					]),
					E('div', { 'class': 'ncs-sec' }, [
						E('p', { 'class': 'ncs-hint' }, [
							'片段里用 ',
							E('code', {}, [ 'auth_basic_user_file /etc/nginx/htpasswd;' ]),
							' 引用这个文件，密码以 $apr1$ 哈希保存。'
						]),
						users.length ? E('div', { 'style': 'margin-top:10px' }, users.map(function(u) {
							return E('div', { 'class': 'ncs-row' }, [
								E('span', { 'class': 'nm mono' }, [ u.user ]),
								E('span', { 'class': 'ncs-spacer' }),
								canWrite ? E('button', {
									'class': 'ncs-btn',
									'click': function() { askAuthUser(u.user); }
								}, [ '改密码' ]) : '',
								canWrite ? E('button', {
									'class': 'ncs-btn danger',
									'click': function() { askAuthDelete(u.user); }
								}, [ '删除' ]) : ''
							]);
						})) : E('p', { 'class': 'ncs-hint' }, [ '还没有用户。' ])
					])
				]));
			});
		}

		function askAuthUser(user) {
			var userIn = E('input', { 'class': 'ncs-input', 'value': user || '', 'placeholder': '用户名' });
			var passIn = E('input', { 'class': 'ncs-input', 'type': 'password', 'placeholder': '新密码' });
			var pass2In = E('input', { 'class': 'ncs-input', 'type': 'password', 'placeholder': '再输一次' });
			var feedback = E('p', { 'style': 'display:none;color:#e08585;margin:10px 0 0' }, [ '' ]);
			var btn = E('button', { 'class': 'ncs-btn primary' }, [ user ? '保存' : '创建' ]);

			if (user) {
				userIn.disabled = true;
				userIn.style.opacity = '0.7';
			}

			function warn(msg) {
				feedback.style.display = '';
				feedback.textContent = msg;
			}

			btn.addEventListener('click', function() {
				var u = String(userIn.value || '').trim();
				var p = String(passIn.value || '');
				var p2 = String(pass2In.value || '');

				if (!/^[A-Za-z0-9_.-]+$/.test(u))
					return warn('用户名只能用字母、数字、下划线、点和短横线。');
				if (!p)
					return warn('密码不能为空。');
				if (p !== p2)
					return warn('两次输入的密码不一样。');

				btn.disabled = true;
				feedback.style.display = 'none';

				// The password travels in the staged file, not as an argument.
				stageAndCall(p + '\n', [ 'auth', 'set', u ])
					.then(function(r) {
						r = r || {};

						if (!r.ok) {
							btn.disabled = false;
							warn(errText(r));
							return;
						}

						ui.hideModal();
						renderResult(true, user ? '密码已更新' : '用户已创建', u, '');
						renderAuthView();
					})
					.catch(function(e) {
						btn.disabled = false;
						warn((e && e.message) || String(e));
					});
			});

			ui.showModal(user ? '修改密码' : '新增用户', [
				E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [ '用户名' ]),
					E('div', { 'class': 'ncs-val' }, [ userIn ])
				]),
				E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [ '密码' ]),
					E('div', { 'class': 'ncs-val' }, [ passIn ])
				]),
				E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [ '确认密码' ]),
					E('div', { 'class': 'ncs-val' }, [ pass2In ])
				]),
				feedback,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					btn
				])
			]);
		}

		function askAuthDelete(user) {
			var btn = E('button', { 'class': 'ncs-btn danger' }, [ '删除' ]);

			btn.addEventListener('click', function() {
				btn.disabled = true;

				callHelper([ 'auth', 'delete', user ]).then(function(r) {
					ui.hideModal();
					r = r || {};

					renderResult(!!r.ok, r.ok ? '用户已删除' : '删除失败', user,
						r.ok ? '' : errText(r));

					renderAuthView();
				});
			});

			ui.showModal('删除用户', [
				E('p', {}, [ '删除用户 ', E('code', {}, [ user ]), ' ？' ]),
				E('p', { 'class': 'ncs-hint' }, [
					'原文件会留一份 .bak，不需要重新加载 nginx。'
				]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					btn
				])
			]);
		}

		// ---- 体检

		function renderAuditView(gen) {
			toolLoading('体检');

			callHelper([ 'audit' ]).then(function(r) {
				if (gen != null && !isCurrent(gen))
					return;

				r = r || {};

				if (r.ok === false) {
					toolError('体检', r);
					return;
				}

				var items = r.findings || [];

				function icon(level) {
					return level === 'warn' ? '!' : (level === 'error' ? '×' : 'i');
				}

				toolShell('体检', '检查 nginx -t 查不出来的问题', [
					E('button', { 'class': 'ncs-btn', 'click': function() { renderAuditView(nextGen()); } }, [ '重新检查' ])
				], items.length ? E('div', {}, items.map(function(f) {
					return E('div', { 'class': 'ncs-find ' + findingLevel(f) }, [
						E('span', { 'class': 'ic' }, [ icon(f.level) ]),
						E('div', {}, [
							E('div', { 'class': 'ti' }, [ f.title ]),
							E('div', { 'class': 'de mono' }, [ f.detail ])
						])
					]);
				})) : E('p', { 'class': 'ncs-hint' }, [ '没有发现问题。' ]));
			});
		}

		function renderProxyReadonly(entry) {
			var p = parseProxyFragment(entry.content);

			// Not a simple single-location proxy: show it as text, with the
			// editor still available.
			if (!p) {
				renderFragReadonly(entry, '这个片段不是一个简单的单 location 反代（可能有多个 location 或手写注释），所以按原文展示。');
				return;
			}

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ entry.name ]),
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ fmtSize(entry.size) + '　' + fmtTime(entry.mtime) ]),
					E('button', {
						'class': 'ncs-btn',
						'click': function() { editing = true; renderContent(); }
					}, [ '编辑' ]),
					E('button', {
						'class': 'ncs-btn danger',
						'click': function() { askDeleteFragment(entry.name); }
					}, [ '删除' ])
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '反向代理' ]),
					readField('路径', 'location', p.path),
					readField('后端地址', 'proxy_pass', p.target),
					readField('WebSocket', 'Upgrade', p.websocket ? '已启用' : ''),
					readField('连接超时', 'proxy_connect_timeout', p.connectTimeout),
					readField('发送超时', 'proxy_send_timeout', p.sendTimeout),
					readField('读超时', 'proxy_read_timeout', p.readTimeout)
				]),

				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '生成的配置' ]),
					E('pre', { 'class': 'ncs-frag' }, [ entry.content ])
				])
			]);
		}

		function renderProxyEdit(entry) {
			var parsed = parseProxyFragment(entry.content);

			if (!parsed) {
				renderFragEdit(entry);
				return;
			}

			var form = proxyFormFields(parsed);
			var preview = E('pre', { 'class': 'ncs-frag' }, [ '' ]);
			var feedback = E('p', { 'class': 'ncs-hint', 'style': 'display:none;color:#e08585' }, [ '' ]);
			var saveBtn = E('button', { 'class': 'ncs-btn primary' }, [ '保存并应用' ]);
			var cancelBtn = E('button', {
				'class': 'ncs-btn',
				'click': function() { editing = false; renderContent(); }
			}, [ '取消' ]);

			function refreshPreview() {
				var v = form.values();

				preview.textContent = proxyFormProblem(v)
					? '（填好路径和后端地址后，这里显示将要写入的配置）'
					: buildProxyFragment(v);
			}

			form.inputs.forEach(function(el) {
				el.addEventListener('input', refreshPreview);
				el.addEventListener('change', refreshPreview);
			});
			refreshPreview();

			saveBtn.addEventListener('click', function() {
				var v = form.values();
				var problem = proxyFormProblem(v);

				if (problem) {
					feedback.style.display = '';
					feedback.textContent = problem;
					return;
				}

				feedback.style.display = 'none';
				saveBtn.disabled = true;
				cancelBtn.disabled = true;
				saveBtn.textContent = '保存中…';

				stageAndCall(buildProxyFragment(v), [ 'frag-save', entry.name ])
					.then(function(r) {
						r = r || {};

						if (r.ok) {
							editing = false;
							return reloadAll().then(function() {
								renderAll();
								renderResult(true, '已保存并应用', entry.name, '');
							});
						}

						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						saveBtn.textContent = '保存并应用';
						feedback.style.display = '';
						feedback.textContent = errText(r) +
							(r.output ? '：' + String(r.output).trim() : '');

						return reloadAll().then(function() { renderAll(); });
					})
					.catch(function(e) {
						saveBtn.disabled = false;
						cancelBtn.disabled = false;
						saveBtn.textContent = '保存并应用';
						feedback.style.display = '';
						feedback.textContent = (e && e.message) || String(e);
					});
			});

			dom.content(contentHost, [
				E('div', { 'class': 'top' }, [
					E('span', { 'class': 't' }, [ entry.name ]),
					E('span', { 'class': 'ncs-spacer' }),
					E('span', { 'class': 'meta' }, [ CONF_DIR ]),
					cancelBtn,
					saveBtn
				]),
				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '反向代理' ]),
					form.host,
					feedback,
					E('p', { 'class': 'ncs-hint' }, [
						'保存时会重新生成整个片段文件；手写注释和表单没覆盖的指令会原样保留，' +
						'结构超出表单的片段请用文本编辑器。'
					])
				]),
				E('div', { 'class': 'ncs-sec' }, [
					E('h3', {}, [ '将要写入' ]),
					preview
				])
			]);
		}

		function openNewProxy() {
			var form = proxyFormFields({});
			var feedback = E('p', { 'style': 'display:none;color:#e08585;margin:10px 0 0' }, [ '' ]);
			var nameIn = E('input', { 'class': 'ncs-input', 'placeholder': '自动按路径取名' });
			var createBtn = E('button', { 'class': 'ncs-btn primary' }, [ '创建' ]);

			// The file name follows the path unless the user overrides it.
			form.inputs[0].addEventListener('input', function() {
				if (!nameIn.dataset.touched)
					nameIn.placeholder = fragmentNameFromPath(form.values().path);
			});
			nameIn.addEventListener('input', function() { nameIn.dataset.touched = '1'; });

			createBtn.addEventListener('click', function() {
				var v = form.values();
				var problem = proxyFormProblem(v);

				if (problem) {
					feedback.style.display = '';
					feedback.textContent = problem;
					return;
				}

				var name = String(nameIn.value || '').trim() || fragmentNameFromPath(v.path);

				if (!FRAG_NAME_RE.test(name)) {
					feedback.style.display = '';
					feedback.textContent = '文件名不合法，必须以 .locations 结尾';
					return;
				}

				if (findFragment(name)) {
					feedback.style.display = '';
					feedback.textContent = '已经存在同名的片段：' + name;
					return;
				}

				createBtn.disabled = true;
				feedback.style.display = 'none';

				stageAndCall(buildProxyFragment(v), [ 'frag-save', name ])
					.then(function(r) {
						r = r || {};

						if (!r.ok) {
							createBtn.disabled = false;
							feedback.style.display = '';
							feedback.textContent = errText(r) +
								(r.output ? '：' + String(r.output).trim() : '');
							return;
						}

						ui.hideModal();
						activeTab = 'proxy';
						activeFrag = name;
						editing = false;
						return reloadAll().then(function() {
							renderAll();
							renderResult(true, '已创建并重载', name, '');
						});
					})
					.catch(function(e) {
						createBtn.disabled = false;
						feedback.style.display = '';
						feedback.textContent = (e && e.message) || String(e);
					});
			});

			ui.showModal('新建反向代理', [
				form.host,
				E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [ '文件名', E('span', { 'class': 'd' }, [ '.locations' ]) ]),
					E('div', { 'class': 'ncs-val' }, [ nameIn ])
				]),
				feedback,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					createBtn
				])
			]);
		}

		function openNewServer() {
			var nameIn = E('input', { 'class': 'ncs-input', 'placeholder': '例如 mysite' });
			var listenIn = E('input', { 'class': 'ncs-input', 'placeholder': '例如 8080 或 10.0.0.1:8080' });
			var serverNameIn = E('input', { 'class': 'ncs-input', 'placeholder': '例如 example.com' });
			var feedback = E('p', { 'style': 'display:none;color:#e08585;margin:10px 0 0' }, [ '' ]);
			var createBtn = E('button', { 'class': 'ncs-btn primary' }, [ '创建' ]);

			function row(label, hint, cell) {
				return E('div', { 'class': 'ncs-field' }, [
					E('div', { 'class': 'ncs-lbl' }, [ label, hint ? E('span', { 'class': 'd' }, [ hint ]) : '' ]),
					E('div', { 'class': 'ncs-val' }, [ cell ])
				]);
			}

			createBtn.addEventListener('click', function() {
				var name = String(nameIn.value || '').trim();
				var listen = String(listenIn.value || '').trim();
				var serverName = String(serverNameIn.value || '').trim();

				// uci only accepts letters, digits and underscore in nginx.<name>.
				if (!/^[A-Za-z0-9_]+$/.test(name)) {
					feedback.style.display = '';
					feedback.textContent = '段名只能用字母、数字和下划线（uci 不接受短横线和点）。';
					return;
				}

				if (findServer(name)) {
					feedback.style.display = '';
					feedback.textContent = '已经存在同名的 server 段：' + name;
					return;
				}

				// A section without a listen directive would fall back to port 80
				// and collide with _redirect2ssl, so it is required here.
				if (!listen) {
					feedback.style.display = '';
					feedback.textContent = '必须填一条 listen，例如 8080 或 10.0.0.1:8080。新建后可在编辑里补证书再开 ssl。';
					return;
				}

				var lines = [ 'listen\t' + listen.replace(/\t/g, ' ') ];
				if (serverName)
					lines.push('server_name\t' + serverName.replace(/\t/g, ' '));

				createBtn.disabled = true;
				feedback.style.display = 'none';

				stageAndCall(lines.join('\n') + '\n', [ 'server-add', name ])
					.then(function(r) {
						r = r || {};

						if (!r.ok) {
							createBtn.disabled = false;
							feedback.style.display = '';
							feedback.textContent = (r.error === 'guard_failed' ? String(r.output || '') : errText(r)) +
								(r.output && r.error !== 'guard_failed' ? '：' + String(r.output).trim() : '');
							return;
						}

						ui.hideModal();
						activeTab = 'servers';
						activeServer = name;
						editing = false;
						return reloadAll().then(function() {
							renderAll();
							renderResult(true, '已新建 server 段', name, '');
						});
					})
					.catch(function(e) {
						createBtn.disabled = false;
						feedback.style.display = '';
						feedback.textContent = (e && e.message) || String(e);
					});
			});

			ui.showModal('新建 server 段', [
				row('段名', 'nginx.<段名>', nameIn),
				row('监听', 'listen（必填）', listenIn),
				row('服务器名', 'server_name（可选）', serverNameIn),
				E('p', { 'class': 'ncs-hint' }, [
					'新建只写入 listen 和 server_name，其余字段（证书、日志、include）建好后在编辑里补。'
				]),
				feedback,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					createBtn
				])
			]);
		}

		function askDeleteServer(name) {
			var delBtn = E('button', { 'class': 'ncs-btn danger' }, [ '删除' ]);

			delBtn.addEventListener('click', function() {
				delBtn.disabled = true;

				callHelper([ 'server-delete', name ]).then(function(r) {
					ui.hideModal();
					r = r || {};

					if (r.ok)
						renderResult(true, '已删除 server 段', name, '');
					else
						renderResult(false, '删除失败', name,
							(r.error === 'guard_failed' ? String(r.output || '') : errText(r)));

					activeServer = null;
					return reloadAll().then(function() {
						if (!findServer(activeServer) && servers.length)
							activeServer = servers[0]['.name'];
						renderAll();
					});
				});
			});

			ui.showModal('删除 server 段', [
				E('p', {}, [
					'确定删除 ', E('code', {}, [ 'nginx.' + name ]),
					' 吗？删除前会自动备份到 /root/backup/nginx-console/，' +
					'并且只有通过 nginx -t 才会真正生效。'
				]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					delBtn
				])
			]);
		}

		function askDeleteFragment(name) {
			var delBtn = E('button', { 'class': 'ncs-btn danger' }, [ '删除' ]);

			delBtn.addEventListener('click', function() {
				delBtn.disabled = true;

				callHelper([ 'frag-delete', name ]).then(function(r) {
					ui.hideModal();
					r = r || {};

					if (r.ok)
						renderResult(true, '已删除', name, '');
					else
						renderResult(false, '删除失败', name,
							errText(r) + (r.output ? '\n' + String(r.output).trim() : ''));

					editing = false;
					return reloadAll().then(function() {
						if (activeFrag === name) {
							// Stay inside the tab the user is looking at.
							var rest = visibleFragments(activeTab);
							activeFrag = rest.length ? rest[0].name : null;
						}

						renderAll();
					});
				});
			});

			ui.showModal('删除片段', [
				E('p', {}, [
					'确定删除 ', E('code', {}, [ name ]),
					' 吗？删除前会自动备份到 /root/backup/nginx-console-fragments/。'
				]),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					delBtn
				])
			]);
		}

		function openNewFragment() {
			// Proxies are created through the structured form.
			if (activeTab === 'proxy') {
				openNewProxy();
				return;
			}

			var input = E('input', {
				'class': 'ncs-input',
				'style': 'width:100%',
				'placeholder': '例如 myservice.locations'
			});
			var feedback = E('p', { 'style': 'display:none;color:#e08585;margin:8px 0 0' }, [ '' ]);
			var createBtn = E('button', { 'class': 'ncs-btn primary' }, [ '创建' ]);

			createBtn.addEventListener('click', function() {
				var name = String(input.value || '').trim();

				if (!FRAG_NAME_RE.test(name)) {
					feedback.style.display = '';
					feedback.textContent = '文件名必须以 .locations 结尾，只能包含字母、数字、点、下划线和短横线。';
					return;
				}

				ui.hideModal();

				var existing = findFragment(name);

				// 'fragments' is not a tab: switching to it left no chip
				// highlighted and hid the new entry from every kind filter.
				// A new fragment is unclassified, so it opens under "其他".
				if (!existing)
					activeTab = 'other';

				activeFrag = name;
				editing = true;

				// A brand new name is not in the list yet: show it as an empty
				// fragment so the editor can open on it.
				if (!existing)
					fragments = fragments.concat([ {
						name: name, size: 0, mtime: 0,
						content: '', kind: activeTab
					} ]);

				renderAll();
			});

			ui.showModal('新建片段', [
				E('p', {}, [ '文件名（创建在 ', E('code', {}, [ CONF_DIR ]), ' 下）：' ]),
				input,
				feedback,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'ncs-btn', 'click': ui.hideModal }, [ '取消' ]),
					' ',
					createBtn
				])
			]);
		}


		renderAll();

		return E('div', {}, [
			E('style', {}, [ CSS ]),

			E('div', { 'class': 'ncs-head' }, [
				E('h2', {}, [ 'Nginx 控制台' ]),
				E('span', { 'class': 'ncs-sub' }, [ '服务器段与 conf.d 片段' ]),
				E('span', { 'class': 'ncs-spacer' }),
				testBtn
			]),

			E('div', { 'class': 'ncs-status' }, [
				status.ok === false
					? E('span', { 'style': 'color:#e08585' }, [
						E('span', { 'class': 'ncs-dot off' }),
						'状态读取失败：' + (status.error || 'unknown'),
						status.output
							? E('code', { 'style': 'margin-left:8px;color:#8d8d8d' },
								[ String(status.output).trim().slice(0, TEST_OUTPUT_PREVIEW) ])
							: ''
					])
					: E('span', {}, [
						E('span', { 'class': 'ncs-dot ' + (status.running ? 'on' : 'off') }),
						status.running ? '运行中' : '未运行'
					]),
				status.version ? E('span', {}, [ E('span', { 'class': 'k' }, [ '版本 ' ]), status.version ]) : '',
				// Counts come from the lists the page holds, not from the
				// status snapshot: that snapshot is read once at load, so
				// saving a section left the number stale and looked like the
				// save had failed.
				E('span', {}, [ E('span', { 'class': 'k' }, [ 'server 段 ' ]),
					String(servers.length) ]),
				E('span', {}, [ E('span', { 'class': 'k' }, [ '片段 ' ]),
					String(fragments.length) ]),
				typeof status.workers === 'number'
					? E('span', {}, [ E('span', { 'class': 'k' }, [ 'worker ' ]), String(status.workers) ])
					: '',
				E('span', {}, [ E('span', { 'class': 'k' }, [ '配置 ' ]), status.conf || '/etc/nginx/uci.conf' ])
			]),

			canWrite ? '' : E('div', { 'class': 'ncs-ro' }, [
				accessUnknown
					? '无法确认当前账号的写权限（权限查询没有响应），因此按只读处理：修改相关的按钮已隐藏。'
					: '当前账号只有只读权限：可以查看配置与状态，修改相关的按钮已隐藏。'
			]),

			resultHost,

			tabHost,
			subTabHost,
			contentHost,

			E('p', { 'class': 'ncs-note' }, [
				'保存走的是同一条路：备份 → 写入 → 重新渲染 → nginx -t → 失败就还原。',
				'server 段只有真正改过的字段会被重写，片段整份替换。'
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
