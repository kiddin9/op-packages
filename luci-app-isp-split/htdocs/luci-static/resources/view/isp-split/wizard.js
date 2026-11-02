'use strict';
'require view';
'require fs';
'require ui';

/*
 * LuCI 首启向导（0.3.3）：自检 → 体检 → 绑定 → 生效
 *
 * 三条硬约束（本文件的骨架就是按它们搭的）：
 *
 *   1) 白名单。页面上每个按钮都只映射到 WIZ 表里的一条**字面量** argv，参数
 *      从不拼接用户输入；不在表里的 key 直接拒绝，不执行任何命令。这样即使
 *      有人往页面里塞了个假按钮，效果也只有"提示不在白名单里"。
 *      rpcd 的 file.exec 是按**路径**授权的，没法按参数收紧（见 docs/SECURITY.md），
 *      所以白名单这一层只能在前端 + 静态断言里做，向导不做任何 shell 拼接。
 *
 *   2) 状态机落盘。四步的进度写 /etc/isp-split/state/wizard.json（ACL 只给这
 *      一个文件写权限），完成后 done=1 + done_at 时间戳。刷新页面能从原步继续；
 *      done=1 时菜单入口（原文「引导」）在页面里显示为「重新引导」——菜单标题
 *      是静态 menu.d，改不了，只能在这里改名（FIX35-SUMMARY 偏离清单 D-1）。
 *
 *   3) 危险动作二次确认。写 mwan3（bootstrap --apply）、重写规则并 reload
 *      mwan3（wire/apply 灰度）、整链同步（sync）都要弹框，文案里逐条列出
 *      "将被写入 / 将被重载"的东西；sync 还要先勾选"我知道会短暂断流"。
 *      撤销引导（bootstrap --rollback）先跑一次不带 --yes 的预演，把 CLI 自己
 *      算出来的"将删除的段"原样贴进确认框，再带 --yes 执行。
 *
 * 失败 UX：任何一步失败都留在当前步，命令与输出展开在同一个 isp-out 区块里
 * （与状态页同一个类）；「回到上一步」只改界面、**不撤销**已生效的改动，文案
 * 写明；要撤销必须显式点「撤销本次引导」。
 *
 * Step 1 复用 0.3.0 那套健康检查（读 state/<probe>/last.json + 后台探测轮询）。
 * 那个功能可以在构建期被剥离（FEATURE_LINECHECK=0），剥离时这一整块会被
 * strip 脚本按成对标记整块删掉，只留一个"本版本未包含"的桩——所以
 * 下面用 var f = function(){} 的赋值写法，而不是同名 function 声明
 * （严格模式下重复声明在部分引擎里直接语法错）。
 */

var CMD = '/usr/sbin/isp-split';
var STATE_FILE = '/etc/isp-split/state/wizard.json';
var STATE_SCHEMA = 1;
var OVERVIEW_URL = 'admin/network/isp-split/overview';
var CONFIG_URL = 'admin/network/isp-split/config';
var DONE_REDIRECT_MS = 4000;

/* 四步：key 只用于导航，title 是用户看到的名字 */
var STEPS = [
	{ key: 'check', title: '环境自检', hint: '只读，硬门' },
	{ key: 'line', title: '体检', hint: '可选，只读探测' },
	{ key: 'bind', title: '绑定骨架', hint: '写 mwan3' },
	{ key: 'live', title: '生效', hint: '写规则并 reload' }
];

/*
 * W3 白名单：向导按钮可用的命令行，全部写死在这里。
 * 值的形态必须是 [] 字面量（selftest 逐条比对，并断言全文件只有一处 fs.exec）。
 */
var WIZ = {
	doctor: [ 'doctor', '--json' ],
	bootstrap_dry: [ 'bootstrap' ],
	bootstrap_apply: [ 'bootstrap', '--apply' ],
	rollback_list: [ 'bootstrap', '--rollback' ],
	rollback_yes: [ 'bootstrap', '--rollback', '--yes' ],
	plan: [ 'plan' ],
	wire: [ 'wire' ],
	apply: [ 'apply' ],
	sync: [ 'sync' ]
};

/* ---------------------------------------------------------------- 体检步（可剥离） */

/* 剥离版（FEATURE_LINECHECK=0）：这三个赋值留在文件里，整块体检实现被删掉 */
var lcAvailable = function() { return false; };
var loadLc = function() { return Promise.resolve(null); };
var paintLc = function(box) {
	box.appendChild(E('div', { 'class': 'isp-empty' }, [
		_('本版本未包含这条可选的健康检查（构建期已剥离）。直接点「下一步」即可。')
	]));
};

/* lc:begin */
WIZ.linecheck_bg = [ 'linecheck', '--background' ];
var LC_CACHE = '/etc/isp-split/state/linecheck/last.json';
var LC_POLL_MS = 2500;
var LC_POLL_MAX_MS = 90000;
var POLL_LOCK_STALE_S = 300;

lcAvailable = function() { return true; };

loadLc = function() {
	return fs.read(LC_CACHE).then(function(s) {
		return parseJsonStr(s);
	}).catch(function() {
		/* 没体检过 / 权限不足：都按"还没有结果"处理，不跑探测 */
		return null;
	});
};

