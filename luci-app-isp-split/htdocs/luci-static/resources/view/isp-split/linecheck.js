'use strict';
'require view';
'require fs';
'require ui';

/*
 * LuCI「线路体检」页（0.3.0）
 *
 * 设计注记（BUG-23，为什么 load() 里一行 exec 都没有）：
 *   这个页面的黄金场景恰恰是“网络最差的时候”：用户怀疑某条线坏了才来体检。
 *   而真实探测（STUN 多点 × 超时 + 双线 HTTP 采样）要 21-60 秒，网络越差越慢；
 *   rpcd 的 exec 是硬超时（VM 上 /etc/config/rpcd timeout=30），超时后 promise
 *   reject，LuCI 连 render 都不会进——页面只剩菜单，用户在最需要体检的时候
 *   拿到一张白屏。所以：
 *     · load() 只 fs.read 一份缓存快照（state/linecheck/last.json），零 exec；
 *     · 没缓存就渲染“尚未体检”占位卡，按钮仍然可用；
 *     · 点按钮 = 让 CLI 起一个后台探测进程（linecheck --background），然后页面
 *       每 2.5s 读一次快照比较 generated，最长等 90s。
 *
 * 数据口径：评分、NAT 五态、四段延迟全部由 shell 侧算好写进 JSON，前端不猜、
 * 不算分，避免两套规则。
 */

var CMD = '/usr/sbin/isp-split';
var CACHE = '/etc/isp-split/state/linecheck/last.json';
var LOCK = '/etc/isp-split/state/linecheck.lock';
var POLL_MS = 2500;
var POLL_MAX_MS = 90000;
/* 锁目录超过这个岁数就当崩溃残留，不再让页面“假装在体检” */
var LOCK_STALE_S = 300;

var ICONS = {
	refresh: '<path d="M20 11a8 8 0 1 0-2.3 6.3"/><path d="M20 4v7h-7"/>',
	pulse: '<path d="M2 12h4l2.5-6 3.5 12 2.5-6H22"/>',
	chevron: '<path d="M6 9l6 6 6-6"/>',
	shield: '<path d="M12 3l7 3v6c0 4-3 7-7 9-4-2-7-5-7-9V6z"/>'
};

function svgIcon(name, size) {
	var span = document.createElement('span');
	span.className = 'isp-ico';
	span.innerHTML = '<svg viewBox="0 0 24 24" width="' + (size || 16) + '" height="' + (size || 16) +
		'" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
		'stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || ICONS.pulse) + '</svg>';
	return span;
}

/* fs.read 解析出来的是字符串（不是 exec 的 {stdout}）；失败一律返回 null */
function parseStr(s) {
	try {
		var v = JSON.parse(String(s || '').trim() || 'null');
		return (v && typeof v === 'object') ? v : null;
	} catch (e) {
		return null;
	}
}

function nowSec() {
	return Math.floor(Date.now() / 1000);
}

function fmtAge(sec) {
	if (sec < 90)
		return sec + _(' 秒前');
	if (sec < 3600)
		return Math.round(sec / 60) + _(' 分钟前');
	return Math.round(sec / 3600) + _(' 小时前');
}

function fmtMs(v) {
	if (v === null || v === undefined || v === '' || v === 0)
		return '—';
	return v + 'ms';
}

function fmtNum(v) {
	return (v === null || v === undefined) ? '—' : String(v);
}

function gradeClass(g) {
	return 'lc-grade is-' + String(g || 'd').toLowerCase();
}

function natClass(type) {
	if (type === 'public' || type === 'cone')
		return 'is-ok';
	if (type === 'symmetric')
		return 'is-warn';
	if (type === 'cgnat')
		return 'is-bad';
	return 'is-muted';
}

function stateText(state) {
	if (state === 'online')
		return _('在线');
	if (state === 'offline')
		return _('离线');
	return _('未知');
}

function classText(c) {
	if (c === 'public')
		return _('公网');
	if (c === 'cgnat')
		return _('CGNAT');
	if (c === 'private')
		return _('私网');
	return _('无地址');
}

