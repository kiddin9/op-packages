/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require baseclass';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';

function pad2(value) {
	value = (value == null) ? '' : String(value).trim();
	return value.length === 1 ? '0' + value : value;
}

function normalizeTimePart(value, min, max) {
	value = parseInt(String(value || '').trim(), 10);
	if (isNaN(value))
		value = min;
	value = Math.max(min, Math.min(max, value));
	return pad2(value);
}

function parseCron(value) {
	const matched = String(value || '').trim().match(/^(\d{1,2})\s+(\d{1,2})\s+\*\s+\*\s+([0-7*])$/);
	if (!matched)
		return null;

	const minute = +matched[1],
	      hour = +matched[2];
	if (minute < 0 || minute > 59 || hour < 0 || hour > 23)
		return null;

	return {
		minute: normalizeTimePart(matched[1], 0, 59),
		hour: normalizeTimePart(matched[2], 0, 23),
		day: matched[3] === '*' ? '*' : (matched[3] === '7' ? '0' : matched[3])
	};
}

function buildCron(day, hour, minute) {
	return [
		normalizeTimePart(minute, 0, 59),
		normalizeTimePart(hour, 0, 23),
		'*',
		'*',
		String(day || '*')
	].join(' ');
}

function alignCronEditorRow(wrap) {
	let field = wrap?.parentNode;

	while (field && !field.classList?.contains('cbi-value-field'))
		field = field.parentNode;

	let row = field?.parentNode;
	while (row && !row.classList?.contains('cbi-value'))
		row = row.parentNode;

	if (!row || !field)
		return false;

	if (wrap._dailyRow) {
		wrap._dailyRow.style.display = row.style.display;
		return true;
	}

	let dailyRow = E('div', { 'class': 'cbi-value homeproxy-cron-daily-row' }, [
		E('div', { 'class': 'cbi-value-title' }, _('Update time (daily)')),
		E('div', { 'class': 'cbi-value-field' }, [ wrap._dailyField ])
	]);

	wrap._dailyRow = dailyRow;
	row.parentNode.insertBefore(dailyRow, row.nextSibling);

	return true;
}

function watchCronEditorRow(wrap) {
	const align = () => alignCronEditorRow(wrap);
	[ 0, 50, 200, 500, 1000, 2000 ].forEach(delay => window.setTimeout(align, delay));

	if (typeof MutationObserver !== 'undefined' && document?.body) {
		const observer = new MutationObserver(() => {
			if (align())
				observer.disconnect();
		});

		observer.observe(document.body, { childList: true, subtree: true });
		window.setTimeout(() => observer.disconnect(), 3000);
	}
}

function renderCronEditor(input) {
	if (!input)
		return null;

	const parsed = parseCron(input.value);
	input.type = 'text';
	input.readOnly = true;
	input.tabIndex = -1;
	input.style.position = 'absolute';
	input.style.opacity = '0';
	input.style.pointerEvents = 'none';
	input.style.width = '1px';
	input.style.height = '1px';
	input.style.minWidth = '1px';
	input.style.maxWidth = '1px';
	input.style.padding = '0';
	input.style.border = '0';

	let day = E('select', { 'class': 'cbi-input-select', 'style': 'width: 12em !important; min-width: 12em !important; max-width: 12em !important; box-sizing: border-box;' }),
	    hour = E('select', { 'class': 'cbi-input-select', 'style': 'width: 4.25em !important; min-width: 4.25em !important; max-width: 4.25em !important; box-sizing: border-box;' }),
	    minute = E('select', { 'class': 'cbi-input-select', 'style': 'width: 4.25em !important; min-width: 4.25em !important; max-width: 4.25em !important; box-sizing: border-box;' }),
	    dailyField = E('div', { 'style': 'display: flex; align-items: center; gap: .25em; width: 9.5em;' }, [
		hour,
		E('span', ':'),
		minute
	    ]),
	    wrap = E('div', { 'class': 'homeproxy-cron-editor' }, [ day ]);

	wrap._dailyField = dailyField;

	for (let i = 0; i < 24; i++)
		hour.appendChild(E('option', { value: pad2(i) }, pad2(i)));

	for (let i = 0; i < 60; i++)
		minute.appendChild(E('option', { value: pad2(i) }, pad2(i)));

	[
		['*', _('Every day')],
		['1', _('Every Monday')],
		['2', _('Every Tuesday')],
		['3', _('Every Wednesday')],
		['4', _('Every Thursday')],
		['5', _('Every Friday')],
		['6', _('Every Saturday')],
		['0', _('Every Sunday')]
	].forEach(([value, label]) => day.appendChild(E('option', { value }, label)));

	day.value = parsed ? parsed.day : '*';
	hour.value = parsed ? parsed.hour : '00';
	minute.value = parsed ? parsed.minute : '00';
	input.value = buildCron(day.value, hour.value, minute.value);
	input.setAttribute('value', input.value);

	const sync = () => {
		input.value = buildCron(day.value, hour.value, minute.value);
		input.setAttribute('value', input.value);
		input.dispatchEvent(new Event('input', { bubbles: true }));
		input.dispatchEvent(new Event('change', { bubbles: true }));
	};

	day.addEventListener('change', sync);
	hour.addEventListener('change', sync);
	minute.addEventListener('change', sync);
	wrap.appendChild(input);
	window.setTimeout(() => watchCronEditorRow(wrap), 0);
	return wrap;
}

