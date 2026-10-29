'use strict';
'require view';
'require fs';
'require ui';

/*
 * LuCI 概览页：运营商分流状态
 *
 * 数据来源（两次只读调用，均由 rpcd file.exec 执行）：
 *   isp-split status --json  → 每个集合的条目数/命中包/流量 + 兜底计数
 *   isp-split health --json  → 源健康度、双线状态、策略占比、数据时间、最近 diff
 *
 * 页面只用原生 DOM（LuCI 的 E()）+ 一份静态 CSS，没有构建工具、没有外链资源：
 * 路由器离线时图标与样式照常显示。
 *
 * 为什么不用 LuCI 的 poll 模块：`poll.add()` 会触发 document 级的 poll-start 事件，
 * 主题随之在顶栏弹出英文 "Refreshing" 徽标（luci.js: showIndicator(_('Refreshing'))），
 * 中文界面里很突兀，而且位置离数据很远。这里改成自己的定时器 + 页面内中文徽标
 * 「刷新中…」，用户看到的是同一处状态点。
 */

var CMD = '/usr/sbin/isp-split';
var REFRESH_SEC = 10;

/* ---------------------------------------------------------------- 图标（内联 SVG，无外链） */

var ICONS = {
	refresh: '<path d="M20 11a8 8 0 1 0-2.3 6.3"/><path d="M20 4v7h-7"/>',
	pause: '<rect x="7" y="5" width="3.2" height="14" rx="1"/><rect x="13.8" y="5" width="3.2" height="14" rx="1"/>',
	play: '<path d="M8 5.5v13l11-6.5z"/>',
	sync: '<path d="M4 7h11a4 4 0 0 1 0 8H9"/><path d="M7 4 4 7l3 3"/><path d="M20 17H9a4 4 0 0 1 0-8h6"/><path d="M17 20l3-3-3-3"/>',
	download: '<path d="M12 4v10"/><path d="M8 10l4 4 4-4"/><path d="M5 19h14"/>',
	check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
	tel: '<path d="M12 9v12"/><circle cx="12" cy="5" r="2"/><path d="M8.6 8.4a5 5 0 0 1 6.8 0"/><path d="M6 5.8a8.4 8.4 0 0 1 12 0"/>',
	uni: '<circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M8 6h8"/><path d="M7 8l4 8"/><path d="M17 8l-4 8"/>',
	cmcc: '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 18h2"/>',
	cernet: '<path d="M3 9.5 12 5l9 4.5-9 4.5z"/><path d="M7 11.5V16c0 1.2 2.2 2.2 5 2.2s5-1 5-2.2v-4.5"/>',
	other: '<circle cx="12" cy="12" r="7"/><path d="M12 5v14"/>',
	/* 兜底流量卡的身份 glyph：地球 + 经纬线（"未归属任何运营商"的那部分流量）。
	   与上面一族同为 24 格 stroke 线稿（stroke-width 1.8、round 收口），
	   44px 下线条不会糊；颜色走 currentColor，深浅主题都不用另做一套。 */
	net: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/>' +
		'<path d="M12 3.5c2.4 2.4 3.8 5.4 3.8 8.5s-1.4 6.1-3.8 8.5"/>' +
		'<path d="M12 3.5C9.6 5.9 8.2 8.9 8.2 12s1.4 6.1 3.8 8.5"/>'
};

var GLYPH_FOR = {
	chinatelecom: 'tel', chinanet: 'tel', telecom: 'tel',
	unicom_cnc: 'uni', unicom: 'uni',
	cmcc: 'cmcc', mobile: 'cmcc',
	cernet: 'cernet'
};

/* 品牌 logo（运营商官方风格标志，192×192 透明底 PNG，静态文件按请求加载）。
   0.3.1 起换图不换名：文件名仍是 logo-<运营商>，只把扩展名从 .svg 改成 .png。
   PNG 是位图，深浅两个主题共用一份即可（透明底天然跟随背景）。 */
var BRAND_LOGO = {
	chinatelecom: 'logo-chinatelecom.png',
	chinanet: 'logo-chinatelecom.png',
	telecom: 'logo-chinatelecom.png',
	unicom_cnc: 'logo-unicom.png',
	unicom: 'logo-unicom.png',
	cmcc: 'logo-mobile.png',
	mobile: 'logo-mobile.png'
};