/* 一份精简卡：一行一条线，评分圆环退化成彩色标签，明细留给体检页 */
paintLc = function(box, snap) {
	var self = this;

	if (!snap || !snap.wans || !snap.wans.length) {
		box.appendChild(E('div', { 'class': 'isp-empty' }, [
			_('还没有体检快照。跑一次只读探针（20-60 秒，后台执行），结果会缓存到设备上。')
		]));
	}
	else {
		var list = E('div', { 'class': 'isp-list' });
		snap.wans.forEach(function(w) {
			var sc = w.score || {};
			var grade = String(sc.grade || 'D').toUpperCase();
			var tag = 'isp-tag' + (grade === 'A' || grade === 'B' ? ' is-ok'
				: (grade === 'C' ? ' is-warn' : ' is-bad'));
			list.appendChild(E('div', { 'class': 'isp-line' + (w.up ? ' is-online' : ' is-offline') }, [
				E('span', { 'class': 'isp-dot' }),
				E('span', { 'class': 'isp-line-name' }, [ w.iface || '?' ]),
				E('span', { 'class': 'isp-line-track' }, [
					(w.isp_label || _('未知')) + ' · ' + (w.wan_ip || '—')
				]),
				E('span', { 'class': 'isp-line-pct' }, [
					E('span', { 'class': tag }, [ grade + ' ' + (sc.total != null ? sc.total : '—') ])
				])
			]));
			if (sc.advice)
				list.appendChild(E('div', { 'class': 'wz-advice' }, [ sc.advice ]));
		});
		box.appendChild(list);

		var gen = +snap.generated || 0;
		box.appendChild(E('div', { 'class': 'wz-meta' }, [
			gen
				? _('快照时间：') + new Date(gen * 1000).toLocaleString()
				: _('快照没有时间戳'),
			' · ',
			snap.geo_enabled ? _('归属地查询开') : _('归属地查询关')
		]));
	}

	var runBtn = E('button', {
		'class': 'cbi-button cbi-button-action',
		'click': function() { lcRun(self, runBtn); }
	}, [ _('跑一次体检') ]);

	box.appendChild(E('div', { 'class': 'wz-actions' }, [
		runBtn,
		E('span', { 'class': 'wz-hint' }, [ _('只读探测，不改 mwan3 / nft 规则；后台跑，页面不会卡住。') ])
	]));
};

/* 后台探测：起进程 → 每 2.5s 读快照比对 generated，最多 90s */
function lcPoll(view, baseGen) {
	var start = Date.now();
	if (view._lcTimer)
		window.clearInterval(view._lcTimer);

	view._lcTimer = window.setInterval(function() {
		if (!view.body || !document.body.contains(view.body)) {
			window.clearInterval(view._lcTimer);
			view._lcTimer = null;
			return;
		}
		var waited = Date.now() - start;
		if (waited > LC_POLL_MAX_MS) {
			window.clearInterval(view._lcTimer);
			view._lcTimer = null;
			view.setOut(_('后台体检超过 90 秒还没出结果：稍后重开本页即可看到结果。'), null, 'bad');
			return;
		}
		loadLc().then(function(d) {
			if (!d || (+d.generated || 0) <= baseGen) {
				view.setNote(_('后台体检中（已等待 ') + Math.round(waited / 1000) + _(' 秒）…'));
				return;
			}
			window.clearInterval(view._lcTimer);
			view._lcTimer = null;
			view.lc = d;
			view.setNote('');
			view.paintStep();
			view.setOut(_('体检完成。'), null, 'ok');
		}).catch(function() { /* 文件还没写出来，下一轮再看 */ });
	}, LC_POLL_MS);
}
/* 起一次后台探测：只有完整版会渲染「跑一次体检」按钮（剥离版走 paintLc 的桩） */
function lcRun(view, btn) {
	var self = view;
	if (self.busy)
		return;
	self.busy = true;
	if (btn)
		btn.disabled = true;
	self.setNote(_('正在启动后台体检…'));

	return self.runWizard('linecheck_bg').then(function(res) {
		var out = ((res && res.stdout) || '') + ((res && res.stderr) || '');
		var d = parseJsonStr((res && res.stdout) || '');
		self.setOut(_('命令：isp-split linecheck --background') + '\n\n' + (out.trim() || _('(无输出)')),
			res, (res && res.code) ? 'bad' : '');

		if (!d) {
			self.busy = false;
			if (btn)
				btn.disabled = false;
			self.setNote('');
			throw new Error(out.trim() || _('linecheck --background 没有返回可解析的状态'));
		}

		var base = self.lc ? (+self.lc.generated || 0) : 0;
		if (d.started && d.finished) {
			self.busy = false;
			return loadLc().then(function(snap) {
				self.lc = snap;
				self.setNote('');
				self.paintStep();
			});
		}
		if (d.started || d.running) {
			self.setNote(_('后台体检中（pid ') + (d.pid || 0) + _('），真实探测 20-60 秒…'));
			lcPoll(self, base);
			return;
		}
		self.busy = false;
		if (btn)
			btn.disabled = false;
		if (d.cached) {
			return loadLc().then(function(snap) {
				self.lc = snap;
				self.paintStep();
				self.setOut(_('60 秒内刚测过，直接用缓存结果。'), null, 'ok');
			});
		}
		throw new Error(d.error || _('未知状态'));
	}).catch(function(err) {
		self.busy = false;
		if (btn)
			btn.disabled = false;
		self.setNote('');
		ui.addNotification(null, E('p', {}, [ _('体检失败：') + String(err) ]), 'danger');
	});
}

/* lc:end */

/* ---------------------------------------------------------------- 工具 */

function parseJsonStr(s) {
	try {
		var v = JSON.parse(String(s == null ? '' : s).trim() || 'null');
		return (v && typeof v === 'object') ? v : null;
	} catch (e) {
		return null;
	}
}

function nowSec() {
	return Math.floor(Date.now() / 1000);
}

function fmtTime(sec) {
	if (!sec)
		return '—';
	return new Date(sec * 1000).toLocaleString();
}

function intIn(v, min, max, dflt) {
	v = parseInt(v, 10);
	if (isNaN(v))
		return dflt;
	if (v < min)
		return min;
	if (v > max)
		return max;
	return v;
}

