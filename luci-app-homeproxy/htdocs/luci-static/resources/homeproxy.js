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

return baseclass.extend({
	dns_strategy: {
		'': _('Default'),
		'prefer_ipv4': _('Prefer IPv4'),
		'prefer_ipv6': _('Prefer IPv6'),
		'ipv4_only': _('IPv4 only'),
		'ipv6_only': _('IPv6 only')
	},

	/* Curated rule sets from MetaCubeX/meta-rules-dat@sing/geo.
	 * Keys are "<category>/<name>" identifiers, expanded to download URLs
	 * by generate_client.uc. Names are proper nouns and need no translation. */
	simple_rule_sets: {
		/* These China domain sets have different scopes and do not fully
		 * contain each other: cn is the broad list (tld-cn is a subset of
		 * it), geolocation-cn is geography based. Select both for full
		 * coverage of domestic domains. */
		'geosite/geolocation-cn': 'GeoSite · geolocation-cn (China, by geography)',
		'geosite/geolocation-!cn': 'GeoSite · geolocation-!cn (non-China)',
		'geosite/cn': 'GeoSite · cn (China, broad)',
		'geosite/gfw': 'GeoSite · gfw',
		'geosite/private': 'GeoSite · private (LAN)',
		'geosite/category-ads-all': 'GeoSite · category-ads-all',
		'geosite/category-ai-!cn': 'GeoSite · category-ai-!cn',
		'geosite/category-dev': 'GeoSite · category-dev',
		'geosite/category-games': 'GeoSite · category-games',
		'geosite/category-media': 'GeoSite · category-media',
		'geosite/category-scholar-!cn': 'GeoSite · category-scholar-!cn',
		'geosite/category-social-media-!cn': 'GeoSite · category-social-media-!cn',
		'geosite/openai': 'GeoSite · openai',
		'geosite/google': 'GeoSite · google',
		'geosite/youtube': 'GeoSite · youtube',
		'geosite/github': 'GeoSite · github',
		'geosite/telegram': 'GeoSite · telegram',
		'geosite/twitter': 'GeoSite · twitter',
		'geosite/facebook': 'GeoSite · facebook',
		'geosite/instagram': 'GeoSite · instagram',
		'geosite/apple': 'GeoSite · apple',
		'geosite/microsoft': 'GeoSite · microsoft',
		'geosite/netflix': 'GeoSite · netflix',
		'geosite/disney': 'GeoSite · disney',
		'geosite/spotify': 'GeoSite · spotify',
		'geosite/bilibili': 'GeoSite · bilibili',
		'geosite/steam': 'GeoSite · steam',
		'geosite/tiktok': 'GeoSite · tiktok',
		'geosite/discord': 'GeoSite · discord',
		'geosite/reddit': 'GeoSite · reddit',
		/* Additional categories */
		'geosite/category-porn': 'GeoSite · category-porn (adult)',
		'geosite/category-finance': 'GeoSite · category-finance',
		'geosite/category-entertainment': 'GeoSite · category-entertainment',
		'geosite/category-cryptocurrency': 'GeoSite · category-cryptocurrency',
		'geosite/category-speedtest': 'GeoSite · category-speedtest',
		'geosite/tld-cn': 'GeoSite · tld-cn (China TLDs, included in cn)',
		/* AI services */
		'geosite/anthropic': 'GeoSite · anthropic (Claude)',
		'geosite/huggingface': 'GeoSite · huggingface',
		'geosite/deepseek': 'GeoSite · deepseek',
		'geosite/perplexity': 'GeoSite · perplexity',
		'geosite/xai': 'GeoSite · xai (Grok)',
		/* Streaming and video */
		'geosite/hbo': 'GeoSite · hbo (HBO Max)',
		'geosite/primevideo': 'GeoSite · primevideo (Prime Video)',
		'geosite/hulu': 'GeoSite · hulu',
		'geosite/abema': 'GeoSite · abema (Japan)',
		'geosite/niconico': 'GeoSite · niconico (Japan)',
		'geosite/bahamut': 'GeoSite · bahamut (Taiwan)',
		'geosite/twitch': 'GeoSite · twitch (live streaming)',
		'geosite/dailymotion': 'GeoSite · dailymotion',
		/* Messaging and social */
		'geosite/whatsapp': 'GeoSite · whatsapp',
		'geosite/signal': 'GeoSite · signal',
		'geosite/line': 'GeoSite · line',
		'geosite/messenger': 'GeoSite · messenger',
		'geosite/linkedin': 'GeoSite · linkedin',
		/* Game platforms */
		'geosite/playstation': 'GeoSite · playstation',
		'geosite/xbox': 'GeoSite · xbox',
		'geosite/nintendo': 'GeoSite · nintendo',
		'geosite/epicgames': 'GeoSite · epicgames',
		'geosite/ea': 'GeoSite · ea (Electronic Arts)',
		'geosite/blizzard': 'GeoSite · blizzard',
		/* Cloud and development */
		'geosite/cloudflare': 'GeoSite · cloudflare',
		'geosite/docker': 'GeoSite · docker',
		'geosite/aws': 'GeoSite · aws (Amazon Web Services)',
		'geosite/gitlab': 'GeoSite · gitlab',
		/* Payments */
		'geosite/paypal': 'GeoSite · paypal',
		'geosite/stripe': 'GeoSite · stripe',
		/* Mainland China services */
		'geosite/baidu': 'GeoSite · baidu',
		'geosite/alibaba': 'GeoSite · alibaba',
		'geosite/tencent': 'GeoSite · tencent',
		'geosite/douyin': 'GeoSite · douyin (TikTok China)',
		'geosite/iqiyi': 'GeoSite · iqiyi',
		'geosite/youku': 'GeoSite · youku',
		'geoip/cn': 'GeoIP · cn (China)',
		'geoip/private': 'GeoIP · private (LAN)',
		/* Service / provider IP sets: small and ideal for apps dialing IPs directly */
		'geoip/cloudflare': 'GeoIP · cloudflare',
		'geoip/cloudfront': 'GeoIP · cloudfront (AWS CDN)',
		'geoip/facebook': 'GeoIP · facebook (Meta)',
		'geoip/fastly': 'GeoIP · fastly (CDN)',
		'geoip/google': 'GeoIP · google (Google / YouTube)',
		'geoip/netflix': 'GeoIP · netflix',
		'geoip/telegram': 'GeoIP · telegram',
		'geoip/tor': 'GeoIP · tor (Tor nodes)',
		'geoip/twitter': 'GeoIP · twitter (X)',
		/* Country / region IP sets */
		'geoip/ae': 'GeoIP · ae',
		'geoip/ar': 'GeoIP · ar',
		'geoip/at': 'GeoIP · at',
		'geoip/au': 'GeoIP · au',
		'geoip/be': 'GeoIP · be',
		'geoip/br': 'GeoIP · br',
		'geoip/ca': 'GeoIP · ca',
		'geoip/ch': 'GeoIP · ch',
		'geoip/cz': 'GeoIP · cz',
		'geoip/de': 'GeoIP · de',
		'geoip/dk': 'GeoIP · dk',
		'geoip/es': 'GeoIP · es',
		'geoip/fi': 'GeoIP · fi',
		'geoip/fr': 'GeoIP · fr',
		'geoip/gb': 'GeoIP · gb',
		'geoip/hk': 'GeoIP · hk',
		'geoip/id': 'GeoIP · id',
		'geoip/ie': 'GeoIP · ie',
		'geoip/il': 'GeoIP · il',
		'geoip/in': 'GeoIP · in',
		'geoip/it': 'GeoIP · it',
		'geoip/jp': 'GeoIP · jp',
		'geoip/kr': 'GeoIP · kr',
		'geoip/mx': 'GeoIP · mx',
		'geoip/my': 'GeoIP · my',
		'geoip/nl': 'GeoIP · nl',
		'geoip/no': 'GeoIP · no',
		'geoip/nz': 'GeoIP · nz',
		'geoip/ph': 'GeoIP · ph',
		'geoip/pl': 'GeoIP · pl',
		'geoip/pt': 'GeoIP · pt',
		'geoip/ru': 'GeoIP · ru',
		'geoip/sa': 'GeoIP · sa',
		'geoip/se': 'GeoIP · se',
		'geoip/sg': 'GeoIP · sg',
		'geoip/th': 'GeoIP · th',
		'geoip/tr': 'GeoIP · tr',
		'geoip/tw': 'GeoIP · tw',
		'geoip/ua': 'GeoIP · ua',
		'geoip/us': 'GeoIP · us',
		'geoip/vn': 'GeoIP · vn',
		'geoip/za': 'GeoIP · za'
	},

	/* Base URLs the "category/name" identifiers above are appended to. */
	simple_ruleset_url_bases: {
		'https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo': _('jsDelivr CDN'),
		'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo': _('jsDelivr CDN (Fastly)'),
		'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo': _('GitHub raw')
	},

	/* Normalize the order of a selected rule set list before it is written to
	 * UCI. Known sets follow the order of the dropdown (passed as `order`),
	 * any leftover value is sorted alphabetically at the end. Pass no `order`
	 * for a plain alphabetical sort. The widget itself is left untouched, so
	 * newly picked items still appear at the bottom until the form is saved. */
	sortRuleSetValues: function(values, order) {
		if (!Array.isArray(values))
			return values;

		let rank = Object.create(null), i = 0;
		for (let key in order || {})
			rank[key] = i++;

		return values.slice().sort((a, b) => {
			let ra = rank[a], rb = rank[b];

			if (ra != null && rb != null)
				return ra - rb;
			if (ra != null)
				return -1;
			if (rb != null)
				return 1;

			return (a < b) ? -1 : (a > b) ? 1 : 0;
		});
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

			/* DynamicList only greys out a choice when it is picked from the
			 * dropdown. Values loaded from UCI are rendered as items directly,
			 * so editing an existing section would leave them selectable. */
			if (!this.allowduplicates) {
				let values = [];
				dl.querySelectorAll('.item > input[type="hidden"]').forEach((input) => {
					values.push(input.value);
				});

				dl.querySelectorAll('.add-item ul > li[data-value]').forEach((li) => {
					if (values.includes(li.getAttribute('data-value')))
						li.setAttribute('unselectable', '');
				});
			}

			return dl;
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
		let label = uci.get(uciconfig, ucisection, 'label');
		if (label) {
			return label;
		} else {
			uci.set(uciconfig, ucisection, 'label', ucisection);
			return ucisection;
		}
	},

	loadModalTitle(title, addtitle, uciconfig, ucisection) {
		let label = uci.get(uciconfig, ucisection, 'label');
		return label ? title + ' » ' + label : addtitle;
	},

	renderSectionAdd(section, extra_class) {
		let el = form.GridSection.prototype.renderSectionAdd.apply(section, [ extra_class ]),
			nameEl = el.querySelector('.cbi-section-create-name');
		ui.addValidator(nameEl, 'uciname', true, (v) => {
			let button = el.querySelector('.cbi-section-create > .cbi-button-add');
			let uciconfig = section.uciconfig || section.map.config;

			if (!v) {
				button.disabled = true;
				return true;
			} else if (uci.get(uciconfig, v)) {
				button.disabled = true;
				return _('Expecting: %s').format(_('unique UCI identifier'));
			} else {
				button.disabled = null;
				return true;
			}
		}, 'blur', 'keyup');

		return el;
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
			let m = value.match(/^(\d+)?\:(\d+)?$/);
			if (m && (m[1] || m[2])) {
				/* Capture groups are strings: comparing them directly would
				 * use lexicographic order ("5" < "100" is false). */
				let start = m[1] ? parseInt(m[1], 10) : 0,
				    end = m[2] ? parseInt(m[2], 10) : 65535;

				if (start >= 0 && start < end && end <= 65535)
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
			if (ucioption === 'node' && value === 'urltest')
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