/* 卡头图标统一 44px：logo 与「无 logo 的 glyph 占位」同尺寸，视觉同构 */
var HEAD_ICO = 44;

function brandLogo(src, size) {
	var file = BRAND_LOGO[src];
	if (!file)
		return null;
	var img = document.createElement('img');
	img.src = L.resource('isp-split/logos/' + file);
	img.alt = src;
	img.width = size || HEAD_ICO;
	img.height = size || HEAD_ICO;
	img.className = 'isp-brand-logo';
	return img;
}

function svgIcon(name, size) {
	var span = document.createElement('span');
	span.className = 'isp-ico';
	span.innerHTML = '<svg viewBox="0 0 24 24" width="' + (size || 18) + '" height="' + (size || 18) +
		'" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
		'stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || ICONS.other) + '</svg>';
	return span;
}

/* ---------------------------------------------------------------- 格式化 */

function fmtNum(n) {
	n = +n || 0;
	return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function fmtBytes(n) {
	n = +n || 0;
	var u = ['B', 'KiB', 'MiB', 'GiB', 'TiB'], i = 0;
	while (n >= 1024 && i < u.length - 1) {
		n /= 1024;
		i++;
	}
	return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + ' ' + u[i];
}

function accentOf(src) {
	return 'var(--isp-accent-' + (GLYPH_FOR[src] || 'other') + ')';
}

/*
 * cron 表达式 → 人话（分 时 日 月 周）。
 * 只翻译最常见、能一眼看懂的形状；认不出来的原样返回，宁可显示原文也不猜错。
 *   17 4 * * *   → 每天 04:17
 *   30 3 * * 1   → 每周一 03:30
 *   5 2 1 * *    → 每月 1 日 02:05
 */
var DOW_NAMES = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

function humanCron(expr) {
	var f = String(expr || '').trim().split(/\s+/);

	if (f.length !== 5)
		return '';

	function num(s) {
		return /^\d+$/.test(s) ? +s : null;
	}

	var min = num(f[0]);
	var hour = num(f[1]);
	if (min === null || hour === null || min > 59 || hour > 23)
		return '';

	var hhmm = (hour < 10 ? '0' : '') + hour + ':' + (min < 10 ? '0' : '') + min;
	var dom = num(f[2]);
	var dow = num(f[4]);

	if (f[2] === '*' && f[3] === '*' && f[4] === '*')
		return _('每天 ') + hhmm;

	if (f[2] === '*' && f[3] === '*' && dow !== null && dow <= 7)
		return _('每') + DOW_NAMES[dow % 7] + ' ' + hhmm;

	if (f[4] === '*' && f[3] === '*' && f[2] !== '*' && dom !== null)
		return _('每月 ') + dom + _(' 日 ') + hhmm;

	return '';
}

/* mwan3 的线路状态是英文枚举，界面上统一显示中文；原文留在 title 里备查 */
function stateText(state) {
	if (state === 'online')
		return _('在线');
	if (state === 'offline')
		return _('离线');
	return _('未知');
}

/* ---------------------------------------------------------------- 数据解析 */

function parseJson(res) {
	try {
		return JSON.parse(((res && res.stdout) || '').trim() || 'null');
	} catch (e) {
		return null;
	}
}

function policyMembers(health, policy) {
	var list = (health && health.policies) || [];
	for (var i = 0; i < list.length; i++)
		if (list[i].name === policy)
			return list[i].members || [];
	return [];
}

/* 策略里出现过的线路，按出现顺序编号：第一条 = 左，第二条 = 右 */
function lineOrder(health) {
	var order = [];
	((health && health.policies) || []).forEach(function(p) {
		(p.members || []).forEach(function(m) {
			if (order.indexOf(m.iface) < 0)
				order.push(m.iface);
		});
	});
	return order;
}

function activeLines(health) {
	var order = lineOrder(health);
	var used = {};
	((health && health.policies) || []).forEach(function(p) {
		(p.members || []).forEach(function(m) {
			if (+m.pct > 0)
				used[m.iface] = true;
		});
	});
	var out = order.filter(function(iface) { return used[iface]; });
	return out.length ? out : order;
}

function lineInfo(health, iface) {
	var lines = (health && health.lines) || [];
	for (var i = 0; i < lines.length; i++)
		if (lines[i].iface === iface)
			return lines[i];
	return null;
}

function lineShares(health, iface) {
	var out = [];
	((health && health.policies) || []).forEach(function(p) {
		(p.members || []).forEach(function(m) {
			if (m.iface === iface && +m.pct > 0)
				out.push({ policy: p.name, pct: +m.pct });
		});
	});
	return out;
}

/* ---------------------------------------------------------------- 视图 */

return view.extend({
	exec: function(args) {
		return fs.exec(CMD, args).then(function(res) {
			if (res && res.code) {
				var out = ((res.stdout || '') + (res.stderr || '')).trim();
				throw new Error('isp-split ' + args.join(' ') +
					' 失败（退出码 ' + res.code + '）' + (out ? '：' + out : ''));
			}
			return res;
		});
	},

	/* 只读 JSON 调用：失败不抛出，交给页面显示一行告警 */
	readJson: function(args) {
		return fs.exec(CMD, args).then(function(res) {
			var data = parseJson(res);
			if (res && res.code && !data)
				throw new Error((((res.stdout || '') + (res.stderr || '')).trim()) ||
					('退出码 ' + res.code));
			return data;
		});
	},

	setOut: function(text) {
		var out = document.getElementById('isp-out');
		if (out) {
			out.textContent = text;
			out.scrollTop = 0;
		}
	},

	run: function(args, label, confirmText) {
		var self = this;

		var doRun = function() {
			self.setOut('正在执行：isp-split ' + args.join(' ') + ' …');
			return self.exec(args).then(function(res) {
				self.setOut(((res.stdout || '') + (res.stderr || '')) || '(无输出)');
				ui.addNotification(null, E('p', {}, [label + ' 已完成']), 'info');
				return self.refresh();
			}).catch(function(err) {
				self.setOut('执行失败：' + String(err));
				ui.addNotification(null, E('p', {}, ['执行失败：' + String(err)]), 'danger');
			});
		};

		if (!confirmText)
			return doRun();

		return ui.showModal(_('确认'), [
			E('p', {}, [confirmText]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, [_('取消')]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': function() { ui.hideModal(); doRun(); }
				}, [_('确认执行')])
			])
		]);
	},

	refresh: function() {
		var self = this;

		/* 上一轮还没回来就不再叠一次取数（10s 一跳，网络慢时很容易叠） */
		if (this._inflight)
			return this._inflight;

		this.busy = true;
		this.paintPill();

		var done = function() {
			self._inflight = null;
			self.busy = false;
			self.paintPill();
		};

		this._inflight = Promise.all([
			this.readJson(['status', '--json']).catch(function(e) {
				return { __error: String(e) };
			}),
			this.readJson(['health', '--json']).catch(function(e) {
				return { __error: String(e) };
			})
		]).then(function(res) {
			self.status = Array.isArray(res[0]) ? res[0] : [];
			self.statusError = res[0] && res[0].__error;
			self.health = (res[1] && !res[1].__error) ? res[1] : {};
			self.healthError = res[1] && res[1].__error;
			self.paint();
		}).then(done, done);

		return this._inflight;
	},

	/* 状态徽标：正常「自动刷新 10s」/ 取数中「刷新中…」+ 转圈 / 暂停「已暂停」 */
	paintPill: function() {
		var pill = this._pill;
		if (!pill || !pill.parentNode)
			return;

		var icon = this._pillIcon;
		var text = this._pillText;

		while (icon.firstChild)
			icon.removeChild(icon.firstChild);

		var cls = 'isp-pill';

		if (this.paused) {
			cls += ' is-paused';
			icon.appendChild(E('span', { 'class': 'isp-dot' }));
			text.textContent = _('已暂停');
		}
		else if (this.busy) {
			cls += ' is-busy';
			var spin = svgIcon('refresh', 13);
			spin.className = 'isp-ico isp-spin';
			icon.appendChild(spin);
			text.textContent = _('刷新中…');
		}
		else {
			icon.appendChild(E('span', { 'class': 'isp-dot' }));
			text.textContent = _('自动刷新 ' + REFRESH_SEC + 's');
		}

		pill.className = cls;
	},

	/* ---------------- 运营商卡片 ---------------- */

	paintOps: function() {
		var self = this;
		var box = document.getElementById('isp-cards');
		if (!box)
			return;

		while (box.firstChild)
			box.removeChild(box.firstChild);

		var rows = (this.status || []).filter(function(r) {
			/* B-1：注释行不是运营商行。shell 侧已过滤，这里兜底，
			   防止旧脚本/手工数据在总览页多出一张卡片。 */
			if (!r || r.set === '兜底')
				return false;
			if (/^\s*#/.test(String(r.set || '')) || /^\s*#/.test(String(r.src || '')))
				return false;
			/* D1-3：教育网（cernet）退出状态页，纯 UI 退场。
			   后端数据行照旧保留（status --json / 诊断 / 导出都不受影响），
			   只是这一版不把它算进运营商网格：cernet 用户量小，指标常年为空，
			   混在电信/联通/移动里只会稀释「一眼看三家」的信息密度。
			   set 名与 src 一起判：ISP_TABLE 里 cernet 的集合名可以改，
			   src 改不了。 */
			if (r.src === 'cernet' || r.set === 'isp_cernet')
				return false;
			return true;
		});

		if (!rows.length) {
			box.appendChild(E('div', { 'class': 'isp-empty' }, [
				this.statusError
					? _('读取状态失败：') + this.statusError
					: _('没有启用的运营商。检查 /etc/isp-split.conf 里的 ISP_TABLE。')
			]));
		}

		var maxPackets = 0;
		rows.forEach(function(r) { maxPackets = Math.max(maxPackets, +r.packets || 0); });

		rows.forEach(function(r) {
			var accent = accentOf(r.src);
			var members = policyMembers(self.health, r.policy);
			var order = lineOrder(self.health);
			var active = members.filter(function(m) { return +m.pct > 0; });
			var arrows = '·';
			var routeText = _('策略无在线成员');

			if (active.length > 1) {
				arrows = '◀▶';
				routeText = active.map(function(m) { return m.iface; }).join(' + ');
			} else if (active.length === 1) {
				arrows = (order.indexOf(active[0].iface) <= 0) ? '◀' : '▶';
				routeText = active[0].iface + ' ' + active[0].pct + '%';
			}

			var packets = +r.packets || 0;
			var pct = maxPackets > 0
				? Math.max(2, Math.round(packets * 100 / maxPackets))
				: 0;

			box.appendChild(E('article', {
				'class': 'isp-card isp-card-op',
				'style': '--isp-accent: ' + accent
			}, [
				E('div', { 'class': 'isp-card-head' }, [
					/* 方案 B：logo 44px 左置 + 运营商名。
					   没有品牌 logo 的来源（自定义源 / other）走同一尺寸的 glyph 占位，
					   两张卡并排时卡头高度与基线一致，不会一张高一卡矮。 */
					E('span', { 'class': 'isp-op-ico' }, [
						brandLogo(r.src) || svgIcon(GLYPH_FOR[r.src] || 'other', HEAD_ICO)
					]),
					E('span', { 'class': 'isp-op-name' }, [ r.label || r.src ])
				]),
				E('div', {}, [
					E('span', { 'class': 'isp-big' }, [ r.exists ? fmtNum(packets) : '—' ]),
					E('span', { 'class': 'isp-unit' }, [ _('命中包') ])
				]),
				E('div', { 'class': 'isp-op-sub' }, [
					r.exists
						? _('流量 ') + fmtBytes(r.bytes) + ' · ' + _('条目 ') + fmtNum(r.elements)
						: _('集合不存在（等待 wire/apply）')
				]),
				E('div', { 'class': 'isp-route' }, [
					E('span', { 'class': 'isp-arrows' }, [ arrows ]),
					E('span', {}, [ routeText ]),
					E('span', { 'class': 'isp-tag' }, [ r.policy ])
				]),
				/* 零流量时不画进度条：2% 的最小宽度会缩成一个孤零零的色点，
				   看起来像渲染坏了。改成一个「—」，标题里说明原因。 */
				packets > 0
					? E('div', { 'class': 'isp-meter' }, [
						E('i', { 'style': 'width:' + pct + '%' })
					])
					: E('div', {
						'class': 'isp-meter-empty',
						'title': r.exists ? _('暂无命中流量') : _('集合尚未生效')
					}, [ '—' ])
			]));
		});

		/* D1-4：兜底流量并入同一张运营商网格，成为「第 4 张卡」。
		   桌面四列（.isp-cards 是 repeat(4)）：三家运营商 + 兜底正好一行四格；
		   ISP_TABLE 多开运营商时按四列继续换行，兜底始终排在最后，不会被挤到
		   另一行只剩一半宽。卡头与运营商卡同构：44px glyph + 名称。
		   内容由 paintFallback() 写进 #isp-fallback（paintOps 之后调用）。 */
		box.appendChild(E('article', {
			'class': 'isp-card isp-card-op isp-card-fb',
			'style': '--isp-accent: var(--isp-accent-other)'
		}, [
			E('div', { 'class': 'isp-card-head' }, [
				E('span', { 'class': 'isp-op-ico' }, [ svgIcon('net', HEAD_ICO) ]),
				E('span', { 'class': 'isp-op-name' }, [ _('兜底流量') ])
			]),
			E('div', { 'id': 'isp-fallback' })
		]));
	},

	/* ---------------- 双线健康 ---------------- */

	paintLines: function() {
		var box = document.getElementById('isp-lines');
		if (!box)
			return;

		while (box.firstChild)
			box.removeChild(box.firstChild);

		var health = this.health || {};
		var ifaces = activeLines(health);

		if (!ifaces.length) {
			box.appendChild(E('div', { 'class': 'isp-empty' }, [
				_('读不到 mwan3 的线路状态（mwan3 未运行，或策略里没有成员）。')
			]));
			return;
		}

		var list = E('div', { 'class': 'isp-list' });
		ifaces.forEach(function(iface) {
			var info = lineInfo(health, iface) || {};
			var state = info.state || 'unknown';
			var cls = 'isp-line' + (state === 'online' ? ' is-online'
				: (state === 'offline' ? ' is-offline' : ''));
			var tracks = (info.tracks || []).map(function(t) {
				return t.ip + ':' + t.state;
			}).join('  ');

			var shares = lineShares(health, iface).map(function(s) {
				return s.policy + ' ' + s.pct + '%';
			}).join(' · ');

			/* 这一列只剩 1fr 的窄位，塞「online · tracking active · IP:up」必然被
			   ellipsis 截成 "tracking activ…"。正文只留两个字，全文进 title。 */
			var detail = state
				+ (info.tracking ? ' · tracking ' + info.tracking : '')
				+ (tracks ? ' · ' + tracks : '');

			list.appendChild(E('div', { 'class': cls }, [
				E('span', { 'class': 'isp-dot' }),
				E('span', { 'class': 'isp-line-name' }, [ iface ]),
				E('span', {
					'class': 'isp-line-track',
					'title': iface + ' · ' + detail
				}, [ stateText(state) ]),
				E('span', { 'class': 'isp-line-pct' }, [ shares || _('未参与策略') ])
			]));
		});
		box.appendChild(list);
	},

	/* ---------------- 兜底流量（第 4 张运营商卡的主体） ----------------
	   口径与 0.3.0 完全一致：未命中任何运营商集合的连接数（首包）与流量。
	   卡头在 paintOps() 里画（44px glyph + 名称），这里只负责主体，
	   字号/间距与运营商卡的 isp-big / isp-op-sub 同一套类名，因此
	   两张卡的数字基线和单位位置自然对齐。 */

	paintFallback: function() {
		var box = document.getElementById('isp-fallback');
		if (!box)
			return;

		while (box.firstChild)
			box.removeChild(box.firstChild);

		var fb = null;
		(this.status || []).forEach(function(r) {
			if (r && r.set === '兜底')
				fb = r;
		});

		if (!fb || !fb.exists) {
			box.appendChild(E('div', { 'class': 'isp-empty' }, [
				_('兜底计数器不存在。执行「同步生效」或确认 COUNT_FALLBACK=1。')
			]));
			return;
		}

		box.appendChild(E('div', {}, [
			E('span', { 'class': 'isp-big' }, [ fmtNum(fb.packets) ]),
			E('span', { 'class': 'isp-unit' }, [ _('连接（首包）') ])
		]));
		box.appendChild(E('div', { 'class': 'isp-op-sub' }, [
			_('流量 ') + fmtBytes(fb.bytes) + ' · ' + _('未命中任何运营商集合')
		]));
	},

	/* ---------------- 数据源健康度 ---------------- */

	paintSources: function() {
		var box = document.getElementById('isp-sources');
		if (!box)
			return;

		while (box.firstChild)
			box.removeChild(box.firstChild);

		var health = this.health || {};
		var srcs = health.sources || [];

		if (!srcs.length) {
			box.appendChild(E('div', { 'class': 'isp-empty' }, [
				this.healthError
					? _('读取数据源状态失败：') + this.healthError
					: _('没有数据源信息。')
			]));
			return;
		}

		var table = E('table', { 'class': 'isp-table' }, [
			E('thead', {}, [
				E('tr', {}, [
					E('th', {}, [_('源')]),
					E('th', {}, [_('角色')]),
					E('th', {}, [_('最后成功')]),
					E('th', { 'class': 'num' }, [_('连续失败')]),
					E('th', { 'class': 'num' }, [_('Jaccard')]),
					E('th', {}, [_('状态')])
				])
			])
		]);
		var body = E('tbody', {});

		srcs.forEach(function(s) {
			var tag = 'isp-tag is-ok';
			var text = _('正常');
			if (s.status === 'disabled') {
				tag = 'isp-tag';
				text = _('未启用校验');
			} else if (s.max_fail && s.fail_days >= s.max_fail) {
				tag = 'isp-tag is-bad';
				text = _('拒绝更新') + ' ' + s.fail_days + '/' + s.max_fail;
			} else if (s.fail_days > 0) {
				tag = 'isp-tag is-warn';
				text = _('降级') + ' ' + s.fail_days + '/' + s.max_fail;
			}

			body.appendChild(E('tr', {}, [
				E('td', {}, [ s.label || s.name ]),
				E('td', {}, [ E('span', { 'class': 'isp-tag' }, [ s.role ]) ]),
				E('td', {}, [ s.last_ok_text || '—' ]),
				E('td', { 'class': 'num' }, [ String(s.fail_days || 0) ]),
				E('td', { 'class': 'num' }, [ s.jaccard != null ? (s.jaccard + '%') : '—' ]),
				E('td', {}, [ E('span', { 'class': tag }, [ text ]) ])
			]));
		});

		table.appendChild(body);
		box.appendChild(table);
	},

	/* ---------------- 数据时间 / cron / diff ---------------- */

	paintTime: function() {
		var box = document.getElementById('isp-time');
		if (!box)
			return;

		while (box.firstChild)
			box.removeChild(box.firstChild);

		var d = (this.health && this.health.data) || {};
		var diff = (this.health && this.health.diff) || {};

		box.appendChild(E('div', { 'class': 'isp-time' }, [
			E('span', {}, [
				_('数据更新：'),
				E('b', {}, [ d.updated && d.updated !== '-' ? d.updated : _('未知') ])
			]),
			E('span', {}, [
				_('下次更新：'),
				E('b', {}, [ d.next_cron && d.next_cron !== '-' ? d.next_cron : _('未知') ]),
				/* 裸 cron 表达式（17 4 * * *）对普通用户等于没写；翻成「每天 04:17」，
				   原始表达式退到 title 里，排障时鼠标一悬停就能看到。 */
				d.cron
					? E('span', {
						'class': 'isp-tag',
						'title': _('cron 表达式：') + d.cron
					}, [ humanCron(d.cron) || d.cron ])
					: ''
			]),
			E('span', {}, [
				_('最近校验：'),
				E('b', {}, [
					diff.min_jaccard != null
						? diff.min_jaccard + '%'
						: ((this.health && this.health.verify_enabled) ? _('尚未运行') : _('未启用校验'))
				])
			])
		]));
	},

	paint: function() {
		this.paintOps();
		this.paintLines();
		this.paintFallback();
		this.paintSources();
		this.paintTime();

		var err = document.getElementById('isp-load-error');
		if (err) {
			var msg = this.statusError
				? ('status: ' + this.statusError)
				: (this.healthError ? ('health: ' + this.healthError) : '');
			err.textContent = msg;
			err.style.display = msg ? '' : 'none';
		}
	},

	/* ---------------- 页面骨架 ---------------- */

	render: function() {
		var self = this;
		this.status = [];
		this.health = {};
		this.paused = false;
		this.busy = false;
		this._inflight = null;

		var pauseLabel = E('span', {}, [_('暂停刷新')]);
		var pauseBtn = E('button', {
			'class': 'btn',
			'title': _('暂停后不再每 10 秒取值，可省一点 CPU'),
			'click': function() {
				self.paused = !self.paused;
				while (pauseBtn.firstChild)
					pauseBtn.removeChild(pauseBtn.firstChild);
				pauseBtn.appendChild(svgIcon(self.paused ? 'play' : 'pause', 16));
				pauseBtn.appendChild(E('span', {}, [ self.paused ? _('继续刷新') : _('暂停刷新') ]));

				self.paintPill();

				if (!self.paused)
					self.refresh();
			}
		}, [ svgIcon('pause', 16), pauseLabel ]);

		this._pillIcon = E('span', { 'class': 'isp-pill-ico' });
		this._pillText = E('span', {});
		var statePill = this._pill = E('span', { 'class': 'isp-pill' }, [
			this._pillIcon,
			this._pillText
		]);
		this.paintPill();

		var actions = E('div', { 'class': 'isp-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': function() {
					self.run(['sync'], _('同步'),
						_('将下载最新运营商数据、重写 mwan3 规则并刷入 nftables。这会改动分流配置，确认继续？'));
				}
			}, [ svgIcon('sync', 16), E('span', {}, [_('同步生效')]) ]),
			E('button', {
				'class': 'cbi-button',
				'click': function() { self.run(['refresh'], _('更新数据')); }
			}, [ svgIcon('download', 16), E('span', {}, [_('更新数据')]) ]),
			E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'click': function() { self.run(['verify'], _('核对')); }
			}, [ svgIcon('check', 16), E('span', {}, [_('核对规则')]) ]),
			E('button', {
				'class': 'cbi-button',
				'click': function() { self.refresh(); }
			}, [ svgIcon('refresh', 16), E('span', {}, [_('刷新')]) ])
		]);

		var container = E('div', { 'class': 'isp-app' }, [
			E('link', {
				'rel': 'stylesheet',
				'href': L.resource('isp-split/isp-split.css')
			}),

			E('div', { 'class': 'isp-hero' }, [
				E('h2', {}, [ _('运营商分流') ]),
				E('div', { 'class': 'isp-sub' }, [
					_('按目标 IP 归属选择出口线路；只影响直连流量，代理流量由 OpenClash 自行接管。')
				]),
				E('div', { 'class': 'isp-toolbar' }, [ statePill, pauseBtn ])
			]),

			E('div', { 'id': 'isp-load-error', 'class': 'isp-err', 'style': 'display:none' }),
			E('div', { 'id': 'isp-cards', 'class': 'isp-cards' }),

			/* 兜底流量不再是独立大卡：它已经并入顶部运营商网格的第 4 格
			   （见 paintOps）。这里腾出来的位置让双线健康 / 数据源健康度 /
			   数据时间排成一行三格（isp-grid-3，断点 1100→2 列、820→1 列），
			   页面从「2+2+2」变成「4 张运营商 + 3 张明细」，视线更顺。 */
			E('div', { 'class': 'isp-grid-3' }, [
				E('section', { 'class': 'isp-card' }, [
					E('h3', {}, [ _('双线健康') ]),
					E('div', { 'id': 'isp-lines' })
				]),
				E('section', { 'class': 'isp-card' }, [
					E('h3', {}, [ _('数据源健康度') ]),
					E('div', { 'id': 'isp-sources' })
				]),
				E('section', { 'class': 'isp-card' }, [
					E('h3', {}, [ _('数据时间') ]),
					E('div', { 'id': 'isp-time' })
				])
			]),

			actions,

			E('pre', { 'id': 'isp-out', 'class': 'isp-out' }, [ _('命令输出会显示在这里') ])
		]);

		this.refresh();

		/* 自带定时器替代 LuCI 的 poll（见文件头注释）：暂停即停，页面被换走即收摊。 */
		this.timer = window.setInterval(function() {
			if (!document.getElementById('isp-time')) {
				window.clearInterval(self.timer);
				self.timer = null;
				return;
			}
			if (self.paused || self.busy)
				return;
			self.refresh();
		}, REFRESH_SEC * 1000);

		return container;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
