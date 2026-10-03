'use strict';
'require view';
'require ui';
'require rpc';
'require fs';

/*
 * shadcnui theme configuration page.
 * Lives at /usr/share/luci/menu.d/luci-app-shadcnui-config.json -> view shadcnui/config
 * Talks to /usr/libexec/rpcd/luci.shadcnui via ubus.
 */

var rpcList = rpc.declare({
	object: 'luci.shadcnui', method: 'list',
	expect: { config: {} }
});
var rpcSave = rpc.declare({
	object: 'luci.shadcnui', method: 'save',
	params: [ 'mode', 'base', 'accent', 'radius', 'bg_source', 'bg_url',
	          'unsplash_key', 'wallhaven_key' ],
	expect: { ok: false }
});
var rpcBing = rpc.declare({
	object: 'luci.shadcnui', method: 'bing_image', expect: { }
});
var rpcUnsplash = rpc.declare({
	object: 'luci.shadcnui', method: 'unsplash_image',
	params: [ 'query' ], expect: { }
});
var rpcWallhaven = rpc.declare({
	object: 'luci.shadcnui', method: 'wallhaven_image',
	params: [ 'query' ], expect: { }
});

/* Helpers ------------------------------------------------------------------ */

function hexToHsl(hex) {
	hex = (hex || '').replace('#', '');
	if (hex.length == 3) hex = hex.split('').map(function (c) { return c + c; }).join('');
	if (hex.length != 6) return null;
	var r = parseInt(hex.slice(0, 2), 16) / 255;
	var g = parseInt(hex.slice(2, 4), 16) / 255;
	var b = parseInt(hex.slice(4, 6), 16) / 255;
	var max = Math.max(r, g, b), min = Math.min(r, g, b);
	var h, s, l = (max + min) / 2;
	if (max == min) { h = 0; s = 0; }
	else {
		var d = max - min;
		s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
		switch (max) {
			case r: h = (g - b) / d + (g < b ? 6 : 0); break;
			case g: h = (b - r) / d + 2; break;
			case b: h = (r - g) / d + 4; break;
		}
		h /= 6;
	}
	return (h * 360).toFixed(1) + ' ' + (s * 100).toFixed(1) + '% ' + (l * 100).toFixed(1) + '%';
}

function hslToHex(hsl) {
	if (!hsl) return '#000000';
	var m = hsl.match(/(-?[\d.]+)\s+(-?[\d.]+)%\s+(-?[\d.]+)%/);
	if (!m) return '#000000';
	var h = +m[1] / 360, s = +m[2] / 100, l = +m[3] / 100;
	function f(p, q, t) {
		if (t < 0) t += 1;
		if (t > 1) t -= 1;
		if (t < 1 / 6) return p + (q - p) * 6 * t;
		if (t < 1 / 2) return q;
		if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
		return p;
	}
	var r, g, b;
	if (s == 0) { r = g = b = l; }
	else {
		var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
		var p = 2 * l - q;
		r = f(p, q, h + 1 / 3); g = f(p, q, h); b = f(p, q, h - 1 / 3);
	}
	function toHex(x) {
		var v = Math.round(x * 255).toString(16);
		return v.length == 1 ? '0' + v : v;
	}
	return '#' + toHex(r) + toHex(g) + toHex(b);
}

/* Live preview applied directly to <html> while user is editing ------------- */
function applyPreview(state) {
	var root = document.documentElement;
	root.setAttribute('data-base', state.base || 'zinc');
	if (state.mode === 'system') {
		var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
		root.setAttribute('data-theme', prefersDark ? 'dark' : 'light');
	} else {
		root.setAttribute('data-theme', state.mode === 'dark' ? 'dark' : 'light');
	}
	root.setAttribute('data-mode', state.mode || 'system');
	if (state.accent) {
		root.style.setProperty('--primary', state.accent);
		root.style.setProperty('--ring', state.accent);
	} else {
		root.style.removeProperty('--primary');
		root.style.removeProperty('--ring');
	}
	if (state.radius) root.style.setProperty('--radius', state.radius);
}

function setBgPreview(url) {
	var img = document.getElementById('shadcnui-bg-preview');
	if (img) img.style.backgroundImage = url ? 'url("' + url + '")' : 'none';
}

/* View definition ---------------------------------------------------------- */

