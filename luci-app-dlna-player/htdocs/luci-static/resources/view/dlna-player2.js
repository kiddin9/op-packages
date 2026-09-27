/* This is free software, licensed under the Apache License, Version 2.0 */

'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

var APLAY = '/usr/bin/aplay';
var MPC   = '/usr/bin/mpc';

/* LuCI 的 fs.exec 不会因非零退出码 reject，需自己判断 */
function mpcText(args) {
	return fs.exec(MPC, args).then(function (rv) {
		return (rv && rv.code === 0) ? (rv.stdout || '') : '';
	}).catch(function () { return ''; });
}
function mpcRun(args) {
	return fs.exec(MPC, args).catch(function () { });
}

return view.extend({
	load: function () {
		function running(cmd) {
			return fs.exec('/bin/pidof', [ cmd ]).then(function (rv) {
				return !!(rv && rv.code === 0 && (rv.stdout || '').trim() !== '');
			}).catch(function () { return false; });
		}
		return Promise.all([
			uci.load('dlna-player'),
			L.resolveDefault(fs.exec(APLAY, ['-l']), { stdout: '' }),
			mpcText(['status']),
			running('mpd'),
			running('upmpdcli'),
			mpcText(['listall'])
		]);
	},

	render: function (data) {
		var aplayOut = (data[1] && data[1].stdout) || '';
		var mpdUp    = data[3];
		var upnpUp   = data[4];
		var allFiles = (data[5] || '').split('\n').filter(function (s) { return s.trim() !== ''; });

		var cards = [];
		aplayOut.split('\n').forEach(function (line) {
			var mm = line.match(/^card\s+(\d+):\s+(\S+)\s+\[([^\]]+)\],\s+device\s+(\d+):\s+([^\[]+)\[([^\]]+)\]/);
			if (mm) {
				cards.push({
					dev: 'hw:' + mm[1] + ',' + mm[4],
					label: 'card ' + mm[1] + ' / device ' + mm[4] + ' — ' + mm[3] + ' / ' + mm[6].trim()
				});
			}
		});

		var m, s, o;

		m = new form.Map('dlna-player', _('DLNA Music Player'),
			_('Turn this device into a music player: auto-detect the sound card, configure MPD and upmpdcli (DLNA).'));

		/* ================= 基础设置 ================= */
		s = m.section(form.TypedSection, 'audio', _('Basic settings'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable audio service'),
			_('Turn the audio setup on or off. When off, MPD and upmpdcli are stopped and disabled.'));
		o.rmempty = false;
		o.default = '0';                 /* 默认关闭 */

		o = s.option(form.DummyValue, '_status', _('Service status'));
		o.rawhtml = true;
		o.cfgvalue = function () {
			function badge(ok, name) {
				return '<span style="display:inline-block;padding:.15rem .5rem;border-radius:.25rem;' +
					'color:#fff;background:' + (ok ? '#3c9a3c' : '#b94a48') + ';margin-right:.4rem">' +
					name + ' ' + (ok ? _('running') : _('stopped')) + '</span>';
			}
			return badge(mpdUp, 'MPD') + badge(upnpUp, 'upmpdcli');
		};

		o = s.option(form.Value, 'device', _('Sound card'),
			_('Leave empty to auto-detect. Pick a detected card below, or type a custom device such as <code>hw:0,0</code>.'));
		o.rmempty = true;
		o.placeholder = _('auto-detect');
		cards.forEach(function (c) { o.value(c.dev, c.label); });

		o = s.option(form.Value, 'music_dir', _('Music directory'),
			_('Where your music files are stored (can be a mount point, e.g. /mnt/sda1/music).'));
		o.default = '/srv/music';
		o.rmempty = false;

		o = s.option(form.Value, 'volume', _('Default volume'),
			_('Default playback volume (0-100). Applied when you save, and on boot if "Remember volume" is off.'));
		o.datatype = 'range(0,100)';
		o.default = '40';
		o.rmempty = false;

		/* DLNA 名称：默认留空 */
		o = s.option(form.Value, 'dlna_name', _('DLNA device name'),
			_('The name shown on your phone when casting music. Leave empty to use the hostname.'));
		o.rmempty = true;
		o.placeholder = _('use hostname');

		o = s.option(form.Flag, 'unmute', _('Unmute on boot'),
			_('ALSA devices are muted by default. Enable to unmute automatically.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'persist_volume', _('Remember volume'),
			_('Keep the playback volume across reboots.'));
		o.default = '1';
		o.rmempty = false;

		return m.render().then(function (node) {
			if (!document.getElementById('dlna-player-layout-css')) {
				document.head.appendChild(E('style', { 'id': 'dlna-player-layout-css' }, [
					'.dlna-player-row { display:flex; gap:1rem; flex-wrap:wrap; align-items:stretch; }',
					'.dlna-player-row > .dlna-player-col { flex:1 1 15rem; min-width:14rem; max-width:100%; display:flex; flex-direction:column; }',
					'.dlna-player-row > .dlna-player-col > .cbi-section { flex:1 1 auto; }',
					'.dlna-player-name { flex:1; min-width:0; white-space:nowrap; overflow-x:auto; overflow-y:hidden; padding:.1rem 0; }',
					'.dlna-player-row .cbi-value { display:flex; align-items:flex-start; gap:.75rem; flex-wrap:wrap; }',
					'.dlna-player-row .cbi-value-title { text-align:left; flex:0 0 8.5rem; max-width:8.5rem; padding-top:.35rem; }',
					'.dlna-player-row .cbi-value-field { flex:1 1 auto; min-width:0; }',
					'.dlna-player-row .cbi-value-description { margin-left:9.25rem; }',
					'.dlna-player-line { display:flex; align-items:center; gap:.75rem; flex-wrap:wrap; margin-bottom:.5rem; padding-left:1rem; }',
					'.dlna-player-line > label { flex:0 0 8.5rem; max-width:8.5rem; text-align:left; }',
					/* 列表也留出同样的左边距，视觉更整齐 */
					'.dlna-player-row .dlna-player-list { margin-left:1rem; }'
				]));
			}

			var h2 = node.querySelector('h2');
			if (h2) h2.style.width = '100%';
			var desc = node.querySelector('.cbi-map-descr');
			if (desc) desc.style.width = '100%';

			var formSec = node.querySelector('.cbi-section') ||
				E('div', { 'class': 'cbi-section dlna-player-col' }, []);

			var statusLine = E('code', {}, [ _('loading...') ]);
			var volSlider, volLabel, seekSlider, seekLabel;
			var repeatBtn, randomBtn, orderBtn;
			var filterInput, listFrame, listCount;
			var curFile = '';
			var fileRows = [];

			/* ---------- 状态刷新（就地更新） ---------- */
			function refreshStatus() {
				return Promise.all([
					mpcText(['status']),
					mpcText(['-f', '%file%', 'current'])
				]).then(function (r) {
					var st  = r[0] || '';
					var cur = (r[1] || '').trim();
					curFile = cur;

					var line = st.split('\n').filter(function (l) { return l.trim() !== ''; })
						.slice(0, 2).join(' — ');
					statusLine.textContent = line || _('stopped');

					/* 音量 */
					var vm = st.match(/volume:\s*(\d+)%/);
					if (vm && volSlider && document.activeElement !== volSlider) {
						volSlider.value = vm[1];
						volLabel.textContent = vm[1] + '%';
					}

					/* 播放进度：数字始终更新；滑块仅在未拖动时同步 */
					var pm = st.match(/#(\d+)\/(\d+)\s+(\d+):(\d+)\/(\d+):(\d+)/);
					if (seekSlider && seekLabel) {
						if (pm) {
							var elapsed = parseInt(pm[3], 10) * 60 + parseInt(pm[4], 10);
							var total   = parseInt(pm[5], 10) * 60 + parseInt(pm[6], 10);
							var pct = total > 0 ? Math.round(elapsed * 100 / total) : 0;
							/* 数字永远更新（修掉"拖动后数字不动"） */
							seekLabel.textContent = pm[3] + ':' + pm[4] + ' / ' + pm[5] + ':' + pm[6];
							/* 滑块只在没被拖动时跟随 */
							if (document.activeElement !== seekSlider)
								seekSlider.value = pct;
						} else {
							/* 没有播放时归零 */
							seekLabel.textContent = '0:00 / 0:00';
							if (document.activeElement !== seekSlider)
								seekSlider.value = 0;
						}
					}

					/* 循环 / 随机 / 顺序 */
					var rep = /repeat:\s*on/.test(st);
					var rnd = /random:\s*on/.test(st);
					var sgl = /single:\s*on/.test(st);
					if (repeatBtn) {
						repeatBtn.textContent = rep ? _('Loop: ON') : _('Loop: OFF');
						repeatBtn.className = 'btn cbi-button cbi-button-' + (rep ? 'apply' : 'reset');
					}
					if (randomBtn) {
						randomBtn.textContent = rnd ? _('Shuffle: ON') : _('Shuffle: OFF');
						randomBtn.className = 'btn cbi-button cbi-button-' + (rnd ? 'apply' : 'reset');
					}
					if (orderBtn) {
						var seq = !rnd && !rep && !sgl;      /* 三者都关 = 纯顺序播放 */
						orderBtn.textContent = seq ? _('Sequential: ON') : _('Sequential: OFF');
						orderBtn.className = 'btn cbi-button cbi-button-' + (seq ? 'apply' : 'reset');
					}

					fileRows.forEach(function (item) {
						var on = (item.name === cur);
						item.el.style.background = on ? '#e8f5e9' : '';
						item.el.style.fontWeight = on ? 'bold' : '';
					});
				});
			}

			function act(args) {
				return mpcRun(args).then(function () { return refreshStatus(); });
			}

			function nextLocalFile() {
				return mpcText(['-f', '%file%', 'current']).then(function (cur) {
					cur = (cur || '').trim();
					var i = allFiles.indexOf(cur);
					if (i >= 0 && i + 1 < allFiles.length) return allFiles[i + 1];
					return allFiles.length ? allFiles[0] : null;
				});
			}

			/* 播放某首：把「全部歌曲」加入队列，再跳到这一首
			   这样放完会自动播下一首（顺序播放）✅ */
			function playFile(f) {
				var idx = allFiles.indexOf(f);
				return mpcRun(['clear']).then(function () {
					return mpcRun(['add', '/']);
				}).then(function () {
					/* mpc play 用 1-based 序号；找不到时回退到第 1 首 */
					return mpcRun(['play', String(idx >= 0 ? idx + 1 : 1)]);
				}).then(function () { return refreshStatus(); });
			}

			function pbtn(label, style, handler) {
				return E('button', {
					'class': 'btn cbi-button cbi-button-' + style,
					'click': ui.createHandlerFn(this, handler)
				}, [ label ]);
			}

			/* ---------- 音乐列表（只滚动，不翻页） ---------- */
			function currentFilter() {
				return (filterInput && filterInput.value || '').toLowerCase();
			}

			function renderList() {
				var kw = currentFilter();
				var fl = kw ? allFiles.filter(function (f) { return f.toLowerCase().indexOf(kw) >= 0; })
				            : allFiles;

				fileRows = [];
				listFrame.innerHTML = '';
				if (!fl.length) {
					listFrame.appendChild(E('div', { 'style': 'padding:.8rem;color:#888;text-align:center' }, [
						_('No matching music.')
					]));
				} else {
					fl.forEach(function (f) {
						var row = E('div', {
							'style': 'display:flex;align-items:center;gap:.5rem;padding:.3rem .4rem;border-radius:.2rem'
						}, [
							pbtn(_('Play'), 'action', function () { return playFile(f); }),
							E('span', { 'class': 'dlna-player-name' }, [ f ]),
							pbtn(_('Add'), 'reset', function () {
								return mpcRun(['add', f]).then(function () { return refreshStatus(); });
							})
						]);
						fileRows.push({ name: f, el: row });
						listFrame.appendChild(row);
					});
				}

				listCount.textContent = _('Showing %d / %d').format(fl.length, allFiles.length);

				fileRows.forEach(function (item) {
					var on = (item.name === curFile);
					item.el.style.background = on ? '#e8f5e9' : '';
					item.el.style.fontWeight = on ? 'bold' : '';
				});
			}

			/* ============ 播放器区域 ============ */
			var playerSec = E('div', { 'class': 'cbi-section dlna-player-col' }, [
				E('h3', {}, [ _('Player') ]),
				E('p', { 'class': 'cbi-section-descr' }, [ _('Current:') + ' ', statusLine ]),

				/* 音量 */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Volume') ]),
					volSlider = E('input', {
						'type': 'range', 'min': '0', 'max': '100', 'step': '1',
						'style': 'flex:1;max-width:20rem;cursor:pointer'
					}, []),
					volLabel = E('code', { 'style': 'min-width:3rem' }, [ '--%' ])
				]),

				/* 进度 */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Progress') ]),
					seekSlider = E('input', {
						'type': 'range', 'min': '0', 'max': '100', 'step': '1',
						'style': 'flex:1;max-width:20rem;cursor:pointer'
					}, []),
					seekLabel = E('code', { 'style': 'min-width:7.5rem' }, [ '0:00 / 0:00' ])
				]),

				/* 播放控制（用 dlna-player-line 保证与左侧标签对齐一致） */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Player control') ]),
					E('div', { 'style': 'display:flex;gap:.5rem;flex-wrap:wrap' }, [
						pbtn(_('Play'),   'apply',  function () { return act(['play']); }),
						pbtn(_('Pause'),  'reset',  function () { return act(['pause']); }),
						pbtn(_('Stop'),   'reset',  function () { return act(['stop']); }),
						pbtn(_('Next track'), 'action', function () {
							return nextLocalFile().then(function (f) {
								if (!f) return refreshStatus();
								return playFile(f);
							});
						}),
						pbtn(_('Rescan'), 'action', function () { return act(['update']); })
					])
				]),

				/* 循环 / 随机 / 顺序 */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Play mode') ]),
					E('div', { 'style': 'display:flex;gap:.5rem;flex-wrap:wrap' }, [
						repeatBtn = pbtn(_('Loop: OFF'), 'reset', function () {
							return mpcText(['status']).then(function (st) {
								return act(['repeat', /repeat:\s*on/.test(st) ? 'off' : 'on']);
							});
						}),
						randomBtn = pbtn(_('Shuffle: OFF'), 'reset', function () {
							return mpcText(['status']).then(function (st) {
								return act(['random', /random:\s*on/.test(st) ? 'off' : 'on']);
							});
						}),
						orderBtn = pbtn(_('Sequential: ON'), 'apply', function () {
							/* 顺序播放：关闭 随机 / 循环 / 单曲 */
							return mpcRun(['random', 'off']).then(function () {
								return mpcRun(['repeat', 'off']);
							}).then(function () {
								return mpcRun(['single', 'off']);
							}).then(function () { return refreshStatus(); });
						})
					])
				]),

				/* 队列操作 */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Play queue') ]),
					E('div', { 'style': 'display:flex;gap:.5rem;flex-wrap:wrap' }, [
						pbtn(_('Clear queue'), 'reset', function () { return act(['clear']); })
					])
				]),

				/* 搜索 */
				E('div', { 'class': 'dlna-player-line' }, [
					E('label', {}, [ _('Search') ]),
					E('div', { 'style': 'flex:1;min-width:0;display:flex;flex-direction:column' }, [
						filterInput = E('input', {
							'type': 'text', 'class': 'cbi-input-text',
							'placeholder': _('type to filter...'),
							'style': 'width:100%;max-width:22rem'
						}, []),
						E('div', { 'style': 'margin-top:.2rem;color:#666;font-size:.9em' }, [
							listCount = E('span', {}, [ '' ])
						])
					])
				]),

				/* 列表：只滚动，不翻页 */
				listFrame = E('div', {
					'class': 'dlna-player-list',
					'style': 'border:1px solid #ccc;border-radius:.3rem;' +
						'max-height:20rem;overflow-y:auto;overflow-x:hidden;background:#fff'
				}, [])
			]);

			/* 响应式：宽屏并排，窄屏自动上下（靠 flex-wrap）
			   注意：LuCI 保存后会重渲染表单，导致自定义布局被清掉，
			   所以做成「可重复挂载」的函数，丢失时自动重建 ✅ */
			var layoutRow = null;

			function mountLayout() {
				/* 布局还在 → 什么都不做 */
				if (layoutRow && document.body.contains(layoutRow) &&
					document.body.contains(playerSec))
					return;

				/* 找到（或重新找到）基础设置那个 section */
				var fs = node.querySelector('.cbi-section.dlna-player-col') ||
				         node.querySelector('.cbi-section');
				if (!fs) return;

				/* 清掉可能残留的旧 row */
				var old = node.querySelector('.dlna-player-row');
				if (old) old.remove();

				layoutRow = E('div', { 'class': 'dlna-player-row' }, [
					E('div', { 'class': 'dlna-player-col' }, [ fs ]),
					playerSec
				]);
				node.appendChild(layoutRow);
			}

			mountLayout();

			/* ---- 事件绑定 ---- */
			var volTimer = null;
			volSlider.addEventListener('input', function () {
				var v = volSlider.value;
				volLabel.textContent = v + '%';
				if (volTimer) clearTimeout(volTimer);
				volTimer = setTimeout(function () {
					mpcRun(['volume', v]).then(function () { return refreshStatus(); });
				}, 150);
			});

			var seekTimer = null;
			seekSlider.addEventListener('input', function () {
				if (seekTimer) clearTimeout(seekTimer);
				seekTimer = setTimeout(function () {
					mpcRun(['seek', seekSlider.value + '%']).then(function () {
						/* 关键：拖完立即失焦，否则滑块会一直"被拖动中"而不再刷新 */
						seekSlider.blur();
						return refreshStatus();
					});
				}, 250);
			});

			filterInput.addEventListener('input', function () { renderList(); });

			renderList();
			refreshStatus();

			/* 每 3 秒同步一次状态（进度条会跟着走），顺便补回被清掉的布局 */
			var syncTimer = setInterval(function () {
				if (!document.body.contains(statusLine)) { clearInterval(syncTimer); return; }
				mountLayout();
				refreshStatus();
			}, 3000);

			return node;
		});
	},

	handleSaveApply: function (ev, mode) {
		var self = this;
		return this.handleSave(ev).then(function () {
			return uci.apply();
		}).catch(function (e) {
			console.warn('dlna-player: uci apply failed', e);
		}).then(function () {
			return fs.exec('/etc/init.d/dlna-player', ['start']);
		}).then(function () {
			/* 应用「默认音量」——保存时就立即生效（不等下次开机） */
			var v = uci.get('dlna-player', 'main', 'volume');
			if (v !== null && v !== undefined && v !== '')
				return fs.exec('/usr/bin/mpc', ['volume', String(v)]).catch(function () { });
		}).then(function () {
			ui.addNotification(null, E('p', _('Settings applied. Services restarted.')));
			/* 保存后 LuCI 会重渲染，稍等再刷新页面让布局重建 */
			window.setTimeout(function () { location.reload(); }, 2000);
		}).catch(function (e) {
			ui.addNotification(null, E('p', _('Apply failed: %s').format(
				(e && (e.message || e.toString())) || 'unknown')));
		});
	}
});