function geoText(geo) {
	if (!geo || geo.status === 'off')
		return _('未查询（隐私开关关闭）');
	if (geo.status === 'noip')
		return _('无公网出口 IP，跳过');
	if (geo.status === 'ok')
		return (geo.location || '') + (geo.provider ? '（' + geo.provider + '）' : '');
	return _('查询失败（不影响评分）');
}

function targetText(t) {
	if (!t)
		return _('无可用目标');
	return t.domain + ' → ' + t.ip + ' · ' + (t.label || t.isp || '?') +
		' · ' + (t.mode === 'same_isp' ? _('同运营商') : _('跨网基线'));
}

/* 一行 key/value；value 可以是字符串、DOM 节点，或它们的数组。
 *
 * 曾经写成 E('span', {class:'lc-val'}, [value])：value 是数组时 LuCI 会把它
 * String() 掉，页面上直接显示 “HTMLSpanElement,HTMLSpanElement”
 * （WAN IP / 出口 IP / NAT 类型三行都是这样）。数组必须作为 children 展开，
 * 并过滤 null（没有 multi_nat 时那一项就是 null），否则会渲染出空文本节点。
 */
function row(label, value) {
	var kids = (Array.isArray(value) ? value : [ value ]).filter(function(x) {
		return x !== null && x !== undefined;
	});
	return E('div', { 'class': 'lc-row' }, [
		E('span', { 'class': 'lc-key' }, [ label ]),
		E('span', { 'class': 'lc-val' }, kids)
	]);
}

function seg(label, value) {
	return E('div', { 'class': 'lc-seg' }, [
		E('span', { 'class': 'lc-seg-label' }, [ label ]),
		E('span', { 'class': 'lc-seg-value' }, [ value ])
	]);
}