/* 状态文件归一化：坏文件（截断 / 手改错）不能让页面白屏，按"从第 0 步开始"处理 */
function normalizeState(raw) {
	var st = {
		schema: STATE_SCHEMA,
		step: 0,
		done: 0,
		started: 0,
		updated: 0,
		done_at: 0
	};
	if (!raw || typeof raw !== 'object')
		return st;

	st.step = intIn(raw.step, 0, STEPS.length - 1, 0);
	st.done = raw.done ? 1 : 0;
	st.started = parseInt(raw.started, 10) || 0;
	st.updated = parseInt(raw.updated, 10) || 0;
	st.done_at = parseInt(raw.done_at, 10) || 0;
	/* done=1 但没有时间戳 = 半截写入，退回未完成，避免"已完成"横幅显示 — */
	if (st.done && !st.done_at) {
		st.done = 0;
	}
	return st;
}

function statusText(s) {
	if (s === 'fail')
		return _('会失效');
	if (s === 'warn')
		return _('有保留');
	if (s === 'ok')
		return _('正常');
	return _('未知');
}

function statusCls(s) {
	if (s === 'fail')
		return 'is-bad';
	if (s === 'warn')
		return 'is-warn';
	if (s === 'ok')
		return 'is-ok';
	return '';
}

function kv(label, value) {
	return E('div', { 'class': 'wz-kv' }, [
		E('span', { 'class': 'wz-kv-key' }, [ label ]),
		E('span', { 'class': 'wz-kv-val' }, [ value ])
	]);
}

/* ---------------------------------------------------------------- 视图 */