return baseclass.extend({
	dns_strategy: {
		'': _('Default'),
		'prefer_ipv4': _('Prefer IPv4'),
		'prefer_ipv6': _('Prefer IPv6'),
		'ipv4_only': _('IPv4 only'),
		'ipv6_only': _('IPv6 only')
	},

	shadowsocks_encrypt_length: {
		/* AEAD */
		'aes-128-gcm': 0,
		'aes-192-gcm': 0,
		'aes-256-gcm': 0,
		'chacha20-ietf-poly1305': 0,
		'xchacha20-ietf-poly1305': 0,
		/* AEAD 2022 */
		'2022-blake3-aes-128-gcm': 16,
		'2022-blake3-aes-256-gcm': 32,
		'2022-blake3-chacha20-poly1305': 32
	},

	shadowsocks_encrypt_methods: [
		/* Stream */
		'none',
		/* AEAD */
		'aes-128-gcm',
		'aes-192-gcm',
		'aes-256-gcm',
		'chacha20-ietf-poly1305',
		'xchacha20-ietf-poly1305',
		/* AEAD 2022 */
		'2022-blake3-aes-128-gcm',
		'2022-blake3-aes-256-gcm',
		'2022-blake3-chacha20-poly1305'
	],

	tls_cipher_suites: [
		'TLS_RSA_WITH_AES_128_CBC_SHA',
		'TLS_RSA_WITH_AES_256_CBC_SHA',
		'TLS_RSA_WITH_AES_128_GCM_SHA256',
		'TLS_RSA_WITH_AES_256_GCM_SHA384',
		'TLS_AES_128_GCM_SHA256',
		'TLS_AES_256_GCM_SHA384',
		'TLS_CHACHA20_POLY1305_SHA256',
		'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA',
		'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA',
		'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA',
		'TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA',
		'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
		'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384',
		'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',
		'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
		'TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256',
		'TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256'
	],

	tls_versions: [
		'1.0',
		'1.1',
		'1.2',
		'1.3'
	],

	CBIStaticList: form.DynamicList.extend({
		__name__: 'CBI.StaticList',

		renderWidget: function(/* ... */) {
			let dl = form.DynamicList.prototype.renderWidget.apply(this, arguments);
			dl.querySelector('.add-item ul > li[data-value="-"]')?.remove();
			return dl;
		}
	}),

	CBIMultiValue: form.MultiValue.extend({
		__name__: 'CBI.HomeProxyMultiValue',

		renderWidget(section_id, _option_index, cfgvalue) {
			let value = (cfgvalue != null) ? cfgvalue : this.default,
			    choices = this.transformChoices() || {},
			    widget = new ui.Dropdown(L.toArray(value), choices, {
				id: this.cbid(section_id),
				sort: this.keylist,
				multiple: true,
				optional: this.optional || this.rmempty,
				select_placeholder: this.placeholder,
				create: this.create,
				display_items: this.display_size ?? this.size ?? 3,
				dropdown_items: this.dropdown_size ?? this.size ?? -1,
				validate: this.getValidator(section_id),
				disabled: (this.readonly != null) ? this.readonly : this.map.readonly
			});

			return widget.render();
		}
	}),

	calcStringMD5(e) {
		/* Thanks to https://stackoverflow.com/a/41602636 */
		let h = (a, b) => {
			let c, d, e, f, g;
			c = a & 2147483648;
			d = b & 2147483648;
			e = a & 1073741824;
			f = b & 1073741824;
			g = (a & 1073741823) + (b & 1073741823);
			return e & f ? g ^ 2147483648 ^ c ^ d : e | f ? g & 1073741824 ? g ^ 3221225472 ^ c ^ d : g ^ 1073741824 ^ c ^ d : g ^ c ^ d;
		}, k = (a, b, c, d, e, f, g) => h((a = h(a, h(h(b & c | ~b & d, e), g))) << f | a >>> 32 - f, b),
		l = (a, b, c, d, e, f, g) => h((a = h(a, h(h(b & d | c & ~d, e), g))) << f | a >>> 32 - f, b),
		m = (a, b, c, d, e, f, g) => h((a = h(a, h(h(b ^ c ^ d, e), g))) << f | a >>> 32 - f, b),
		n = (a, b, c, d, e, f, g) => h((a = h(a, h(h(c ^ (b | ~d), e), g))) << f | a >>> 32 - f, b),
		p = a => { let b = '', d = ''; for (let c = 0; c <= 3; c++) d = a >>> 8 * c & 255, d = '0' + d.toString(16), b += d.substr(d.length - 2, 2); return b; };

		let f = [], q, r, s, t, a, b, c, d;
		e = (() => {
			e = e.replace(/\r\n/g, '\n');
			let b = '';
			for (let d = 0; d < e.length; d++) {
				let c = e.charCodeAt(d);
				b += c < 128 ? String.fromCharCode(c) : c < 2048 ? String.fromCharCode(c >> 6 | 192) + String.fromCharCode(c & 63 | 128) :
					String.fromCharCode(c >> 12 | 224) + String.fromCharCode(c >> 6 & 63 | 128) + String.fromCharCode(c & 63 | 128);
			}
			return b;
		})();
		f = (() => {
			let c = e.length, a = c + 8, d = 16 * ((a - a % 64) / 64 + 1), b = Array(d - 1), f = 0, g = 0;
			for (; g < c;) a = (g - g % 4) / 4, f = g % 4 * 8, b[a] |= e.charCodeAt(g) << f, g++;
			a = (g - g % 4) / 4, b[a] |= 128 << g % 4 * 8, b[d - 2] = c << 3, b[d - 1] = c >>> 29;
			return b;
		})();

		a = 1732584193, b = 4023233417, c = 2562383102, d = 271733878;
		for (e = 0; e < f.length; e += 16) {
			q = a, r = b, s = c, t = d;
			a = k(a, b, c, d, f[e +  0],  7, 3614090360), d = k(d, a, b, c, f[e +  1], 12, 3905402710),
			c = k(c, d, a, b, f[e +  2], 17,  606105819), b = k(b, c, d, a, f[e +  3], 22, 3250441966),
			a = k(a, b, c, d, f[e +  4],  7, 4118548399), d = k(d, a, b, c, f[e +  5], 12, 1200080426),
			c = k(c, d, a, b, f[e +  6], 17, 2821735955), b = k(b, c, d, a, f[e +  7], 22, 4249261313),
			a = k(a, b, c, d, f[e +  8],  7, 1770035416), d = k(d, a, b, c, f[e +  9], 12, 2336552879),
			c = k(c, d, a, b, f[e + 10], 17, 4294925233), b = k(b, c, d, a, f[e + 11], 22, 2304563134),
			a = k(a, b, c, d, f[e + 12],  7, 1804603682), d = k(d, a, b, c, f[e + 13], 12, 4254626195),
			c = k(c, d, a, b, f[e + 14], 17, 2792965006), b = k(b, c, d, a, f[e + 15], 22, 1236535329),
			a = l(a, b, c, d, f[e +  1],  5, 4129170786), d = l(d, a, b, c, f[e +  6],  9, 3225465664),
			c = l(c, d, a, b, f[e + 11], 14,  643717713), b = l(b, c, d, a, f[e +  0], 20, 3921069994),
			a = l(a, b, c, d, f[e +  5],  5, 3593408605), d = l(d, a, b, c, f[e + 10],  9,   38016083),
			c = l(c, d, a, b, f[e + 15], 14, 3634488961), b = l(b, c, d, a, f[e +  4], 20, 3889429448),
			a = l(a, b, c, d, f[e +  9],  5,  568446438), d = l(d, a, b, c, f[e + 14],  9, 3275163606),
			c = l(c, d, a, b, f[e +  3], 14, 4107603335), b = l(b, c, d, a, f[e +  8], 20, 1163531501),
			a = l(a, b, c, d, f[e + 13],  5, 2850285829), d = l(d, a, b, c, f[e +  2],  9, 4243563512),
			c = l(c, d, a, b, f[e +  7], 14, 1735328473), b = l(b, c, d, a, f[e + 12], 20, 2368359562),
			a = m(a, b, c, d, f[e +  5],  4, 4294588738), d = m(d, a, b, c, f[e +  8], 11, 2272392833),
			c = m(c, d, a, b, f[e + 11], 16, 1839030562), b = m(b, c, d, a, f[e + 14], 23, 4259657740),
			a = m(a, b, c, d, f[e +  1],  4, 2763975236), d = m(d, a, b, c, f[e +  4], 11, 1272893353),
			c = m(c, d, a, b, f[e +  7], 16, 4139469664), b = m(b, c, d, a, f[e + 10], 23, 3200236656),
			a = m(a, b, c, d, f[e + 13],  4,  681279174), d = m(d, a, b, c, f[e +  0], 11, 3936430074),
			c = m(c, d, a, b, f[e +  3], 16, 3572445317), b = m(b, c, d, a, f[e +  6], 23,   76029189),
			a = m(a, b, c, d, f[e +  9],  4, 3654602809), d = m(d, a, b, c, f[e + 12], 11, 3873151461),
			c = m(c, d, a, b, f[e + 15], 16,  530742520), b = m(b, c, d, a, f[e +  2], 23, 3299628645),
			a = n(a, b, c, d, f[e +  0],  6, 4096336452), d = n(d, a, b, c, f[e +  7], 10, 1126891415),
			c = n(c, d, a, b, f[e + 14], 15, 2878612391), b = n(b, c, d, a, f[e +  5], 21, 4237533241),
			a = n(a, b, c, d, f[e + 12],  6, 1700485571), d = n(d, a, b, c, f[e +  3], 10, 2399980690),
			c = n(c, d, a, b, f[e + 10], 15, 4293915773), b = n(b, c, d, a, f[e +  1], 21, 2240044497),
			a = n(a, b, c, d, f[e +  8],  6, 1873313359), d = n(d, a, b, c, f[e + 15], 10, 4264355552),
			c = n(c, d, a, b, f[e +  6], 15, 2734768916), b = n(b, c, d, a, f[e + 13], 21, 1309151649),
			a = n(a, b, c, d, f[e +  4],  6, 4149444226), d = n(d, a, b, c, f[e + 11], 10, 3174756917),
			c = n(c, d, a, b, f[e +  2], 15,  718787259), b = n(b, c, d, a, f[e +  9], 21, 3951481745),
			a = h(a, q), b = h(b, r), c = h(c, s), d = h(d, t);
		}
		return (p(a) + p(b) + p(c) + p(d)).toLowerCase();
	},

	decodeBase64Str(str) {
		if (!str)
			return null;

		/* Thanks to luci-app-ssr-plus */
		str = str.replace(/-/g, '+').replace(/_/g, '/');
		let padding = (4 - str.length % 4) % 4;
		if (padding)
			str = str + Array(padding + 1).join('=');

		return decodeURIComponent(Array.prototype.map.call(atob(str), (c) =>
			'%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)
		).join(''));
	},

	getBuiltinFeatures() {
		const callGetSingBoxFeatures = rpc.declare({
			object: 'luci.homeproxy',
			method: 'singbox_get_features',
			expect: { '': {} }
		});

		return L.resolveDefault(callGetSingBoxFeatures(), {});
	},

	renderCronSelector(/* ... */) {
		if (!this._homeproxyCronOriginalFormvalue) {
			this._homeproxyCronOriginalFormvalue = this.formvalue;
			this.formvalue = function(section_id) {
				let cbid = this.cbid(section_id),
				    ids = [ cbid, 'widget.' + cbid ],
				    roots = [ document.getElementById('modal_overlay'), document ],
				    input = null;

				for (let root of roots) {
					if (!root)
						continue;

					for (let el of root.querySelectorAll('input')) {
						if (ids.includes(el.id) || ids.includes(el.name)) {
							input = el;
							break;
						}
					}

					if (input)
						break;
				}

				let value = input?.value ||
					this._homeproxyCronOriginalFormvalue?.call(this, section_id) ||
					this.default ||
					'0 0 * * *';

				return parseCron(value) ? value : (this.default || '0 0 * * *');
			};
		}

		let node = form.Value.prototype.renderWidget.apply(this, arguments),
		    editor = renderCronEditor(node.querySelector('input'));

		return editor || node;
	},

	renderCronSelectorRow(/* ... */) {
		return form.Value.prototype.render.apply(this, arguments);
	},

	generateRand(type, length) {
		let byteArr;
		if (['base64', 'hex'].includes(type))
			byteArr = crypto.getRandomValues(new Uint8Array(length));
		switch (type) {
			case 'base64':
				/* Thanks to https://stackoverflow.com/questions/9267899 */
				return btoa(String.fromCharCode.apply(null, byteArr));
			case 'hex':
				return Array.from(byteArr, (byte) =>
					(byte & 255).toString(16).padStart(2, '0')
				).join('');
			case 'uuid':
				/* Thanks to https://stackoverflow.com/a/2117523 */
				return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, (c) =>
					(c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
				);
			default:
				return null;
		};
	},

	loadDefaultLabel(uciconfig, ucisection) {
		if (!ucisection)
			return '';

		let label = uci.get(uciconfig, ucisection, 'label');
		if (label) {
			return label;
		} else {
			uci.set(uciconfig, ucisection, 'label', ucisection);
			return ucisection;
		}
	},

	loadModalTitle(title, addtitle, uciconfig, ucisection) {
		if (!ucisection)
			return addtitle;

		let label = uci.get(uciconfig, ucisection, 'label');
		return label ? title + ' » ' + label : addtitle;
	},

	normalizeSectionId(label, prefix) {
		let section_id = (label || '').trim().replace(/[^A-Za-z0-9_]/g, '_').replace(/^_+|_+$/g, '');
		return (prefix || 'cfg') + '_' + (section_id || 'section');
	},

	renderSectionAdd(section, extra_class) {
		let el = form.GridSection.prototype.renderSectionAdd.apply(section, [ extra_class ]),
			nameEl = el.querySelector('.cbi-section-create-name'),
			button = el.querySelector('.cbi-section-create > .cbi-button-add'),
			uciconfig = section.uciconfig || section.map.config,
			sectiontype = section.sectiontype,
			labelEl = E('input', {
				'type': 'text',
				'class': nameEl.className
			}),
			hintEl = E('div', { 'class': 'cbi-value-description' });

		nameEl.style.display = 'none';
		nameEl.parentNode.insertBefore(labelEl, nameEl);
		nameEl.parentNode.appendChild(hintEl);
		button.disabled = true;

		const syncSectionName = () => {
			let label = (labelEl.value || '').trim();
			hintEl.textContent = '';

			if (!label) {
				nameEl.value = '';
				button.disabled = true;
				return;
			}

			let duplicate = false;
			uci.sections(uciconfig, sectiontype, (res) => {
				if ((res.label || res['.name']) === label)
					duplicate = true;
			});

			if (duplicate) {
				nameEl.value = '';
				button.disabled = true;
				hintEl.textContent = _('Expecting: %s').format(_('unique value'));
				return;
			}

			let normalized = (label || '').trim().replace(/[^A-Za-z0-9_]/g, '_').replace(/^_+|_+$/g, '') || 'section',
			    section_id = (sectiontype || 'cfg') + '_' + normalized,
			    suffix = 1;
			while (uci.get(uciconfig, section_id))
				section_id = (sectiontype || 'cfg') + '_' + normalized + '_' + suffix++;

			nameEl.value = section_id;
			nameEl.dataset.sectionId = section_id;
			nameEl.dataset.sectionLabel = label;
			button.disabled = null;
		};

		labelEl.addEventListener('input', syncSectionName);
		labelEl.addEventListener('blur', syncSectionName);

		button.addEventListener('click', () => {
			syncSectionName();

			let label = nameEl.dataset.sectionLabel,
			    section_id = nameEl.dataset.sectionId;

			window.setTimeout(() => {
				if (label && section_id && uci.get(uciconfig, section_id))
					uci.set(uciconfig, section_id, 'label', label);
			}, 0);
		});

		return el;
	},

	installCloseButtonText() {
		if (window.__homeproxyCloseButtonText)
			return;

		window.__homeproxyCloseButtonText = true;

		let fix = (root) => {
			for (let el of (root || document).querySelectorAll('button, .btn, input[type="button"], input[type="submit"]')) {
				let text = (el.textContent || el.value || '').trim();
				if (text !== 'Dismiss' && text !== '\u5ffd\u7565')
					continue;

				if ('value' in el && !el.textContent.trim())
					el.value = _('Close');
				else
					el.textContent = _('Close');
			}
		};

		let observe = () => {
			if (!document.body)
				return;

			fix(document);
			new MutationObserver((mutations) => {
				for (let mutation of mutations)
					for (let node of mutation.addedNodes)
						if (node.nodeType === 1)
							fix(node);
				fix(document);
			}).observe(document.body, { childList: true, subtree: true });
		};

		if (document.body)
			observe();
		else
			document.addEventListener('DOMContentLoaded', observe, { once: true });
	},

	uploadCertificate(_option, type, filename, ev) {
		const callWriteCertificate = rpc.declare({
			object: 'luci.homeproxy',
			method: 'certificate_write',
			params: ['filename'],
			expect: { '': {} }
		});

		return ui.uploadFile('/tmp/homeproxy_certificate.tmp', ev.target)
		.then(L.bind((_btn, res) => {
			return L.resolveDefault(callWriteCertificate(filename), {}).then((ret) => {
				if (ret.result === true)
					ui.addNotification(null, E('p', _('Your %s was successfully uploaded. Size: %sB.').format(type, res.size)));
				else
					ui.addNotification(null, E('p', _('Failed to upload %s, error: %s.').format(type, ret.error)));
			});
		}, this, ev.target))
		.catch((e) => { ui.addNotification(null, E('p', e.message)) });
	},

	uploadPanel(_option, ev) {
		const callInstallPanel = rpc.declare({
			object: 'luci.homeproxy',
			method: 'clash_api_install_panel',
			expect: { '': {} }
		});

		const normalizeMessage = (message) => {
			switch (message) {
			case 'panel_backup_failed':
				return _('Backup panel failed.');
			case 'panel_restore_failed':
				return _('Restore panel failed.');
			case 'empty_panel_zip':
				return _('Panel ZIP file is empty.');
			case 'unzip_unavailable':
				return _('The unzip command is unavailable.');
			case 'invalid_panel_zip':
				return _('Invalid panel ZIP file.');
			case 'panel_install_failed':
				return _('Install panel failed.');
			default:
				return message || _('unknown error');
			}
		};

		return ui.uploadFile('/tmp/homeproxy_panel.tmp', ev.target)
		.then(L.bind((_btn, res) => {
			return L.resolveDefault(callInstallPanel(), {}).then((ret) => {
				if (ret.result === true)
					ui.addNotification(null, E('p', _('Your %s was successfully uploaded. Size: %sB.').format(_('panel ZIP package'), res.size)), 'info');
				else
					ui.addNotification(null, E('p', _('Failed to upload %s, error: %s.').format(_('panel ZIP package'), normalizeMessage(ret.error))), 'danger');
			});
		}, this, ev.target))
		.catch((e) => { ui.addNotification(null, E('p', e.message || e), 'danger') });
	},

	validateBase64Key(length, section_id, value) {
		/* Thanks to luci-proto-wireguard */
		if (section_id && value)
			if (value.length !== length || !value.match(/^(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?$/) || value[length-1] !== '=')
				return _('Expecting: %s').format(_('valid base64 key with %d characters').format(length));

		return true;
	},

	validateCertificatePath(section_id, value) {
		if (section_id && value)
			if (!value.match(/^(\/etc\/homeproxy\/certs\/|\/etc\/acme\/|\/etc\/ssl\/).+$/))
				return _('Expecting: %s').format(_('/etc/homeproxy/certs/..., /etc/acme/..., /etc/ssl/...'));

		return true;
	},

	validatePortRange(section_id, value) {
		if (section_id && value) {
			value = value.match(/^(\d+)?\:(\d+)?$/);
			if (value && (value[1] || value[2])) {
				if (!value[1])
					value[1] = 0;
				else if (!value[2])
					value[2] = 65535;

				if (value[1] < value[2] && value[2] <= 65535)
					return true;
			}

			return _('Expecting: %s').format( _('valid port range (port1:port2)'));
		}

		return true;
	},

	validateUniqueValue(uciconfig, ucisection, ucioption, section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			if (ucioption === 'node' && (value === 'urltest' || value === 'selector'))
				return true;

			let duplicate = false;
			uci.sections(uciconfig, ucisection, (res) => {
				if (res['.name'] !== section_id)
					if (res[ucioption] === value)
						duplicate = true
			});
			if (duplicate)
				return _('Expecting: %s').format(_('unique value'));
		}

		return true;
	},

	validateUUID(section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			else if (value.match('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') === null)
				return _('Expecting: %s').format(_('valid uuid'));
		}

		return true;
	}
});
