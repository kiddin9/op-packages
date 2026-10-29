'use strict';
'require view';
'require fs';
'require ui';

/*
 * LuCI 配置页：策略映射 / 多线路 DNS / 域名分流
 *
 * 约定：
 *   · 所有文件解析与改写仍由 `isp-split conf` 在 shell 侧完成（带白名单校验、
 *     回读校验、失败回滚），前端只负责收集值；
 *   · 前端做一遍同样的校验，错误直接标在出错的输入框下面（红字），
 *     不必等后端返回；
 *   · `conf preview` 只把改动写进临时副本再跑 plan，"保存前预检"不会碰
 *     /etc/isp-split.conf。
 */

var CMD = '/usr/sbin/isp-split';

/* ---------------------------------------------------------------- 图标（内联 SVG） */

var ICONS = {
	refresh: '<path d="M20 11a8 8 0 1 0-2.3 6.3"/><path d="M20 4v7h-7"/>',
	check: '<path d="M4 12.5 9 17.5 20 6.5"/>',
	plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
	up: '<path d="M12 19V5"/><path d="M6 11l6-6 6 6"/>',
	down: '<path d="M12 5v14"/><path d="M6 13l6 6 6-6"/>',
	trash: '<path d="M4 7h16"/><path d="M9 7V4h6v3"/><path d="M6 7l1 13h10l1-13"/>',
	plug: '<path d="M9 3v6"/><path d="M15 3v6"/><path d="M6 9h12v3a6 6 0 0 1-12 0z"/><path d="M12 18v3"/>',
	save: '<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v6h8V4"/><path d="M8 20v-6h8v6"/>'
};

function svgIcon(name, size) {
	var span = document.createElement('span');
	span.className = 'isp-ico';
	span.innerHTML = '<svg viewBox="0 0 24 24" width="' + (size || 16) + '" height="' + (size || 16) +
		'" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" ' +
		'stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || ICONS.check) + '</svg>';
	return span;
}

/* ---------------------------------------------------------------- 工具 */

function run(args) {
	return fs.exec(CMD, args).then(function(res) {
		// fs.exec 不管退出码都会 resolve；非 0 必须变成 reject，
		// 否则校验失败也会被 UI 当成"已保存"。
		if (res && res.code) {
			var out = ((res.stdout || '') + (res.stderr || '')).trim();
			throw new Error('isp-split ' + args.join(' ') +
				' 失败（退出码 ' + res.code + '）' + (out ? '：' + out : ''));
		}
		return res;
	});
}

/* 行内错误提示：同一个 td 里紧跟输入框的一行红字 */
function errBox() {
	return E('div', { 'class': 'isp-err' });
}

function setErr(box, msg) {
	if (!box)
		return;
	if (msg) {
		box.textContent = msg;
		box.classList.add('is-on');
	} else {
		box.textContent = '';
		box.classList.remove('is-on');
	}
}

function isIPv4(s) {
	if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(s))
		return false;
	var p = s.split('.');
	for (var i = 0; i < p.length; i++) {
		if (+p[i] > 255)
			return false;
	}
	return true;
}

function isDomain(s) {
	if (!/^[A-Za-z0-9._-]+$/.test(s))
		return false;
	if (s.charAt(0) === '.' || s.charAt(s.length - 1) === '.')
		return false;
	return s.indexOf('..') < 0;
}

function isSrc(s) {
	return /^[A-Za-z0-9._-]+$/.test(s);
}

function isSetName(s) {
	return /^[A-Za-z0-9_]{1,15}$/.test(s);
}

/* ---------------------------------------------------------------- 视图 */