return view.extend({
	/* ---------------- 载入：零 exec ---------------- */
	load: function() {
		return fs.read(STATE_FILE).then(function(s) {
			return parseJsonStr(s);
		}).catch(function() {
			/* 首次进入 / 没有权限 / 文件不存在：都按"还没开始"处理 */
			return null;
		}).then(function(st) {
			return loadLc().then(function(lc) {
				return { state: st, lc: lc };
			});
		});
	},

	render: function(loaded) {
		var self = this;

		this.state = normalizeState(loaded && loaded.state);
		this.lc = (loaded && loaded.lc) || null;
		this.doctor = null;
		this.doctorErr = null;
		this.doctorBusy = false;
		this.busy = false;
		this._lcTimer = null;
		this._redirectTimer = null;
		this._dryRun = null;

		this.heroTitle = E('h2', {}, [ _('引导') ]);
		this.heroSub = E('div', { 'class': 'isp-sub' }, [
			_('四步把分流跑起来：环境自检 → 体检（可选）→ 绑定骨架 → 生效。每一步都会把真实执行的命令和输出摊开给你看。')
		]);
		this.pill = E('span', { 'class': 'isp-pill' });
		this.bannerBox = E('div', { 'class': 'isp-banner-wrap' });
		this.navBox = E('div', { 'class': 'wz-steps' });
		this.body = E('div', { 'class': 'wz-body' });
		this.out = E('pre', { 'id': 'wz-out', 'class': 'isp-out' }, [ _('命令输出会显示在这里') ]);
		this.note = E('div', { 'class': 'wz-note' });

		this.prevBtn = E('button', {
			'class': 'cbi-button',
			'click': function() { self.goStep(self.state.step - 1); }
		}, [ _('上一步') ]);

		this.nextBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': function() { self.next(); }
		}, [ _('下一步') ]);

		this.rollbackBtn = E('button', {
			'class': 'cbi-button cbi-button-negative',
			'click': function() { self.rollbackFlow(); }
		}, [ _('撤销本次引导') ]);

		var container = E('div', { 'class': 'isp-app' }, [
			E('link', {
				'rel': 'stylesheet',
				'href': L.resource('isp-split/isp-split.css')
			}),

			E('div', { 'class': 'isp-hero' }, [
				this.heroTitle,
				this.heroSub,
				E('div', { 'class': 'isp-toolbar' }, [ this.pill ])
			]),

			this.bannerBox,
			this.navBox,
			this.body,
			this.note,
			this.out,

			E('div', { 'class': 'wz-footer' }, [
				this.prevBtn,
				this.nextBtn,
				E('span', { 'class': 'wz-hint' }, [
					_('「上一步」只改界面：已经生效的改动不会被撤销，要撤销请用右侧的「撤销本次引导」。')
				]),
				E('span', { 'class': 'wz-spacer' }),
				this.rollbackBtn
			])
		]);

		this.paintNav();
		this.paintBanner();

		if (this.state.done)
			this.paintDone();
		else
			this.paintStep();

		return container;
	},

	/* ---------------- 状态读写 ---------------- */

	saveState: function() {
		var self = this;
		var st = {
			schema: STATE_SCHEMA,
			step: this.state.step,
			done: this.state.done ? 1 : 0,
			started: this.state.started || nowSec(),
			updated: nowSec(),
			done_at: this.state.done_at || 0
		};
		this.state = st;

		return fs.write(STATE_FILE, JSON.stringify(st) + '\n').catch(function(err) {
			/* 写不进去（ACL 被改 / 磁盘满）不能假装成功：提示 + 页面仍可用 */
			ui.addNotification(null, E('p', {}, [
				_('保存向导进度失败：') + String(err) +
				_('（进度不会记住，但本页的操作不受影响）')
			]), 'warning');
		});
	},

	startOver: function() {
		var self = this;
		if (this._redirectTimer) {
			window.clearTimeout(this._redirectTimer);
			this._redirectTimer = null;
		}
		this.state = normalizeState({
			step: 0,
			done: 0,
			started: nowSec(),
			/* done_at 保留：历史完成时间仍是事实，只是本次要重新走一遍 */
			done_at: this.state.done_at
		});
		this.doctor = null;
		this.doctorErr = null;
		this._dryRun = null;
		return this.saveState().then(function() {
			self.heroTitle.textContent = _('引导');
			self.paintNav();
			self.paintBanner();
			self.paintStep();
		});
	},

	/* ---------------- 导航 ---------------- */

	doctorFailed: function() {
		var checks = (this.doctor && this.doctor.checks) || [];
		for (var i = 0; i < checks.length; i++)
			if (checks[i].status === 'fail')
				return true;
		return false;
	},

	/* 第 0 步是硬门：doctor 有 fail 就不许往下走（W1 的要求）。
	   读不到 doctor 结果不是 fail，是"不知道"——同样不放行，文案说清楚。 */
	canProceed: function() {
		if (this.state.step !== 0)
			return true;
		if (!this.doctor || this.doctorFailed())
			return false;
		return true;
	},

	next: function() {
		if (this.state.step >= STEPS.length - 1)
			return;

		if (!this.canProceed()) {
			ui.addNotification(null, E('p', {}, [
				this.doctorErr
					? _('环境自检没跑成功，先修好再继续：') + this.doctorErr
					: _('环境自检里有会静默失效的项（fail）。按上面的建议处理后点「重新自检」再继续。')
			]), 'danger');
			return;
		}

		this.goStep(this.state.step + 1);
	},

	goStep: function(n) {
		if (this._redirectTimer) {
			window.clearTimeout(this._redirectTimer);
			this._redirectTimer = null;
		}
		this.state.step = intIn(n, 0, STEPS.length - 1, 0);
		this.saveState();
		this.paintNav();
		this.paintStep();
	},

	paintNav: function() {
		var self = this;
		while (this.navBox.firstChild)
			this.navBox.removeChild(this.navBox.firstChild);

		STEPS.forEach(function(s, i) {
			var cls = 'wz-step';
			if (self.state.done || i < self.state.step)
				cls += ' is-done';
			if (!self.state.done && i === self.state.step)
				cls += ' is-current';

			self.navBox.appendChild(E('button', {
				'class': cls,
				'disabled': (i > self.state.step && !self.state.done) ? '' : null,
				'title': s.hint,
				'click': function() {
					/* 往回走永远允许；往前只能在已到达过的步之间点（下一步会再校验硬门） */
					if (i <= self.state.step || self.state.done)
						self.goStep(i);
				}
			}, [
				E('span', { 'class': 'wz-step-no' }, [ String(i) ]),
				E('span', { 'class': 'wz-step-title' }, [ s.title ]),
				E('span', { 'class': 'wz-step-hint' }, [ s.hint ])
			]));
		});

		if (this.state.done) {
			this.pill.className = 'isp-pill';
			this.pill.textContent = _('已完成 ') + fmtTime(this.state.done_at);
		}
		else {
			this.pill.className = 'isp-pill';
			this.pill.textContent = _('第 ') + this.state.step + _(' / 3 步');
		}

		this.prevBtn.style.display = (this.state.step > 0 && !this.state.done) ? '' : 'none';
		this.nextBtn.style.display = (this.state.step < STEPS.length - 1 && !this.state.done) ? '' : 'none';
		this.nextBtn.disabled = !this.canProceed();
		this.rollbackBtn.style.display = (this.state.step >= 2 || this.state.done) ? '' : 'none';
	},

	/* ---------------- 横幅：完成态 / 硬门提示 ---------------- */

	paintBanner: function() {
		while (this.bannerBox.firstChild)
			this.bannerBox.removeChild(this.bannerBox.firstChild);

		if (this.state.done) {
			this.bannerBox.appendChild(E('div', { 'class': 'isp-banner wz-done-banner' }, [
				E('div', { 'class': 'isp-banner-msg' }, [
					E('strong', {}, [ _('引导已完成') ]),
					E('div', {}, [
						_('完成时间：') + fmtTime(this.state.done_at) +
						_('。再次进入本页是「重新引导」：四步会重新走一遍，但下面的任何按钮都不会自动撤销已经生效的配置。')
					])
				])
			]));
			return;
		}

		if (this.state.step === 0 && this.doctorErr) {
			this.bannerBox.appendChild(E('div', { 'class': 'isp-banner is-bad' }, [
				E('div', { 'class': 'isp-banner-msg' }, [
					E('strong', {}, [ _('环境自检没跑成功') ]),
					E('div', {}, [ String(this.doctorErr) ]),
					E('div', { 'class': 'isp-banner-hint' }, [
						_('自检是只读的。修好上面的错误（多半是 rpcd 权限或 isp-split 版本不匹配），再点「重新自检」。')
					])
				])
			]));
			return;
		}

		if (this.state.step === 0 && this.doctor && this.doctorFailed()) {
			var n = ((this.doctor.summary || {}).conflict) || 0;
			this.bannerBox.appendChild(E('div', { 'class': 'isp-banner is-bad' }, [
				E('div', { 'class': 'isp-banner-msg' }, [
					E('strong', {}, [ _('有 ') + n + _(' 项会让分流静默失效（fail）') ]),
					E('div', {}, [
						(this.doctor.summary || {}).headline || _('先按下面的建议处理，再点「下一步」。')
					])
				])
			]));
		}
	},

	/* ---------------- 每步的渲染入口 ---------------- */

	paintStep: function() {
		var self = this;
		while (this.body.firstChild)
			this.body.removeChild(this.body.firstChild);

		if (this.state.done)
			return this.paintDone();

		this.paintNav();
		this.paintBanner();

		if (this.state.step === 0)
			this.paintCheck();
		else if (this.state.step === 1)
			this.paintLine();
		else if (this.state.step === 2)
			this.paintBind();
		else
			this.paintLive();

		this.paintNav();
	},

	/* ---------------- Step 0：环境自检 ---------------- */

	paintCheck: function() {
		var self = this;
		var box = E('section', { 'class': 'isp-section' }, [
			E('h3', {}, [ _('环境自检（doctor）') ]),
			E('p', { 'class': 'isp-desc' }, [
				_('只读体检：六项兼容矩阵 + 主机前提。不会产生业务流量、不改任何配置；有 fail 项时本页不允许继续。')
			]),
			this.checkBox = E('div', { 'class': 'wz-doctor' })
		]);
		this.body.appendChild(box);

		this.body.appendChild(E('div', { 'class': 'wz-actions' }, [
			E('button', {
				'class': 'cbi-button',
				'click': function() { self.loadDoctor(true); }
			}, [ _('重新自检') ])
		]));

		if (!this.doctor && !this.doctorErr)
			this.loadDoctor(false);
		else
			this.paintCheckResult();
	},

	loadDoctor: function(force) {
		var self = this;
		if (this.doctorBusy)
			return;
		if (this.doctor && !force) {
			this.paintCheckResult();
			return;
		}

		this.doctorBusy = true;
		this.doctor = null;
		this.doctorErr = null;
		if (this.checkBox) {
			while (this.checkBox.firstChild)
				this.checkBox.removeChild(this.checkBox.firstChild);
			this.checkBox.appendChild(E('div', { 'class': 'wz-loading' }, [ _('正在跑 doctor --json …') ]));
		}
		this.nextBtn.disabled = true;

		return this.runWizard('doctor').then(function(res) {
			self.doctorBusy = false;
			var data = parseJsonStr(res && res.stdout);
			if (!data) {
				var raw = (((res && res.stdout) || '') + ((res && res.stderr) || '')).trim();
				self.doctorErr = raw || (_('doctor --json 没有返回可解析的 JSON（退出码 ') +
					((res && res.code) != null ? res.code : '?') + '）');
				self.setOut(_('命令：isp-split doctor --json') + '\n\n' + self.doctorErr, res, 'bad');
				self.paintCheckResult();
				return;
			}
			self.doctor = data;
			self.setOut(_('命令：isp-split doctor --json') + _('（退出码 ') +
				((res && res.code) != null ? res.code : 0) + _('，0=全绿 / 1=有保留 / 2=会失效）'),
				res, self.doctorFailed() ? 'bad' : '');
			self.paintCheckResult();
		});
	},

	paintCheckResult: function() {
		if (!this.checkBox)
			return;

		while (this.checkBox.firstChild)
			this.checkBox.removeChild(this.checkBox.firstChild);

		if (this.doctorErr) {
			this.checkBox.appendChild(E('div', { 'class': 'isp-empty' }, [
				_('自检没跑成功：') + this.doctorErr
			]));
			/* 横幅依赖 doctor 结果，异步回来必须重画一次（否则红条永远不出现） */
			this.paintBanner();
			this.paintNav();
			return;
		}
		if (!this.doctor) {
			this.checkBox.appendChild(E('div', { 'class': 'wz-loading' }, [ _('正在跑 doctor --json …') ]));
			return;
		}

		var d = this.doctor;
		var host = d.host || {};
		var ow = host.openwrt || {};
		var mw = host.mwan3 || {};
		var mem = host.mem || {};
		var bins = host.bins || {};
		var missing = [];
		Object.keys(bins).forEach(function(k) {
			if (!bins[k])
				missing.push(k);
		});

		var hostBox = E('div', { 'class': 'isp-card wz-card' }, [
			E('h3', {}, [ _('主机前提') ]),
			kv(_('系统'), (ow.id || '?') + ' ' + (ow.release || '?') + ' · ' + (ow.target || '?')),
			kv(_('内核'), host.kernel || '?'),
			kv('nftables', host.nft || '?'),
			kv('mwan3', (mw.installed ? (mw.version || '?') : _('未安装')) +
				(mw.installed ? (mw.nft ? _('（nftables 版）') : _('（非 nftables 版，本项目不支持）')) : '')),
			kv('mmx_mask', (mw.mmx_mask || '?') + _('（来源：') + (mw.mmx_mask_source || '?') + '）'),
			kv(_('可用内存'), (Math.round((+mem.avail_kb || 0) / 1024)) + ' / ' +
				(Math.round((+mem.total_kb || 0) / 1024)) + ' MiB'),
			kv(_('缺必需命令'), missing.length ? missing.join(' ') : _('无')),
			kv(_('root 权限'), host.root ? _('是') : _('否（写操作会被拒）'))
		]);

		var sum = d.summary || {};
		var sumBox = E('div', { 'class': 'wz-summary' }, [
			E('span', { 'class': 'isp-tag is-ok' }, [ _('正常 ') + (sum.ok || 0) ]),
			E('span', { 'class': 'isp-tag is-warn' }, [ _('有保留 ') + (sum.warn || 0) ]),
			E('span', { 'class': 'isp-tag is-bad' }, [ _('会失效 ') + (sum.conflict || 0) ]),
			E('span', { 'class': 'isp-tag' }, [ _('未知 ') + (sum.unknown || 0) ]),
			E('span', { 'class': 'wz-summary-head' }, [ sum.headline || '' ])
		]);

		var list = E('div', { 'class': 'wz-checks' });
		(d.checks || []).forEach(function(c) {
			var st = c.status || 'unknown';
			var findings = c.findings || [];
			var fBox = E('div', { 'class': 'wz-find' });
			findings.forEach(function(f) {
				fBox.appendChild(E('div', {
					'class': 'wz-find-line',
					'title': f.code || ''
				}, [ '· ', f.detail || f.code || '' ]));
			});

			list.appendChild(E('div', { 'class': 'wz-check ' + statusCls(st) }, [
				E('div', { 'class': 'wz-check-head' }, [
					E('span', { 'class': 'isp-tag ' + statusCls(st) }, [ statusText(st) ]),
					E('span', { 'class': 'wz-check-title' }, [ c.title || c.id || '?' ]),
					E('span', { 'class': 'wz-check-conf' }, [ _('置信度 ') + (c.confidence || '?') ])
				]),
				fBox,
				E('div', { 'class': 'wz-advice' }, [ _('建议：') + (c.advice || _('无')) ])
			]));
		});

		this.checkBox.appendChild(hostBox);
		this.checkBox.appendChild(sumBox);
		this.checkBox.appendChild(list);

		if (this.doctorFailed())
			this.checkBox.appendChild(E('div', { 'class': 'wz-block' }, [
				_('上面有 fail 项：这是硬门，处理完点「重新自检」。在自检通过之前「下一步」是灰的——带着会静默失效的环境往下走，后面每一步的结果都不可信。')
			]));

		var gate = d.gate || {};
		if (gate.can_wire === false) {
			this.checkBox.appendChild(E('div', { 'class': 'wz-block' }, [
				_('wire/apply 门：阻断（') + ((gate.reasons || []).join(', ') || '?') + '）'
			]));
		}

		this.paintBanner();
		this.paintNav();
	},

	/* ---------------- Step 1：体检（可选） ---------------- */

	paintLine: function() {
		var box = E('section', { 'class': 'isp-section' }, [
			E('h3', {}, [ _('体检（可选）') ]),
			E('p', { 'class': 'isp-desc' }, [
				_('逐条 WAN 看出口类型、四段延迟、NAT 与归属地，用来判断哪条线更适合当主力。只读探测，不改任何配置。')
			])
		]);
		paintLc.call(this, box, this.lc);
		this.body.appendChild(box);
	},

	/* ---------------- Step 2：绑定骨架 ---------------- */

	paintBind: function() {
		var self = this;

		var box = E('section', { 'class': 'isp-section' }, [
			E('h3', {}, [ _('绑定骨架（mwan3）') ]),
			E('p', { 'class': 'isp-desc' }, [
				_('净机上 mwan3 里没有 interface/member/policy，先让 bootstrap 只补骨架：只新增，不覆盖已有段，不碰 network/firewall，也不 reload mwan3。')
			]),
			E('div', { 'class': 'wz-preview' }, [
				E('div', { 'class': 'wz-preview-head' }, [
					E('span', {}, [ _('预演（bootstrap 默认 dry-run，不写任何东西）') ]),
					E('button', {
						'class': 'cbi-button',
						'click': function() { self.runDryRun(true); }
					}, [ _('重新预演') ])
				]),
				this.dryBox = E('pre', { 'class': 'isp-out wz-dry' }, [ _('正在预演…') ])
			]),
			E('div', { 'class': 'wz-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': function() { self.applyBootstrap(); }
				}, [ _('应用骨架') ]),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': function() {
						window.location.href = L.url(CONFIG_URL);
					}
				}, [ _('完整编辑（ISP 表绑定）') ])
			]),
			E('p', { 'class': 'wz-hint' }, [
				_('骨架只解决「mwan3 里有没有段」。哪个运营商走哪条线属于 ISP 表，在「配置 → 策略映射」里改（上面右侧按钮直接跳过去，回来时向导会停在这一步）。')
			])
		]);

		this.body.appendChild(box);

		if (!this._dryRun)
			this.runDryRun(false);
		else
			this.paintDryRun();
	},

	runDryRun: function(force) {
		var self = this;
		if (this._dryRunBusy)
			return;
		if (this._dryRun && !force) {
			this.paintDryRun();
			return;
		}

		this._dryRunBusy = true;
		if (this.dryBox) {
			this.dryBox.textContent = _('正在预演（bootstrap，不写入）…');
			this.dryBox.className = 'isp-out wz-dry';
		}

		return this.runWizard('bootstrap_dry').then(function(res) {
			self._dryRunBusy = false;
			self._dryRun = res || { code: 0, stdout: '', stderr: '' };
			self.paintDryRun();
			self.setOut(_('命令：isp-split bootstrap（dry-run）') + '\n\n' +
				(((res.stdout || '') + (res.stderr || '')).trim() || _('(无输出)')), res,
				(res && res.code) ? 'bad' : '');
		});
	},

	paintDryRun: function() {
		if (!this.dryBox || !this._dryRun)
			return;
		var r = this._dryRun;
		var text = (((r.stdout || '') + (r.stderr || '')).trim()) || _('(无输出)');
		this.dryBox.textContent = text;
		this.dryBox.className = 'isp-out wz-dry' + ((r.code) ? ' is-bad' : '');
	},

	applyBootstrap: function() {
		var self = this;

		return this.confirm(_('确认写入 mwan3 骨架？'), [
			E('p', {}, [
				_('将写入 mwan3 配置：为发现的 WAN 新增 interface / member / policy 段（段名带 isp_split=1 标记）。')
			]),
			E('ul', { 'class': 'wz-list' }, [
				E('li', {}, [ _('只新增：已存在的 interface/member/policy 段一律跳过，不改名、不覆盖。') ]),
				E('li', {}, [ _('不碰 network / firewall / dhcp，不 reload mwan3（灰度）。') ]),
				E('li', {}, [ _('写入走 uci 暂存区 + 校验 + 原子替换；失败自动回滚，并留一份 mwan3 备份。') ]),
				E('li', {}, [ _('若预演提示「mwan3 已配置」，CLI 会拒绝并且一个字节都不改。') ])
			]),
			E('p', { 'class': 'wz-hint' }, [ _('命令：isp-split bootstrap --apply') ])
		], function() {
			return self.runBusy('bootstrap_apply', _('正在写入骨架…'), function(res) {
				if (res && res.code) {
					self.setNote(_('写入失败：留在本步。看下面的命令输出，处理后可以重试。'));
					return;
				}
				self.setNote(_('骨架已写入。下一步：绑定/核对 ISP 表，然后生效。'));
				ui.addNotification(null, E('p', {}, [ _('骨架已写入 mwan3') ]), 'info');
				self.runDryRun(true);
			});
		});
	},

	/* ---------------- Step 3：生效 ---------------- */

	paintLive: function() {
		var self = this;

		var syncBox = E('input', {
			'type': 'checkbox',
			'id': 'wz-sync-ack',
			'click': function(ev) { syncBtn.disabled = !ev.target.checked; }
		});

		var syncBtn = E('button', {
			'class': 'cbi-button cbi-button-negative',
			'disabled': '',
			'click': function() {
				if (!syncBox.checked)
					return;
				self.syncFlow();
			}
		}, [ _('直接同步（sync）') ]);

		var box = E('section', { 'class': 'isp-section' }, [
			E('h3', {}, [ _('生效') ]), 
			E('p', { 'class': 'isp-desc' }, [
				_('默认走灰度：先预演看映射对不对，再「启用」——它重写 mwan3 规则并把集合刷进 nftables。要一步到位就用「直接同步」。')
			]),

			E('div', { 'class': 'wz-cards' }, [
				E('div', { 'class': 'isp-card wz-card' }, [
					E('h3', {}, [ _('灰度（推荐）') ]),
					E('div', { 'class': 'wz-actions' }, [
						E('button', {
							'class': 'cbi-button',
							'click': function() { self.runPlan(); }
						}, [ _('预演生效（plan）') ]),
						E('button', {
							'class': 'cbi-button cbi-button-action',
							'click': function() { self.enableFlow(); }
						}, [ _('启用（wire + apply）') ])
					]),
					E('p', { 'class': 'wz-hint' }, [
						_('plan 只读：列出每个运营商集合的条目数与策略，不做任何改动。')
					])
				]),
				E('div', { 'class': 'isp-card wz-card' }, [
					E('h3', {}, [ _('一步到位') ]),
					E('label', { 'class': 'wz-ack' }, [
						syncBox,
						E('span', {}, [ _('我知道会短暂断流 1-3 秒') ])
					]),
					E('div', { 'class': 'wz-actions' }, [ syncBtn ]),
					E('p', { 'class': 'wz-hint' }, [
						_('sync = 下载数据 + 重写规则 + 刷入 nftables + reload mwan3。')
					])
				])
			])
		]);

		this.body.appendChild(box);
	},

	runPlan: function() {
		var self = this;
		return this.runBusy('plan', _('正在预演（plan，只读）…'), function(res) {
			self.setNote((res && res.code)
				? _('plan 失败：看下面的输出。常见原因是策略缺失或成员为空（第 2 步的 ISP 表绑定）。')
				: _('预演完成：以上是每个集合的条目数与策略。没问题就点「启用」。'));
		});
	},

	enableFlow: function() {
		var self = this;
		return this.confirm(_('确认重写规则并生效？'), [
			E('p', {}, [ _('将对 mwan3 与 nftables 做以下改动：') ]),
			E('ul', { 'class': 'wz-list' }, [
				E('li', {}, [ _('wire：重写 mwan3 的 ipset 段与规则块（只动带 isp_split=1 的部分）。') ]),
				E('li', {}, [ _('apply：把运营商集合刷进 nftables（inet mwan3 的 isp_* 集合）。') ]),
				E('li', {}, [ _('会 reload mwan3：分流流量短暂中断 1-3 秒。') ])
			]),
			E('p', { 'class': 'wz-hint' }, [ _('命令：isp-split wire && isp-split apply') ])
		], function() {
			return self.runBusy('wire', _('正在重写规则（wire）…'), function(r1) {
				if (r1 && r1.code) {
					self.setNote(_('wire 失败：留在本步，已生效的配置**没有**被撤销。'));
					return;
				}
				return self.runBusy('apply', _('正在刷入 nftables（apply）…'), function(r2) {
					if (r2 && r2.code) {
						self.setNote(_('apply 失败：规则已重写但集合没刷进去。看输出，重试 apply 即可。'));
						return;
					}
					return self.finish();
				});
			});
		});
	},

	syncFlow: function() {
		var self = this;
		return this.confirm(_('确认整链同步？'), [
			E('p', {}, [ _('isp-split sync 会依次做四件事：') ]),
			E('ul', { 'class': 'wz-list' }, [
				E('li', {}, [ _('下载最新运营商地址数据（替换 /etc/isp-split/data）。') ]),
				E('li', {}, [ _('重写 mwan3 的 ipset 段与规则块（isp_split=1）。') ]),
				E('li', {}, [ _('把集合刷进 nftables。') ]),
				E('li', {}, [ _('reload mwan3 —— 分流流量短暂中断 1-3 秒。') ])
			]),
			E('p', { 'class': 'wz-hint' }, [ _('命令：isp-split sync') ])
		], function() {
			return self.runBusy('sync', _('正在同步（下载 + 写规则 + 刷入 + reload）…'), function(res) {
				if (res && res.code) {
					self.setNote(_('同步失败：看下面的输出。已写入的部分不会自动回滚，可重试或「撤销本次引导」。'));
					return;
				}
				return self.finish();
			});
		});
	},

	/* ---------------- 完成态 ---------------- */

	finish: function() {
		var self = this;
		this.state.done = 1;
		this.state.done_at = nowSec();
		this.state.step = STEPS.length - 1;

		return this.saveState().then(function() {
			self.paintNav();
			self.paintBanner();
			self.paintDone();
			ui.addNotification(null, E('p', {}, [ _('引导已完成，正在跳转到状态页…') ]), 'info');
			self._redirectTimer = window.setTimeout(function() {
				window.location.href = L.url(OVERVIEW_URL);
			}, DONE_REDIRECT_MS);
		});
	},

	paintDone: function() {
		var self = this;
		while (this.body.firstChild)
			this.body.removeChild(this.body.firstChild);

		this.heroTitle.textContent = _('重新引导');

		this.body.appendChild(E('section', { 'class': 'isp-section' }, [
			E('div', { 'class': 'wz-done' }, [
				E('div', { 'class': 'wz-done-mark' }, [ '✓' ]),
				E('div', { 'class': 'wz-done-text' }, [
					E('strong', {}, [ _('引导已完成') ]),
					E('div', {}, [ _('完成时间：') + fmtTime(this.state.done_at) ]),
					E('div', { 'class': 'wz-hint' }, [
						_('状态已写入 /etc/isp-split/state/wizard.json（done=1）。分流是否按预期工作，请看状态页的运营商卡片与「双线健康」。')
					])
				])
			]),
			E('div', { 'class': 'wz-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': function() { window.location.href = L.url(OVERVIEW_URL); }
				}, [ _('前往状态页') ]),
				E('button', {
					'class': 'cbi-button',
					'click': function() { self.startOver(); }
				}, [ _('重新引导') ]),
				E('a', {
					'class': 'cbi-button',
					'href': L.url(CONFIG_URL)
				}, [ _('完整编辑（ISP 表绑定）') ])
			])
		]));

		this.paintNav();
	},

	/* ---------------- 撤销本次引导 ---------------- */

	rollbackFlow: function() {
		var self = this;
		this.setNote(_('正在列取将删除的 mwan3 段（预演，不写入）…'));

		/* 先跑不带 --yes 的预演：CLI 会把"将删除的段"打印到 stdout，然后因为
		   非交互环境拒绝执行（退出码非 0，一个字节都不改）。这份清单直接贴进
		   确认框——不靠前端猜哪些段会被删。 */
		return this.runWizard('rollback_list').then(function(res) {
			var text = ((res && res.stdout) || '').trim();
			var err = ((res && res.stderr) || '').trim();
			self.setOut(_('命令：isp-split bootstrap --rollback（预演）') + '\n\n' +
				(text || err || _('(无输出)')), res, '');

			if (!text) {
				self.setNote('');
				ui.addNotification(null, E('p', {}, [
					_('没有可回滚的段（或命令失败）：') + (err || _('未知原因'))
				]), 'warning');
				return;
			}

			self.setNote('');
			return self.confirm(_('确认撤销本次引导？'), [
				E('p', {}, [ _('将删除下面这些带 isp_split=1 标记的 mwan3 段（手配段一个都不动）：') ]),
				E('pre', { 'class': 'isp-out wz-dry' }, [ text ]),
				E('p', { 'class': 'wz-hint' }, [
					_('仍被其它策略引用的成员段会保留（删了 mwan3 会渲染失败）。命令：isp-split bootstrap --rollback --yes')
				])
			], function() {
				return self.runBusy('rollback_yes', _('正在撤销骨架…'), function(r) {
					if (r && r.code) {
						self.setNote(_('撤销失败：看下面的输出。'));
						return;
					}
					self.state.done = 0;
					self.state.done_at = 0;
					self.state.step = 2;
					return self.saveState().then(function() {
						self.heroTitle.textContent = _('引导');
						self.paintBanner();
						self.paintStep();
						ui.addNotification(null, E('p', {}, [ _('骨架已撤销') ]), 'info');
					});
				});
			});
		});
	},

	/* ---------------- 执行与输出 ---------------- */

	/* 唯一允许调用 CLI 的入口：key 必须在 WIZ 白名单里，argv 只从表里取 */
	runWizard: function(key) {
		var args = WIZ[key];
		if (!Array.isArray(args))
			return Promise.resolve({
				code: 126,
				stdout: '',
				stderr: _('子命令不在向导白名单里：') + String(key)
			});
		return fs.exec(CMD, args.slice());
	},

	/* 危险动作统一走这里：打印命令 + 退出码 + 输出；退出码非 0 时自动留在本步 */
	runBusy: function(key, note, done) {
		var self = this;
		if (this.busy)
			return Promise.resolve(null);
		this.busy = true;
		this.busyKey = key;
		this.setNote(note);
		this.setBusy(true);

		var args = WIZ[key] || [ key ];
		var cmdText = _('命令：isp-split ') + args.join(' ');

		return this.runWizard(key).then(function(res) {
			var out = (((res && res.stdout) || '') + ((res && res.stderr) || '')).trim();
			var code = (res && res.code != null) ? res.code : 0;
			self.busy = false;
			self.setBusy(false);
			self.setOut(cmdText + '\n' + _('退出码：') + code + '\n\n' + (out || _('(无输出)')),
				res, code ? 'bad' : 'ok');
			if (code)
				ui.addNotification(null, E('p', {}, [ _('执行失败：') + cmdText.replace(/^命令：/, '') ]), 'danger');
			return done ? done(res) : null;
		}).catch(function(err) {
			self.busy = false;
			self.setBusy(false);
			self.setNote('');
			self.setOut(cmdText + '\n' + _('执行失败：') + String(err), null, 'bad');
			ui.addNotification(null, E('p', {}, [ _('执行失败：') + String(err) ]), 'danger');
		});
	},

	setBusy: function(on) {
		var btns = this.body ? this.body.querySelectorAll('button') : [];
		for (var i = 0; i < btns.length; i++)
			btns[i].disabled = !!on;
		if (!on && this.nextBtn)
			this.nextBtn.disabled = !this.canProceed();
	},

	setNote: function(text, kind) {
		if (!this.note)
			return;
		this.note.textContent = text || '';
		this.note.className = 'wz-note' + (kind ? ' is-' + kind : '');
	},

	setOut: function(text, res, kind) {
		if (!this.out)
			return;
		this.out.textContent = text || '';
		this.out.className = 'isp-out' + (kind ? ' is-' + kind : '');
		this.out.scrollTop = 0;
		if (res && res.code === 126)
			this.setNote(_('这个按钮调用的子命令不在白名单里，已被拒绝。'), 'bad');
	},

	/* 统一的二次确认弹框：只包裹"已经写好的动作"，文案由调用方逐条列出 */
	confirm: function(title, kids, onOk) {
		return ui.showModal(title, kids.concat([
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('取消') ]),
				' ',
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': function() {
						ui.hideModal();
						return onOk();
					}
				}, [ _('确认执行') ])
			])
		]));
	},

	/* 只读页：不带 cbi-map，也不给 Save & Apply 底栏（同其他只读页的注释） */
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