return view.extend({

	load: function () { return rpcList(); },

	render: function (cfg) {
		cfg = cfg || {};
		var main = cfg.main || {};
		var unsplashCfg = cfg.unsplash || {};
		var wallhavenCfg = cfg.wallhaven || {};

		// initial state
		var state = {
			mode:      main.mode      || 'system',
			base:      main.base      || 'zinc',
			accent:    main.accent    || '',
			radius:    main.radius    || '0.5rem',
			bg_source: main.bg_source || 'none',
			bg_url:    main.bg_url    || '',
			unsplash_key:  '',
			wallhaven_key: ''
		};

		// --- Builders -----------------------------------------------------------

		function row(label, descr, control) {
			var d = E('div', { 'class': 'cbi-value' }, [
				E('div', { 'class': 'cbi-value-title' }, label),
				E('div', { 'class': 'cbi-value-field' }, [ control ])
			]);
			if (descr) d.appendChild(E('div', { 'class': 'cbi-value-description' }, descr));
			return d;
		}

		function select(name, options, value) {
			var sel = E('select', { 'id': 'sci-' + name });
			options.forEach(function (o) {
				var opt = E('option', { 'value': o[0] }, o[1]);
				if (o[0] === value) opt.selected = true;
				sel.appendChild(opt);
			});
			return sel;
		}

		var modeSel = select('mode', [
			[ 'system', _('Follow system') ],
			[ 'light',  _('Light') ],
			[ 'dark',   _('Dark') ]
		], state.mode);
		modeSel.addEventListener('change', function (ev) {
			state.mode = ev.target.value;
			applyPreview(state);
		});

		var baseSel = select('base', [
			[ 'zinc',    'Zinc' ],
			[ 'slate',   'Slate' ],
			[ 'stone',   'Stone' ],
			[ 'gray',    'Gray' ],
			[ 'neutral', 'Neutral' ]
		], state.base);
		baseSel.addEventListener('change', function (ev) {
			state.base = ev.target.value;
			applyPreview(state);
		});

		// Accent: color picker + readout of the HSL string
		var accentPick = E('input', {
			type:  'color',
			value: state.accent ? hslToHex(state.accent) : '#18181b',
			style: 'width:42px;height:36px;padding:2px;cursor:pointer'
		});
		var accentText = E('input', {
			type:        'text',
			placeholder: 'e.g. 240 5.9% 10%  (leave empty for base default)',
			value:       state.accent,
			style:       'flex:1'
		});
		var accentReset = E('button', {
			'class': 'btn btn-outline btn-sm',
			'type':  'button',
			'click': function () {
				state.accent = ''; accentText.value = '';
				applyPreview(state);
			}
		}, _('Reset'));
		var accentRow = E('div', { style: 'display:flex;gap:.5rem;align-items:center' },
			[ accentPick, accentText, accentReset ]);

		accentPick.addEventListener('input', function (ev) {
			var hsl = hexToHsl(ev.target.value);
			state.accent = hsl;
			accentText.value = hsl;
			applyPreview(state);
		});
		accentText.addEventListener('change', function (ev) {
			state.accent = ev.target.value.trim();
			if (state.accent) accentPick.value = hslToHex(state.accent);
			applyPreview(state);
		});

		// Radius slider
		var radiusInp = E('input', {
			type: 'range', min: '0', max: '1.5', step: '0.05',
			value: parseFloat(state.radius) || 0.5,
			style: 'flex:1'
		});
		var radiusOut = E('span', { style: 'width:4em;text-align:right;font-variant-numeric:tabular-nums' },
			state.radius);
		radiusInp.addEventListener('input', function (ev) {
			state.radius = ev.target.value + 'rem';
			radiusOut.textContent = state.radius;
			applyPreview(state);
		});
		var radiusRow = E('div', { style: 'display:flex;gap:.75rem;align-items:center' },
			[ radiusInp, radiusOut ]);

		// Background source selector + per-source UI ----------------------------

		var bgSrcSel = select('bg_source', [
			[ 'none',      _('None') ],
			[ 'bing',      _('Bing daily') ],
			[ 'url',       _('Custom URL') ],
			[ 'local',     _('Local upload') ],
			[ 'unsplash',  _('Unsplash') ],
			[ 'wallhaven', _('Wallhaven') ]
		], state.bg_source);

		var bgUrlInp = E('input', {
			type: 'url',
			value: state.bg_url,
			placeholder: 'https://example.com/wallpaper.jpg'
		});
		bgUrlInp.addEventListener('change', function (ev) {
			state.bg_url = ev.target.value.trim();
			setBgPreview(state.bg_url);
		});

		var unsplashKeyInp = E('input', {
			type: 'password', placeholder: '***',
			value: unsplashCfg.access_key === '***' ? '' : (unsplashCfg.access_key || '')
		});
		unsplashKeyInp.addEventListener('change', function (ev) {
			state.unsplash_key = ev.target.value;
		});

		var unsplashQueryInp = E('input', {
			type: 'text',
			value: unsplashCfg.query || 'nature',
			placeholder: 'nature, mountains, abstract...'
		});

		var wallhavenKeyInp = E('input', {
			type: 'password', placeholder: '*** (optional, for SFW token)',
			value: wallhavenCfg.api_key === '***' ? '' : (wallhavenCfg.api_key || '')
		});
		wallhavenKeyInp.addEventListener('change', function (ev) {
			state.wallhaven_key = ev.target.value;
		});

		var wallhavenQueryInp = E('input', {
			type: 'text',
			value: wallhavenCfg.query || 'minimal',
			placeholder: 'minimal, cyberpunk, anime...'
		});

		// Fetch buttons
		function feedback(msg, kind) {
			ui.addNotification(null, E('p', {}, msg), kind || 'info');
		}

		var bingFetchBtn = E('button', {
			'class': 'btn',
			'type':  'button',
			'click': function () {
				bingFetchBtn.disabled = true;
				rpcBing().then(function (r) {
					bingFetchBtn.disabled = false;
					if (r && r.url) {
						state.bg_url = r.url;
						bgUrlInp.value = r.url;
						setBgPreview(r.url);
						feedback(_('Bing image loaded.'), 'success');
					} else {
						feedback(_('Failed to fetch Bing image.'), 'danger');
					}
				});
			}
		}, _('Fetch today\'s Bing image'));

		var unsplashFetchBtn = E('button', {
			'class': 'btn',
			'type':  'button',
			'click': function () {
				unsplashFetchBtn.disabled = true;
				rpcUnsplash(unsplashQueryInp.value).then(function (r) {
					unsplashFetchBtn.disabled = false;
					if (r && r.url) {
						state.bg_url = r.url;
						bgUrlInp.value = r.url;
						setBgPreview(r.url);
						feedback(_('Unsplash image loaded' + (r.attribution ? ' — ' + r.attribution : '')) + '.', 'success');
					} else {
						feedback(_('Failed to fetch Unsplash image.') + (r && r.error ? ' (' + r.error + ')' : ''), 'danger');
					}
				});
			}
		}, _('Fetch random Unsplash'));

		var wallhavenFetchBtn = E('button', {
			'class': 'btn',
			'type':  'button',
			'click': function () {
				wallhavenFetchBtn.disabled = true;
				rpcWallhaven(wallhavenQueryInp.value).then(function (r) {
					wallhavenFetchBtn.disabled = false;
					if (r && r.url) {
						state.bg_url = r.url;
						bgUrlInp.value = r.url;
						setBgPreview(r.url);
						feedback(_('Wallhaven image loaded.'), 'success');
					} else {
						feedback(_('Failed to fetch Wallhaven image.') + (r && r.error ? ' (' + r.error + ')' : ''), 'danger');
					}
				});
			}
		}, _('Fetch random Wallhaven'));

		// Local file upload — write into /www/luci-static/shadcnui/img/background/
		var localUpload = E('input', { type: 'file', accept: 'image/*' });
		localUpload.addEventListener('change', function (ev) {
			var f = ev.target.files && ev.target.files[0];
			if (!f) return;
			// strip path components, allow only safe chars in the filename
			var safe = f.name.replace(/[^A-Za-z0-9._-]/g, '_');
			var path = '/www/luci-static/shadcnui/img/background/' + safe;
			var reader = new FileReader();
			reader.onload = function () {
				var bytes = new Uint8Array(reader.result);
				fs.write(path, bytes).then(function () {
					var publicUrl = '/luci-static/shadcnui/img/background/' + safe;
					state.bg_url = publicUrl;
					bgUrlInp.value = publicUrl;
					setBgPreview(publicUrl);
					feedback(_('Uploaded to %s').format(path), 'success');
				}).catch(function (err) {
					feedback(_('Upload failed: %s').format(err.message || err), 'danger');
				});
			};
			reader.readAsArrayBuffer(f);
		});

		// Containers per source — show/hide based on selector
		var bgSections = {
			none: E('p', { 'class': 'cbi-value-description' },
				_('No background image will be shown on the login page.')),
			url: E('div', { style: 'display:grid;gap:.5rem' }, [ bgUrlInp ]),
			local: E('div', { style: 'display:grid;gap:.5rem' }, [
				localUpload,
				E('p', { 'class': 'cbi-value-description' },
					_('Files are stored under /www/luci-static/shadcnui/img/background/.'))
			]),
			bing: E('div', { style: 'display:grid;gap:.5rem' }, [
				bingFetchBtn,
				E('p', { 'class': 'cbi-value-description' },
					_('Requires internet access from the router.'))
			]),
			unsplash: E('div', { style: 'display:grid;gap:.5rem' }, [
				row(_('Access Key'), _('Get a free Demo key at unsplash.com/developers.'),
				    unsplashKeyInp),
				row(_('Query'), null, unsplashQueryInp),
				unsplashFetchBtn
			]),
			wallhaven: E('div', { style: 'display:grid;gap:.5rem' }, [
				row(_('API Key'), _('Optional. Required only for NSFW or rate-limit relief.'),
				    wallhavenKeyInp),
				row(_('Query'), null, wallhavenQueryInp),
				wallhavenFetchBtn
			])
		};

		function showBgSection() {
			Object.keys(bgSections).forEach(function (k) {
				bgSections[k].style.display = (k === state.bg_source) ? '' : 'none';
			});
		}

		bgSrcSel.addEventListener('change', function (ev) {
			state.bg_source = ev.target.value;
			showBgSection();
		});

		var bgPreview = E('div', {
			'id':    'shadcnui-bg-preview',
			'style': 'width:100%;aspect-ratio:16/6;border-radius:var(--radius);' +
			         'border:1px solid hsl(var(--border));background-size:cover;' +
			         'background-position:center;background-color:hsl(var(--muted))'
		});
		setBgPreview(state.bg_url);

		// --- Save button --------------------------------------------------------

		var saveBtn = E('button', {
			'class': 'btn btn-lg',
			'type':  'button',
			'click': function () {
				saveBtn.disabled = true;
				rpcSave(state.mode, state.base, state.accent, state.radius,
				        state.bg_source, state.bg_url,
				        state.unsplash_key, state.wallhaven_key).then(function (ok) {
					saveBtn.disabled = false;
					if (ok) {
						ui.addNotification(null,
							E('p', {}, _('Settings saved. Reload the page to apply everywhere.')),
							'success');
					} else {
						ui.addNotification(null,
							E('p', {}, _('Failed to save settings.')), 'danger');
					}
				});
			}
		}, _('Save'));

		// --- Layout -------------------------------------------------------------

		showBgSection();
		applyPreview(state);

		return E('div', {}, [
			E('h1', { 'class': 'page-title' }, _('Theme')),
			E('p',  { 'class': 'page-description' },
				_('Personalize the shadcnui LuCI theme. Changes preview live; click Save to persist.')),

			E('div', { 'class': 'cbi-section' }, [
				E('legend', {}, _('Appearance')),
				row(_('Mode'),
				    _('Light, dark, or follow your operating system.'),
				    modeSel),
				row(_('Base palette'),
				    _('Neutral palette — same options as on ui.shadcn.com.'),
				    baseSel),
				row(_('Accent color'),
				    _('Overrides --primary. Hex picker writes the equivalent HSL string used by shadcn tokens.'),
				    accentRow),
				row(_('Border radius'),
				    _('Controls corner roundness across the theme.'),
				    radiusRow)
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('legend', {}, _('Login background')),
				row(_('Source'), null, bgSrcSel),
				bgSections.none,
				bgSections.url,
				bgSections.local,
				bgSections.bing,
				bgSections.unsplash,
				bgSections.wallhaven,
				E('div', { style: 'margin-top:1rem' }, bgPreview)
			]),

			E('div', { 'class': 'cbi-page-actions' }, [ saveBtn ])
		]);
	},

	handleSaveApply: null,
	handleSave:      null,
	handleReset:     null
});