return view.extend({
	load: function() {
		/* 配置字段走 conf get；数据源健康度走 health --json。
		   health/policy-check 失败不能拖垮整个配置页：捕获后渲染成“读取失败”。 */
		return Promise.all([
			run(['conf', 'get']),
			fs.exec(CMD, ['health', '--json']).catch(function() { return null; }),
			fs.exec(CMD, ['policy-check', '--json']).catch(function() { return null; })
		]);
	},

	render: function(res) {
		var self = this;
		var out = (res && res[0] && res[0].stdout) || '';
		var health = null;
		try {
			health = JSON.parse(((res[1] && res[1].stdout) || '').trim() || 'null');
		} catch (e) {
			health = null;
		}
		/* BUG-25：首装用户 mwan3 里没有 wan_only/wanb_only 策略时，
		   wire 会静默失效。这里在页面顶部给一条醒目提示 + 一键 init。 */
		var pcheck = null;
		try {
			pcheck = JSON.parse(((res[2] && res[2].stdout) || '').trim() || 'null');
		} catch (e) {
			pcheck = null;
		}

		var model = {
			mode: 'bind',
			policies: [],
			isp: [],
			dns: [],
			domains: [],
			/* lc:begin */
			lc: { enable: true, geo: true, provider: 'auto', interval: 60 }
			/* lc:end */
		};

		out.split('\n').forEach(function(line) {
			if (!line)
				return;
			/* 注释行不是数据行（B-1）。conf get 已在 shell 侧过滤，
			   这里再挡一次，避免旧版脚本或手工拼接的输出被渲染成红行。 */
			if (/^\s*#/.test(line))
				return;
			var f = line.split('\t');
			if (f[0] === 'dns_mode')
				model.mode = (f[1] || 'bind').trim();
			else if (f[0] === 'policies')
				model.policies = (f[1] || '').trim().split(/\s+/).filter(Boolean);
			else if (f[0] === 'isp' && f.length >= 5)
				model.isp.push({ src: f[1], set: f[2], policy: f[3], enabled: f[4] === '1' });
			else if (f[0] === 'dns' && f.length >= 3)
				model.dns.push({ policy: f[1], dns: f[2], test: null });
			else if (f[0] === 'domain' && f.length >= 3)
				model.domains.push({ domain: f[1], policy: f[2] });
			/* lc:begin */
			else if (f[0] === 'line_check_enable')
				model.lc.enable = (f[1] || '1') === '1';
			else if (f[0] === 'line_check_geo')
				model.lc.geo = (f[1] || '1') === '1';
			else if (f[0] === 'line_check_provider')
				model.lc.provider = f[1] || 'auto';
			else if (f[0] === 'line_check_interval')
				model.lc.interval = parseInt(f[1], 10) || 60;
			/* lc:end */
		});

		if (!model.isp.length) {
			return E('div', { 'class': 'isp-app cbi-map' }, [
				E('link', { 'rel': 'stylesheet', 'href': L.resource('isp-split/isp-split.css') }),
				E('h2', {}, [ _('运营商分流 · 配置') ]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('读不到 /etc/isp-split.conf 的 ISP_TABLE，请先确认已安装并执行过 isp-split fetch。')
				])
			]);
		}

		var result = E('pre', { 'id': 'cfg-out', 'class': 'isp-out is-empty', 'hidden': '' }, ['']);

		/* 没有输出时保持 hidden：主题的 pre{display:block} 会盖掉 hidden 属性，
		   CSS 里配了 .isp-out[hidden]{display:none!important}，这里只管切换属性。 */
		function showResult(text) {
			if (text) {
				result.textContent = text;
				result.removeAttribute('hidden');
				result.classList.remove('is-empty');
			}
			else {
				result.textContent = '';
				result.setAttribute('hidden', '');
				result.classList.add('is-empty');
			}
			result.scrollTop = 0;
		}

		/* ============================================================ 一、策略映射 */

		var ispTbody = E('tbody', {});

		function renderIsp() {
			while (ispTbody.firstChild)
				ispTbody.removeChild(ispTbody.firstChild);

			model.isp.forEach(function(row, idx) {
				row._err = row._err || {};

				var srcInp = E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'value': row.src,
					'placeholder': '源名，如 chinatelecom'
				});
				srcInp.addEventListener('input', function() {
					row.src = srcInp.value.trim();
					validateIspRow(row);
				});

				var setInp = E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'value': row.set,
					'placeholder': '集合名，<=15 字符'
				});
				setInp.addEventListener('input', function() {
					row.set = setInp.value.trim();
					validateIspRow(row);
				});

				var polSel = E('select', { 'class': 'cbi-input-select' },
					model.policies.map(function(p) {
						return E('option', { 'value': p, 'selected': p === row.policy ? '' : null }, [ p ]);
					}));
				if (!model.policies.length)
					polSel.appendChild(E('option', { 'value': '' }, [ _('（mwan3 里没有策略）') ]));
				polSel.addEventListener('change', function() {
					row.policy = polSel.value;
					validateIspRow(row);
				});

				var chk = E('input', { 'type': 'checkbox', 'checked': row.enabled ? '' : null });
				chk.addEventListener('change', function() { row.enabled = chk.checked; });

				var up = E('button', {
					'class': 'isp-icon-btn', 'title': _('上移（提高优先级）'),
					'disabled': idx === 0 ? '' : null,
					'click': function() { moveIsp(idx, -1); }
				}, [ svgIcon('up', 15) ]);

				var down = E('button', {
					'class': 'isp-icon-btn', 'title': _('下移（降低优先级）'),
					'disabled': idx === model.isp.length - 1 ? '' : null,
					'click': function() { moveIsp(idx, 1); }
				}, [ svgIcon('down', 15) ]);

				var tr = E('tr', {}, [
					E('td', { 'data-th': _('运营商') }, [ srcInp, row._err.src = errBox() ]),
					E('td', { 'data-th': _('集合') }, [ setInp, row._err.set = errBox() ]),
					E('td', { 'data-th': _('策略') }, [ polSel, row._err.policy = errBox() ]),
					E('td', { 'data-th': _('启用') }, [
						E('label', { 'class': 'isp-switch' }, [
							chk,
							E('span')
						])
					]),
					E('td', { 'data-th': _('顺序') }, [
						E('div', { 'class': 'isp-row-actions' }, [ up, down ])
					])
				]);
				ispTbody.appendChild(tr);
				validateIspRow(row);
			});
		}

		function moveIsp(idx, delta) {
			var to = idx + delta;
			if (to < 0 || to >= model.isp.length)
				return;
			var row = model.isp.splice(idx, 1)[0];
			model.isp.splice(to, 0, row);
			renderIsp();
		}

		function validateIspRow(row) {
			var err = row._err || {};
			var ok = true;

			if (!isSrc(row.src || '')) {
				setErr(err.src, _('只能包含字母、数字、点、下划线、连字符'));
				ok = false;
			} else {
				setErr(err.src, '');
			}

			if (!isSetName(row.set || '')) {
				setErr(err.set, _('1-15 个字符，只能是字母/数字/下划线'));
				ok = false;
			} else {
				var dup = model.isp.filter(function(r) { return r !== row && r.set === row.set; }).length;
				if (dup) {
					setErr(err.set, _('集合名重复'));
					ok = false;
				} else {
					setErr(err.set, '');
				}
			}

			if (!row.policy || (model.policies.length && model.policies.indexOf(row.policy) < 0)) {
				setErr(err.policy, _('mwan3 里没有这个策略'));
				ok = false;
			} else {
				setErr(err.policy, '');
			}

			row._valid = ok;
			return ok;
		}

		renderIsp();

		var addIspBtn = E('button', {
			'class': 'cbi-button cbi-button-neutral',
			'click': function() {
				model.isp.push({
					src: '', set: '', policy: model.policies[0] || '', enabled: true
				});
				renderIsp();
			}
		}, [ svgIcon('plus'), E('span', {}, [_('添加运营商')]) ]);

		/* ============================================================ 二、多线路 DNS */

		var dnsTbody = E('tbody', {});

		/* DNS 行 = mwan3 策略 ∪ DNS_TABLE 里已有但 mwan3 没列出的策略 */
		var dnsPolicies = model.policies.slice();
		model.dns.forEach(function(r) {
			if (dnsPolicies.indexOf(r.policy) < 0)
				dnsPolicies.push(r.policy);
		});
		dnsPolicies.forEach(function(p) {
			var exists = null;
			model.dns.forEach(function(r) { if (r.policy === p) exists = r; });
			if (!exists)
				model.dns.push({ policy: p, dns: '', test: null });
		});

		function renderDns() {
			while (dnsTbody.firstChild)
				dnsTbody.removeChild(dnsTbody.firstChild);

			model.dns.forEach(function(row) {
				row._err = errBox();

				var inp = E('input', {
					'type': 'text', 'class': 'cbi-input-text',
					'placeholder': _('该线路使用的 DNS，如 223.5.5.5'),
					'value': row.dns
				});
				inp.addEventListener('input', function() {
					row.dns = inp.value.trim();
					validateDnsRow(row);
				});

				var resSpan = E('div', { 'class': 'isp-test-result' }, [
					row.test ? row.test.text : ''
				]);
				if (row.test)
					resSpan.className = 'isp-test-result ' + (row.test.ok ? 'is-ok' : 'is-bad');

				var testBtn = E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'title': _('向该线路的 DNS 发一次查询'),
					'click': function() {
						resSpan.className = 'isp-test-result';
						resSpan.textContent = _('测试中…');
						/* 这里不能用 run()：DNS 不可用时命令返回 1，但 JSON 仍然有效 */
						return fs.exec(CMD, ['dnstest', row.policy, '--json']).then(function(r) {
							var d = null;
							try {
								d = JSON.parse((r.stdout || '').trim() || 'null');
							} catch (e) {
								d = null;
							}
							if (d && d.ok) {
								resSpan.className = 'isp-test-result is-ok';
								resSpan.textContent = _('可用') + '（' + (d.device || '?') + ' → ' +
									(d.answer || '?') + '）';
								row.test = { ok: true, text: resSpan.textContent };
							} else {
								resSpan.className = 'isp-test-result is-bad';
								resSpan.textContent = _('不可用（DNS 无响应）');
								row.test = { ok: false, text: resSpan.textContent };
							}
						}).catch(function(e) {
							resSpan.className = 'isp-test-result is-bad';
							resSpan.textContent = _('测线失败：') + String(e).replace(/^.*失败（[^）]*）：/, '');
						});
					}
				}, [ svgIcon('plug'), E('span', {}, [_('测线')]) ]);

				dnsTbody.appendChild(E('tr', {}, [
					E('td', { 'data-th': _('线路（策略）') }, [
						E('span', { 'class': 'isp-line-name' }, [ row.policy ]),
						row._err
					]),
					E('td', { 'data-th': _('DNS') }, [ inp ]),
					E('td', { 'data-th': _('测线') }, [
						E('div', { 'class': 'isp-row-actions' }, [ testBtn ]),
						resSpan
					])
				]));
				validateDnsRow(row);
			});
		}

		function validateDnsRow(row) {
			if (!row.dns) {
				setErr(row._err, '');
				row._valid = true;
				return true;
			}
			if (!isIPv4(row.dns)) {
				setErr(row._err, _('必须是 IPv4 地址，如 223.5.5.5'));
				row._valid = false;
				return false;
			}
			setErr(row._err, '');
			row._valid = true;
			return true;
		}

		renderDns();

		var modeSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'bind', 'selected': model.mode === 'bind' ? '' : null },
				[_('bind · dnsmasq 绑定出接口')]),
			E('option', { 'value': 'mark', 'selected': model.mode === 'mark' ? '' : null },
				[_('mark · nft 按目标 DNS 打标')])
		]);
		modeSel.addEventListener('change', function() { model.mode = modeSel.value; });

		/* ============================================================ 三、域名分流 */

		var domTbody = E('tbody', {});

		function renderDomains() {
			while (domTbody.firstChild)
				domTbody.removeChild(domTbody.firstChild);

			if (!model.domains.length) {
				domTbody.appendChild(E('tr', {}, [
					E('td', { 'colspan': 3, 'data-th': '' }, [
						E('div', { 'class': 'isp-empty' }, [
							_('尚未配置。大多数域名不需要在这里出现——只有 CDN 调度不准的站点才需要钉线。')
						])
					])
				]));
				return;
			}

			model.domains.forEach(function(row, idx) {
				var inp = E('input', {
					'type': 'text', 'class': 'cbi-input-text',
					'placeholder': _('域名后缀，如 bilivideo.com'),
					'value': row.domain
				});
				inp.addEventListener('input', function() {
					row.domain = inp.value.trim();
					validateDomainRow(row);
				});

				var sel = E('select', { 'class': 'cbi-input-select' },
					model.policies.map(function(p) {
						return E('option', { 'value': p, 'selected': p === row.policy ? '' : null }, [ p ]);
					}));
				sel.addEventListener('change', function() {
					row.policy = sel.value;
					validateDomainRow(row);
				});

				var del = E('button', {
					'class': 'isp-icon-btn is-danger', 'title': _('删除'),
					'click': function() {
						ui.showModal(_('确认删除'), [
							E('p', {}, [
								_('把 ') + (row.domain || _('这一行')) + _(' 从域名分流里删掉？')
							]),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': ui.hideModal }, [_('取消')]),
								' ',
								E('button', {
									'class': 'cbi-button cbi-button-negative',
									'click': function() {
										ui.hideModal();
										model.domains.splice(idx, 1);
										renderDomains();
									}
								}, [_('删除')])
							])
						]);
					}
				}, [ svgIcon('trash', 15) ]);

				var err = errBox();
				row._err = err;

				domTbody.appendChild(E('tr', {}, [
					E('td', { 'data-th': _('域名后缀') }, [ inp, err ]),
					E('td', { 'data-th': _('钉到线路') }, [ sel ]),
					E('td', { 'data-th': _('操作') }, [
						E('div', { 'class': 'isp-row-actions' }, [ del ])
					])
				]));
				validateDomainRow(row);
			});
		}

		function validateDomainRow(row) {
			if (!row.domain) {
				setErr(row._err, '');
				row._valid = true;
				return true;
			}
			if (!isDomain(row.domain)) {
				setErr(row._err, _('只能包含字母/数字/点/下划线/连字符，且不能以点开头或结尾'));
				row._valid = false;
				return false;
			}
			var dup = model.domains.filter(function(r) {
				return r !== row && r.domain === row.domain;
			}).length;
			if (dup) {
				setErr(row._err, _('域名重复'));
				row._valid = false;
				return false;
			}
			setErr(row._err, '');
			row._valid = true;
			return true;
		}

		renderDomains();

		var addDomBtn = E('button', {
			'class': 'cbi-button cbi-button-positive',
			'click': function() {
				model.domains.push({ domain: '', policy: model.policies[0] || '' });
				renderDomains();
			}
		}, [ svgIcon('plus'), E('span', {}, [_('添加域名')]) ]);

		/* lc:begin */
		/* ============================================================ 三、线路体检 */

		var lcEnable = E('input', { 'type': 'checkbox', 'checked': model.lc.enable ? '' : null });
		lcEnable.addEventListener('change', function() { model.lc.enable = lcEnable.checked; });

		var lcGeo = E('input', { 'type': 'checkbox', 'checked': model.lc.geo ? '' : null });
		lcGeo.addEventListener('change', function() {
			model.lc.geo = lcGeo.checked;
			lcProvider.disabled = !lcGeo.checked;
		});

		var lcProvider = E('select', { 'class': 'cbi-input-select', 'disabled': model.lc.geo ? null : '' },
			[
				['auto', _('自动（百度优先，失败转 ip-api）')],
				['baidu', _('只用百度（HTTPS）')],
				['ip-api', _('只用 ip-api（HTTP，明文）')],
				['off', _('关闭')]
			].map(function(o) {
				return E('option', { 'value': o[0], 'selected': model.lc.provider === o[0] ? '' : null }, [ o[1] ]);
			}));
		lcProvider.addEventListener('change', function() { model.lc.provider = lcProvider.value; });

		var lcInterval = E('input', {
			'type': 'number', 'class': 'cbi-input-text', 'min': '15', 'max': '3600',
			'value': String(model.lc.interval || 60)
		});
		var lcIntervalErr = errBox();
		lcInterval.addEventListener('input', function() {
			var n = parseInt(lcInterval.value, 10);
			model.lc.interval = isNaN(n) ? 0 : n;
			if (model.lc.interval < 15 || model.lc.interval > 3600) {
				setErr(lcIntervalErr, _('必须是 15-3600 之间的整数秒'));
				model.lc._valid = false;
			} else {
				setErr(lcIntervalErr, '');
				model.lc._valid = true;
			}
		});
		model.lc._valid = !(model.lc.interval < 15 || model.lc.interval > 3600);

		var lcSection = E('section', { 'class': 'isp-section' }, [
			E('h3', {}, [ _('线路体检') ]),
			E('p', { 'class': 'isp-desc' }, [
				_('对每条 WAN 做出口类型、四段延迟、NAT 与归属地检查。体检只读，不修改 mwan3/nft 规则。')
			]),
			E('table', { 'class': 'isp-form-table' }, [
				E('tbody', {}, [
					E('tr', {}, [
						E('td', { 'data-th': _('启用') }, [
							E('label', { 'class': 'isp-switch' }, [ lcEnable, E('span') ]),
							E('div', { 'class': 'lc-hint' }, [ _('关闭后命令行与页面都不再执行体检') ])
						]),
						E('td', { 'data-th': _('归属地查询') }, [
							E('label', { 'class': 'isp-switch' }, [ lcGeo, E('span') ]),
							E('div', { 'class': 'lc-hint' }, [
								_('关闭后只停止归属地查询；出口 IP 回显、STUN 与延迟探测仍会发出。卡片显示“未查询”')
							])
						])
					]),
					E('tr', {}, [
						E('td', { 'data-th': _('归属地服务商') }, [ lcProvider ]),
						E('td', { 'data-th': _('最小间隔') }, [
							E('div', { 'class': 'lc-inline' }, [
								lcInterval, E('span', { 'class': 'lc-hint' }, [ _('秒（15-3600）') ])
							]),
							lcIntervalErr
						])
					])
				])
			]),
			E('div', { 'class': 'isp-note lc-privacy-note' }, [
				_('隐私说明：开启归属地后，体检会把每条 WAN 的出口公网 IP 发送给第三方（默认百度，失败时 ip-api.com）查询归属地。'),
				_('只发送出口 IP，不发送内网地址、设备名、MAC、流量内容。ip-api 使用 HTTP，传输不加密；介意时请选择“关闭”或“只用百度”。'),
				_('关闭后省/市显示“未查询”，但仍会用本地 @isp_* 集合判断运营商大类（本机判断，不外发）。'),
				_('注意：关闭归属地只停止归属地查询；出口 IP 回显、STUN 与延迟探测仍会按配置的服务器发出。要完全停发，请关闭“启用”。')
			])
		]);
		/* lc:end */

		/* ============================================================ 四、数据源（只读） */

		/* 数据源地址是 root 路径的下载入口，配置页不开放编辑：
		   一个非法 URL 就能让 root 去拉任意内容。这里只展示现状，
		   修改方式指向 CONFIGURATION.md 的「多数据源」一节。 */
		var srcTbody = E('tbody', {});
		var srcRows = (health && health.sources) || [];
		var verifyEnabled = !!(health && health.verify_enabled);

		function srcRoleText(role) {
			if (role === 'primary')
				return _('主源');
			if (role === 'verify')
				return _('校验源');
			if (role === 'audit')
				return _('审计源');
			return role || '—';
		}

		function renderSources() {
			while (srcTbody.firstChild)
				srcTbody.removeChild(srcTbody.firstChild);

			if (!srcRows.length) {
				srcTbody.appendChild(E('tr', {}, [
					E('td', { 'colspan': 6, 'data-th': '' }, [
						E('div', { 'class': 'isp-empty' }, [
							health
								? _('没有数据源信息。')
								: _('读取数据源状态失败，请检查 isp-split health --json。')
						])
					])
				]));
				return;
			}

			srcRows.forEach(function(s) {
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

				srcTbody.appendChild(E('tr', {}, [
					E('td', { 'data-th': _('源') }, [ s.label || s.name ]),
					E('td', { 'data-th': _('角色') }, [
						E('span', { 'class': 'isp-tag' }, [ srcRoleText(s.role) ])
					]),
					E('td', { 'data-th': _('状态') }, [
						E('span', { 'class': tag }, [ text ])
					]),
					E('td', { 'data-th': _('最近 Jaccard') }, [
						s.jaccard != null ? (s.jaccard + '%') : '—'
					]),
					E('td', { 'data-th': _('最后成功') }, [ s.last_ok_text || '—' ]),
					E('td', { 'data-th': _('连续失败') }, [
						String(s.fail_days || 0)
					])
				]));
			});
		}

		renderSources();

		/* ============================================================ 保存 / 预检 */

		function values() {
			var ispVal = model.isp.map(function(r) {
				return r.src + ':' + r.set + ':' + r.policy + ':' + (r.enabled ? '1' : '0');
			}).join('|');

			var dnsVal = model.dns.filter(function(r) { return r.dns; })
				.map(function(r) { return r.policy + ':' + r.dns; }).join('|');

			var domVal = model.domains.filter(function(r) { return r.domain; })
				.map(function(r) { return r.domain + ':' + r.policy; }).join('|');

			return {
				isp: ispVal,
				dns: dnsVal,
				dom: domVal,
				mode: modeSel.value,
				/* lc:begin */
				lcEnable: model.lc.enable ? '1' : '0',
				lcGeo: model.lc.geo ? '1' : '0',
				lcProvider: model.lc.provider,
				lcInterval: String(model.lc.interval || 60)
				/* lc:end */
			};
		}

		/* 返回 true = 全部合法；出错的行已经标红 */
		function validateAll() {
			var ok = true;
			model.isp.forEach(function(r) { ok = validateIspRow(r) && ok; });
			model.dns.forEach(function(r) { ok = validateDnsRow(r) && ok; });
			model.domains.forEach(function(r) { ok = validateDomainRow(r) && ok; });

			if (!model.isp.length) {
				ui.addNotification(null, E('p', {}, [
					_('至少保留一行运营商映射')
				]), 'danger');
				ok = false;
			}
			/* lc:begin */
			if (!model.lc._valid) {
				ui.addNotification(null, E('p', {}, [
					_('线路体检的最小间隔必须是 15-3600 之间的整数秒')
				]), 'danger');
				ok = false;
			}
			/* lc:end */
			return ok;
		}

		function listErrors() {
			var msgs = [];
			model.isp.forEach(function(r) {
				if (r._valid === false)
					msgs.push(_('运营商行 ') + (r.set || r.src || '?') + _(' 有错误'));
			});
			model.dns.forEach(function(r) {
				if (r._valid === false)
					msgs.push(_('DNS 行 ') + r.policy + _(' 有错误'));
			});
			model.domains.forEach(function(r) {
				if (r._valid === false)
					msgs.push(_('域名行 ') + (r.domain || '?') + _(' 有错误'));
			});
			return msgs;
		}

		function step(args, log) {
			return run(args).then(function(r) {
				var t = ((r.stdout || '') + (r.stderr || '')).trim();
				log.push('$ isp-split ' + args.join(' ') + '\n' + (t || '  (无输出)'));
				return r;
			});
		}

		function preflight() {
			if (!validateAll()) {
				showResult(_('预检未通过：') + '\n  - ' + listErrors().join('\n  - '));
				ui.addNotification(null, E('p', {}, [_('表格里还有非法输入，先修正标红的行')]), 'danger');
				return;
			}

			var v = values();
			showResult(_('正在预检（只写临时副本，不会改动配置）…'));
			run(['conf', 'preview',
				'isp_table', v.isp,
				'dns_table', v.dns,
				'domain_split', v.dom,
				'dns_mode', v.mode
				/* lc:begin */
				,'line_check_enable', v.lcEnable,
				'line_check_geo', v.lcGeo,
				'line_check_provider', v.lcProvider,
				'line_check_interval', v.lcInterval
				/* lc:end */
			]).then(function(r) {
				showResult(((r.stdout || '') + (r.stderr || '')) || '(无输出)');
				ui.addNotification(null, E('p', {}, [_('预检完成，配置未被修改')]), 'info');
			}).catch(function(e) {
				showResult(_('预检失败：') + String(e));
				ui.addNotification(null, E('p', {}, [_('预检失败：') + String(e)]), 'danger');
			});
		}

		function save(apply) {
			if (!validateAll()) {
				showResult(_('保存已取消：') + '\n  - ' + listErrors().join('\n  - '));
				ui.addNotification(null, E('p', {}, [_('表格里还有非法输入，先修正标红的行')]), 'danger');
				return;
			}

			var v = values();
			var log = [];

			step(['conf', 'set', 'isp_table', v.isp], log)
				.then(function() { return step(['conf', 'set', 'dns_table', v.dns], log); })
				.then(function() { return step(['conf', 'set', 'domain_split', v.dom], log); })
				.then(function() { return step(['conf', 'set', 'dns_mode', v.mode], log); })
				/* lc:begin */
				.then(function() { return step(['conf', 'set', 'line_check_enable', v.lcEnable], log); })
				.then(function() { return step(['conf', 'set', 'line_check_geo', v.lcGeo], log); })
				.then(function() { return step(['conf', 'set', 'line_check_provider', v.lcProvider], log); })
				.then(function() { return step(['conf', 'set', 'line_check_interval', v.lcInterval], log); })
				/* lc:end */
				.then(function() {
					if (!apply)
						return null;
					return step(['wire'], log)
						.then(function() { return step(['apply'], log); })
						.then(function() { return step(['dns'], log); });
				})
				.then(function() {
					showResult(log.join('\n\n'));
					ui.addNotification(null, E('p', {}, [
						apply
							? _('已保存并生效')
							: _('已保存。改动需执行「保存并生效」或手动 wire/apply 后才生效')
					]), 'info');
				})
				.catch(function(e) {
					showResult(log.join('\n\n') + '\n\n错误: ' + String(e));
					ui.addNotification(null, E('p', {}, [ _('操作失败：') + String(e) ]), 'danger');
				});
		}

		/* BUG-25：策略缺失/空成员时页面顶部的醒目提示条。
		   只有 policy-check 明确返回 ok=false 才显示；读不到（旧版脚本/命令失败）
		   时保持安静，不用一个误报吓用户。 */
		var policyBanner = E('div', { 'class': 'isp-banner-wrap' });
		if (pcheck && pcheck.ok === false) {
			var bad = (pcheck.policies || []).filter(function(p) { return !p.ok; });
			var badText = bad.map(function(p) {
				return p.name + '（' + (p.detail || _('不可用')) + '）';
			}).join('、');
			var bannerErr = E('div', { 'class': 'isp-banner-err' });
			var bannerBtn;
			bannerBtn = E('button', {
				'class': 'cbi-button cbi-button-action isp-banner-btn',
				'click': function() {
					bannerBtn.disabled = true;
					bannerBtn.textContent = _('正在初始化…');
					bannerErr.textContent = '';
					return run(['init', '--assume-yes']).then(function() {
						ui.addNotification(null, E('p', {}, [ _('已绑定线路，页面将刷新') ]), 'info');
						window.location.reload();
					}).catch(function(e) {
						bannerBtn.disabled = false;
						bannerBtn.textContent = _('重新尝试初始化');
						bannerErr.textContent = String(e).replace(/^.*失败（[^）]*）：/, '');
					});
				}
			}, [ _('运行初始化绑定线路') ]);
			policyBanner = E('div', { 'class': 'isp-banner is-warn' }, [
				E('div', { 'class': 'isp-banner-msg' }, [
					E('strong', {}, [ _('mwan3 策略缺失或没有成员：分流规则不会生效') ]),
					E('div', {}, [ _('需要绑定的策略：') + badText ]),
					E('div', { 'class': 'isp-banner-hint' }, [
						_('按钮会按 ISP 表顺序自动绑定（wan_only→wan1、wanb_only→wan2…）；也可以 SSH 执行 '),
						E('code', {}, [ 'isp-split init' ]),
						_(' 逐个选择接口。')
					]),
					bannerErr
				]),
				bannerBtn
			]);
		}

		/* ============================================================ 页面 */

		return E('div', { 'class': 'isp-app cbi-map' }, [
			E('link', { 'rel': 'stylesheet', 'href': L.resource('isp-split/isp-split.css') }),

			E('div', { 'class': 'isp-hero' }, [
				E('h2', {}, [ _('运营商分流 · 配置') ]),
				E('div', { 'class': 'isp-sub' }, [
					_('改动写入 /etc/isp-split.conf：写入前校验、写入后回读，语法不合法自动回滚。')
				])
			]),

			policyBanner,

			/* ---- 策略映射 ---- */
			E('section', { 'class': 'isp-section' }, [
				E('h3', {}, [ _('策略映射') ]),
				E('p', { 'class': 'isp-desc' }, [
					_('顺序即优先级：排在前面的运营商优先占有重叠地址。集合名同时是 mwan3 规则名（<=15 字符）。')
				]),
				E('table', { 'class': 'isp-form-table' }, [
					E('thead', {}, [
						E('tr', {}, [
							E('th', {}, [_('运营商（源名）')]),
							E('th', {}, [_('集合')]),
							E('th', {}, [_('策略')]),
							E('th', {}, [_('启用')]),
							E('th', {}, [_('顺序')])
						])
					]),
					ispTbody
				]),
				E('div', { 'class': 'isp-btn-row' }, [ addIspBtn ])
			]),

			/* ---- 多线路 DNS ---- */
			E('section', { 'class': 'isp-section' }, [
				E('h3', {}, [ _('多线路 DNS') ]),
				E('p', { 'class': 'isp-desc' }, [
					_('让每条线用自己运营商的 DNS，CDN 才会把本运营商节点返回给你。留空表示不配置。')
				]),
				E('table', { 'class': 'isp-form-table' }, [
					E('thead', {}, [
						E('tr', {}, [
							E('th', {}, [_('线路（策略）')]),
							E('th', {}, [_('DNS 服务器')]),
							E('th', {}, [_('测线')])
						])
					]),
					dnsTbody
				]),
				E('div', { 'class': 'isp-btn-row' }, [
					E('span', { 'class': 'isp-line-name' }, [_('出线方式')]),
					modeSel
				]),
				/* 这行解释原来挤在 .isp-tag 胶囊里，窄屏换成两行后首尾字符被圆角压掉，
				   看着像被截断。改成普通说明段落：整段换行显示，title 再兜一次全文。 */
				E('div', {
					'class': 'isp-note',
					'title': _('bind 依赖 dnsmasq @接口；mark 用 nft 打标，OpenClash 接管 DNS 时更稳')
				}, [
					_('bind 依赖 dnsmasq @接口；mark 用 nft 打标，OpenClash 接管 DNS 时更稳')
				])
			]),

			/* ---- 域名分流 ---- */
			E('section', { 'class': 'isp-section' }, [
				E('h3', {}, [ _('域名分流') ]),
				E('p', { 'class': 'isp-desc' }, [
					_('未列出的域名走系统默认上游（通常就是 PPPoE 下发的运营商 DNS，无需配置）。'),
					_('只有个别站点 CDN 调度不准时，才需要把它的域名钉到指定线路。')
				]),
				E('table', { 'class': 'isp-form-table' }, [
					E('thead', {}, [
						E('tr', {}, [
							E('th', {}, [_('域名后缀')]),
							E('th', {}, [_('钉到线路')]),
							E('th', {}, [_('操作')])
						])
					]),
					domTbody
				]),
				E('div', { 'class': 'isp-btn-row' }, [ addDomBtn ])
			]),

			/* lc:begin */
			/* ---- 线路体检 ---- */
			lcSection,
			/* lc:end */

			/* ---- 数据源（只读） ---- */
			E('section', { 'class': 'isp-section' }, [
				E('h3', {}, [ _('数据源'), E('span', { 'class': 'isp-tag' }, [ _('只读') ]) ]),
				E('p', { 'class': 'isp-desc' }, [
					_('主源出数据，校验源只跑日 diff；分歧超阈值会拒绝更新并保留旧数据。'),
					_('为避免把非法 URL 写进 root 路径，本页只展示、不开放编辑。')
				]),
				E('div', { 'class': 'isp-btn-row' }, [
					E('span', {
						'class': 'isp-tag' + (verifyEnabled ? ' is-ok' : '')
					}, [ verifyEnabled ? _('校验已启用') : _('校验未启用') ]),
					E('span', { 'class': 'isp-tag' }, [
						_('源声明来自 ISP_SOURCES')
					])
				]),
				E('table', { 'class': 'isp-form-table' }, [
					E('thead', {}, [
						E('tr', {}, [
							E('th', {}, [_('源')]),
							E('th', {}, [_('角色')]),
							E('th', {}, [_('状态')]),
							E('th', {}, [_('最近 Jaccard')]),
							E('th', {}, [_('最后成功')]),
							E('th', {}, [_('连续失败')])
						])
					]),
					srcTbody
				]),
				E('div', { 'class': 'isp-note' }, [
					_('修改数据源请编辑 /etc/isp-split.conf 的 ISP_SOURCES / ISP_SOURCE_FILES，'),
					E('a', {
						'href': 'https://github.com/jihebube/openwrt-isp-split/blob/main/docs/CONFIGURATION.md',
						'target': '_blank',
						'rel': 'noopener'
					}, [ _('配置文档') ]),
					_(' 的「多数据源」一节有完整字段说明与降级行为表。')
				])
			]),

			E('div', { 'class': 'isp-footer-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': preflight
				}, [ svgIcon('refresh'), E('span', {}, [_('保存前预检')]) ]),
				E('button', {
					'class': 'cbi-button',
					'click': function() { save(false); }
				}, [ svgIcon('save'), E('span', {}, [_('仅保存')]) ]),
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': function() { save(true); }
				}, [ svgIcon('check'), E('span', {}, [_('保存并生效')]) ])
			]),

			result
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