return view.extend({
	/* 零 exec：只读缓存快照 + 看一眼锁（判断是否有体检在跑） */
	load: function() {
		return fs.read(CACHE).then(function(s) {
			return { raw: s, data: parseStr(s) };
		}).catch(function() {
			/* 文件不存在 / 权限不足 / 还没体检过：都按“尚未体检”处理 */
			return { raw: null, data: null };
		}).then(function(res) {
			return L.resolveDefault(fs.stat(LOCK), null).then(function(st) {
				var mt = (st && (+st.mtime || 0)) || 0;
				res.running = !!mt && (nowSec() - mt) < LOCK_STALE_S;
				return res;
			}, function() { return res; });
		});
	},

	render: function(loaded) {
		var self = this;
		this.data = (loaded && loaded.data) || null;
		this.baseGen = this.data ? (+this.data.generated || 0) : 0;
		this.busy = false;
		this._poll = null;

		var cards = E('div', { 'id': 'lc-cards', 'class': 'isp-cards lc-cards' });
		var meta = E('div', { 'id': 'lc-meta', 'class': 'lc-meta' });
		var msg = E('div', { 'id': 'lc-msg', 'class': 'lc-msg' });
		this.cardsBox = cards;
		this.metaBox = meta;
		this.msgBox = msg;

		var runBtn = E('button', {
			'class': 'cbi-button cbi-button-action lc-run',
			'click': function() { self.run(); }
		}, [ svgIcon('pulse'), E('span', {}, [ _('开始体检') ]) ]);
		this.runBtn = runBtn;

		var pill = E('span', { 'id': 'lc-pill', 'class': 'isp-pill' });
		this.pill = pill;

		this.paint();

		/* 打开页面时如果已有一次后台体检在跑（例如刚才的探测还没结束、
		   或者用户重开了本页），直接进轮询态，不要再点一次。
		   但如果手上已经有一份没过期的快照，就不必陪着等——那可能只是一
		   个崩溃残留的锁目录。 */
		if (loaded && loaded.running) {
			var age = this.data && this.data.generated
				? nowSec() - (+this.data.generated) : 1e9;
			if (age > (+((this.data || {}).interval) || 60))
				this.poll(0);
		}

		/* 只读页：不能带 cbi-map —— LuCI 见到它会补一条 “Save & Apply” 底栏，
		   而这一页没有任何可保存的表单，底栏只会误导用户。 */
		return E('div', { 'class': 'isp-app' }, [
			E('link', { 'rel': 'stylesheet', 'href': L.resource('isp-split/isp-split.css') }),

			E('div', { 'class': 'isp-hero' }, [
				E('h2', {}, [ _('线路体检') ]),
				E('div', { 'class': 'isp-sub' }, [
					_('逐条 WAN 检查出口类型、四段延迟、NAT 与归属地。只读探测，不改 mwan3/nft 规则；体检在后台跑，页面只读结果，不会卡住。')
				]),
				E('div', { 'class': 'isp-toolbar' }, [ runBtn, pill ])
			]),

			E('div', { 'class': 'lc-privacy' }, [
				svgIcon('shield', 15),
				E('span', {}, [
					_('归属地查询只发送每条线的出口公网 IP，不发送内网地址、设备名、MAC 或流量内容；可在「配置 → 线路体检」关闭。')
				])
			]),

			meta,
			msg,
			cards
		]);
	},

	/* ---------------- 触发后台体检 ---------------- */

	run: function() {
		var self = this;
		if (this.busy)
			return;
		this.busy = true;
		this.paintButton();
		this.setMsg(_('正在启动后台体检…'), 'info');

		fs.exec(CMD, ['linecheck', '--background']).then(function(res) {
			var out = ((res && res.stdout) || '') + ((res && res.stderr) || '');
			var d = parseStr((res && res.stdout) || '');
			if (!d)
				throw new Error(out.trim() || _('linecheck --background 没有返回可解析的状态'));
			if (d.started && d.finished)
				return self.reload(_('体检完成。'));
			if (d.started)
				return self.poll(d.pid);
			if (d.running) {
				self.setMsg(_('已有一次体检在跑（pid ') + d.pid + _('，已 ') + (d.elapsed || 0) +
					_(' 秒），继续等它的结果…'), 'info');
				return self.poll(d.pid);
			}
			if (d.cached) {
				self.busy = false;
				return self.reload(_('60 秒内刚测过，直接显示缓存结果（要强制重测请用命令行 --force）。'));
			}
			throw new Error(d.error || _('未知状态'));
		}).catch(function(err) {
			self.busy = false;
			self.stopPoll();
			self.setMsg(_('启动体检失败：') + String(err), 'bad');
			ui.addNotification(null, E('p', {}, [ _('启动体检失败：') + String(err) ]), 'danger');
		});
	},

	/* 轮询：每 2.5s 读一次快照，generated 变大就渲染；最多 90s。 */
	poll: function(pid) {
		var self = this;
		this.busy = true;
		this.paintButton();
		var start = Date.now();
		if (this._poll)
			clearInterval(this._poll);
		this.setMsg(_('后台体检中（pid ') + (pid || 0) + _('），真实探测 20-60 秒，网络越差越慢…'), 'info');

		this._poll = setInterval(function() {
			/* 页面被切走/卸载后自己停，别在后台空转 */
			if (!self.cardsBox || !document.body.contains(self.cardsBox)) {
				self.stopPoll();
				return;
			}
			var waited = Date.now() - start;
			if (waited > POLL_MAX_MS) {
				self.stopPoll();
				self.setMsg(_('后台体检超过 90 秒还没出结果：可能线路极差或探测卡住。稍后重新打开本页即可看到结果，也可用命令行 isp-split linecheck --json 查看。'), 'bad');
				return;
			}
			fs.read(CACHE).then(function(s) {
				var d = parseStr(s);
				if (!d || (+d.generated || 0) <= self.baseGen)
					return;
				self.data = d;
				self.baseGen = +d.generated || 0;
				self.paint();
				self.stopPoll();
				self.setMsg(_('体检完成。'), 'ok');
			}).catch(function() { /* 还没写出来，下一轮再看 */ });
			self.setMsg(_('后台体检中（已等待 ') + Math.round(waited / 1000) + _(' 秒）…'), 'info');
		}, POLL_MS);
	},

	stopPoll: function() {
		if (this._poll) {
			clearInterval(this._poll);
			this._poll = null;
		}
		this.busy = false;
		this.paintButton();
	},

	reload: function(msg) {
		var self = this;
		return fs.read(CACHE).then(function(s) {
			var d = parseStr(s);
			if (d) {
				self.data = d;
				self.baseGen = +d.generated || 0;
			}
			self.stopPoll();
			self.paint();
			self.setMsg(msg || _('体检完成。'), 'ok');
		}).catch(function() {
			self.stopPoll();
			self.paint();
			self.setMsg(msg || _('还没有结果。'), 'info');
		});
	},

	setMsg: function(t, kind) {
		if (!this.msgBox)
			return;
		this.msgBox.textContent = t || '';
		this.msgBox.className = 'lc-msg' + (kind ? ' is-' + kind : '');
	},

	paintButton: function() {
		if (!this.runBtn)
			return;
		var span = this.runBtn.querySelector('span:last-child');
		if (this.busy) {
			this.runBtn.disabled = true;
			if (span) span.textContent = _('体检中…');
		} else {
			this.runBtn.disabled = false;
			if (span) span.textContent = this.data ? _('重新体检') : _('开始体检');
		}

		if (!this.pill)
			return;
		this.pill.className = 'isp-pill' + (this.busy ? ' is-busy' : '');
		if (this.busy) {
			this.pill.textContent = _('后台体检中…');
		} else if (this.data) {
			var gen = +this.data.generated || 0;
			var age = gen ? Math.max(0, nowSec() - gen) : 0;
			var intv = +this.data.interval || 60;
			this.pill.textContent = (gen ? fmtAge(age) : _('无时间戳')) +
				(age <= intv ? _(' · 缓存有效') : _(' · 已过期'));
		} else {
			this.pill.textContent = _('尚未体检');
		}
	},

	/* ---------------- 渲染 ---------------- */

	paint: function() {
		if (!this.cardsBox)
			return;
		while (this.cardsBox.firstChild)
			this.cardsBox.removeChild(this.cardsBox.firstChild);
		while (this.metaBox.firstChild)
			this.metaBox.removeChild(this.metaBox.firstChild);

		this.paintButton();

		/* 没缓存：占位卡。绝不为了“有没有数据”去跑一次探测。 */
		if (!this.data) {
			this.cardsBox.appendChild(E('div', { 'class': 'isp-card lc-placeholder' }, [
				E('div', { 'class': 'lc-ph-head' }, [
					svgIcon('pulse', 18),
					E('strong', {}, [ _('尚未体检') ])
				]),
				E('p', { 'class': 'lc-ph-text' }, [
					_('点上方「开始体检」：探测会在后台跑（逐条 WAN 检查出口类型、四段延迟、NAT、归属地），通常 20-60 秒，网络差时更久。本页不会卡住，中途可以离开。')
				]),
				E('p', { 'class': 'lc-ph-note' }, [
					_('结果会缓存在设备上，60 秒内再次打开本页直接显示。')
				])
			]));
			return;
		}

		var d = this.data;
		var gen = +d.generated || 0;
		var age = gen ? Math.max(0, nowSec() - gen) : 0;
		var intv = +d.interval || 60;
		var bits = [];
		bits.push(_('版本 ') + (d.version || '?'));
		if (gen)
			bits.push(_('生成于 ') + new Date(gen * 1000).toLocaleString() + '（' + fmtAge(age) + '）');
		bits.push(age <= intv ? _('缓存有效') : _('已过期，可重新体检'));
		bits.push(_('缓存间隔 ') + intv + 's');
		bits.push(d.socat ? _('socat 可用') : _('socat 未安装（NAT 只能判未知）'));
		bits.push(d.geo_enabled ? _('归属地查询开') : _('归属地查询关'));
		this.metaBox.textContent = bits.join(' · ');

		var wans = d.wans || [];
		if (!wans.length) {
			this.cardsBox.appendChild(E('div', { 'class': 'isp-empty' }, [
				(d.errors && d.errors.length)
					? d.errors.join('；')
					: _('没有可体检的 WAN。先在 mwan3 启用接口，或在命令行用 --wan 指定。')
			]));
			return;
		}

		for (var i = 0; i < wans.length; i++)
			this.cardsBox.appendChild(this.card(wans[i], d));
	},

	card: function(w, d) {
		var sc = w.score || {};
		var nat = w.nat || {};
		var lat = w.latency || {};
		var geo = w.geo || {};
		var http = w.http || {};
		var detail = E('div', { 'class': 'lc-detail', 'hidden': '' });

		var toggle = E('button', {
			'class': 'lc-toggle',
			'click': function() {
				if (detail.hasAttribute('hidden')) {
					detail.removeAttribute('hidden');
					toggle.classList.add('is-open');
					toggle.lastChild.textContent = _('收起明细');
				} else {
					detail.setAttribute('hidden', '');
					toggle.classList.remove('is-open');
					toggle.lastChild.textContent = _('查看明细');
				}
			}
		}, [ svgIcon('chevron', 14), E('span', {}, [ _('查看明细') ]) ]);

		var multi = w.multi_nat
			? E('span', { 'class': 'lc-tag is-warn' }, [ _('多层 NAT/代理') ])
			: null;

		var natTag = E('span', { 'class': 'lc-tag ' + natClass(nat.type) }, [ nat.label || _('未知') ]);

		var card = E('article', {
			'class': 'isp-card lc-card',
			'style': '--lc-accent: ' + (sc.grade === 'A' ? 'var(--isp-ok)' :
				sc.grade === 'B' ? 'var(--isp-primary)' :
				sc.grade === 'C' ? 'var(--isp-warn)' : 'var(--isp-bad)')
		}, [
			E('div', { 'class': 'lc-head' }, [
				E('div', { 'class': 'lc-title' }, [
					E('span', { 'class': 'lc-name' }, [ w.iface || '?' ]),
					E('span', { 'class': 'lc-dev' }, [ w.device || '' ]),
					E('span', { 'class': 'lc-state ' + (w.up ? 'is-on' : 'is-off') }, [
						stateText(w.state)
					])
				]),
				E('div', { 'class': 'lc-score' }, [
					E('span', { 'class': gradeClass(sc.grade) }, [ sc.grade || 'D' ]),
					E('span', { 'class': 'lc-total' }, [ fmtNum(sc.total) ]),
					E('span', { 'class': 'lc-max' }, [ '/100' ])
				])
			]),

			E('div', { 'class': 'lc-kv' }, [
				row(_('WAN IP'), [
					E('span', {}, [ w.wan_ip || '—' ]),
					E('span', { 'class': 'lc-tag is-muted' }, [ classText(w.ip_class) ])
				]),
				row(_('出口 IP'), [
					E('span', {}, [ w.exit_ip || _('未取到（可能未真正出网）') ]),
					multi
				]),
				row(_('运营商'), [ w.isp_label || _('未知') ]),
				row(_('NAT 类型'), [ natTag,
					E('span', { 'class': 'lc-sub' }, [
						nat.confidence === 'high' ? _('置信度高')
							: nat.confidence === 'medium' ? _('置信度中（仅一个探测点）')
							: _('置信度未知')
					])
				]),
				row(_('归属地'), [ geoText(geo) ])
			]),

			E('div', { 'class': 'lc-segs' }, [
				seg('DNS', fmtMs(lat.dns_ms)),
				seg('TCP', fmtMs(lat.tcp_ms)),
				seg('TLS', fmtMs(lat.tls_ms)),
				seg(_('首字节'), fmtMs(lat.ttfb_ms))
			]),

			E('div', { 'class': 'lc-line2' }, [
				E('span', {}, [ _('抖动 ') + fmtNum(lat.jitter_ms) + 'ms' ]),
				E('span', {}, [ _('丢包 ') + fmtNum(lat.loss_pct) + '%' ]),
				E('span', {}, [ _('HTTP ') + fmtNum(http.code) ]),
				E('span', {}, [ _('目标：') + targetText(w.target) ])
			]),

			E('div', { 'class': 'lc-advice' + (sc.grade === 'D' || nat.type === 'cgnat' ? ' is-bad' : '') }, [
				svgIcon('pulse', 15),
				E('span', {}, [ sc.advice || _('无建议') ])
			]),

			toggle,
			detail
		]);

		/* 明细：评分拆分 + 硬上限 + STUN 探测 + 原始目标/延迟 */
		var tbody = E('tbody', {});
		(sc.breakdown || []).forEach(function(b) {
			tbody.appendChild(E('tr', {}, [
				E('td', { 'data-th': _('项目') }, [ b.label || b.key ]),
				E('td', { 'data-th': _('观测') }, [ b.value || '—' ]),
				E('td', { 'data-th': _('得分') }, [ (b.points || 0) + ' / ' + (b.max || 0) ]),
				E('td', { 'data-th': _('依据') }, [ b.reason || '—' ])
			]));
		});

		detail.appendChild(E('h4', {}, [ _('评分明细') ]));
		detail.appendChild(E('table', { 'class': 'lc-table' }, [
			E('thead', {}, [ E('tr', {}, [
				E('th', {}, [_('项目')]), E('th', {}, [_('观测')]),
				E('th', {}, [_('得分')]), E('th', {}, [_('依据')])
			]) ]),
			tbody
		]));

		if (sc.caps && sc.caps.length) {
			var ul = E('ul', { 'class': 'lc-caps' });
			sc.caps.forEach(function(c) { ul.appendChild(E('li', {}, [ c ])); });
			detail.appendChild(E('h4', {}, [ _('硬上限') ]));
			detail.appendChild(ul);
		}

		var probes = nat.probes || [];
		if (probes.length) {
			var pt = E('tbody', {});
			probes.forEach(function(p) {
				pt.appendChild(E('tr', {}, [
					E('td', { 'data-th': _('服务器') }, [ p.server || '—' ]),
					E('td', { 'data-th': 'IP' }, [ p.ip || '—' ]),
					E('td', { 'data-th': _('状态') }, [ p.status === 'ok' ? _('成功') : p.status === 'bad' ? _('坏包') : _('超时') ]),
					E('td', { 'data-th': _('映射') }, [ p.mapped || '—' ]),
					E('td', { 'data-th': 'RTT' }, [ p.rtt_ms ? p.rtt_ms + 'ms' : '—' ])
				]));
			});
			detail.appendChild(E('h4', {}, [ _('STUN 探测') + (nat.detail ? '：' + nat.detail : '') ]));
			detail.appendChild(E('table', { 'class': 'lc-table' }, [
				E('thead', {}, [ E('tr', {}, [
					E('th', {}, [_('服务器')]), E('th', {}, ['IP']),
					E('th', {}, [_('状态')]), E('th', {}, [_('映射')]), E('th', {}, ['RTT'])
				]) ]),
				pt
			]));
		}

		detail.appendChild(E('div', { 'class': 'lc-raw' }, [
			_('目标：') + targetText(w.target) + ' · ' +
			_('尝试 ') + fmtNum(lat.attempts) + _(' 次 / 成功 ') + fmtNum(lat.ok_count) + _(' 次 · ') +
			_('本地 STUN 端口 ') + fmtNum(nat.local_port)
		]));

		return card;
	},

	/* 只读页：把三个保存钩子显式置空，LuCI 才不会补一条 “Save & Apply / Reset”
	   底栏（overview.js 早就这么写了，linecheck 漏了）。这一页没有任何可保存的
	   表单，底栏只会让人以为有未保存的改动。 */
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
