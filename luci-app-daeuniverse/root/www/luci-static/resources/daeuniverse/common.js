'use strict';
'require baseclass';
'require rpc';
'require uci';
'require fs';
'require ui';
'require poll';
'require dom';
'require view';
'require form';
'require session';

function showNotification(title, children, type, timeout) {
	timeout = (timeout != null) ? timeout : 3000;
	if (ui && ui.addTimeLimitedNotification) {
		return ui.addTimeLimitedNotification(title, children, timeout, type);
	}
	if (!ui || !ui.addNotification) return null;
	var node = ui.addNotification(title, children, type);
	if (node && timeout > 0) {
		setTimeout(function() {
			if (node && node.parentNode) {
				node.classList.add('fade-out');
				node.classList.remove('fade-in');
				setTimeout(function() {
					if (node && node.parentNode) {
						node.parentNode.removeChild(node);
					}
				}, 800);
			}
		}, timeout);
	}
	return node;
}

var callStatus = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'status',
	expect: { }
});

var callGetCores = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'get_cores',
	expect: { }
});

var callPrepareCoreSwitch = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'prepare_core_switch',
	params: [ 'core' ],
	expect: { }
});

var callValidateConfig = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'validate_config',
	params: [ 'core' ],
	expect: { }
});

var callReload = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'reload',
	expect: { success: true }
});

var callRestart = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'restart',
	expect: { success: true }
});

var callGetLog = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'get_log',
	expect: { }
});

var callClearLog = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'clear_log',
	expect: { success: true }
});

var callDashboardInfo = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'get_dashboard_info',
	params: [ 'type' ],
	expect: { }
});

var callDownloadDashboard = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'download_dashboard',
	params: [ 'url', 'type' ],
	expect: { }
});

var callDownloadStatus = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'download_status',
	expect: { }
});

var callSwitchDashboardApi = rpc.declare({
	object: 'luci.daeuniverse',
	method: 'switch_dashboard_api',
	params: [ 'type', 'defer_apply' ],
	expect: { }
});

function settingsSection() {
	var sections = uci.sections('daeuniverse', 'daeuniverse') || [];
	return sections[0] || {};
}

function isServiceEnabled() {
	return settingsSection().enabled === '1';
}

function getConfiguredCore() {
	var c = settingsSection().core;
	return (c === 'dae' || c === 'honk') ? c : 'honk';
}

function coreLabel(core) {
	return (core === 'dae') ? 'DAE' : 'HONK';
}

function updateStatus(data, targetEl) {
	var el = targetEl || document.getElementById('daeu_status');
	if (!el) return;
	var core = (data && (data.active_core || data.configured_core)) || getConfiguredCore();
	var label = coreLabel(core);
	if (data && data.running) {
		var mem = data.memory ? ' (' + _('Memory Usage') + ': ' + data.memory + ')' : '';
		dom.content(el, [
			E('span', { 'style': 'color: var(--success, #22c55e); font-weight: bold;' }, label + ' ' + _('RUNNING')),
			' ',
			E('span', { 'style': 'color: var(--text-muted, #888); font-size: 0.9em;' }, mem)
		]);
	} else {
		dom.content(el, [
			E('span', { 'style': 'color: var(--danger, #ef4444); font-weight: bold;' }, label + ' ' + _('NOT RUNNING'))
		]);
	}
}

function addElementPoll(fn, el, interval, onDetach) {
	var missing = 0;

	var pollFn = function() {
		if (document.body.contains(el)) {
			missing = 0;
		} else if (++missing > 1) {
			poll.remove(pollFn);
			if (typeof onDetach === 'function')
				onDetach();
			return Promise.resolve();
		}

		return fn();
	};

	poll.add(pollFn, interval);

	return pollFn;
}

function waitForServiceState(wantRunning, attempts) {
	attempts = attempts || 10;

	return new Promise(function(resolve) {
		var tries = 0;

		function step() {
			callStatus().then(function(st) {
				var running = !!(st && st.running);

				if (running === wantRunning || ++tries >= attempts) {
					updateStatus(st);
					if (poll && typeof(poll.start) === 'function')
						poll.start();
					resolve({ running: running, status: st });
				} else {
					setTimeout(step, 1200);
				}
			}).catch(function() {
				if (++tries >= attempts) {
					updateStatus({ running: false });
					if (poll && typeof(poll.start) === 'function')
						poll.start();
					resolve({ running: null });
				} else {
					setTimeout(step, 1200);
				}
			});
		}

		step();
	});
}

function msgText(res, fallback) {
	var d = (res && res.detail) ? String(res.detail) : '';

	if (res && res.code) {
		switch (res.code) {
		case 'dae_not_installed':
			return _('/usr/bin/dae is not installed');
		case 'dae_validate_failed':
			return _('dae configuration validation failed') + (d ? ': ' + d : '');
		case 'invalid_core':
			return _('Invalid core') + (d ? ': ' + d : '');
		case 'core_not_installed':
			return _('Selected core is not installed') + (d ? ': ' + d : '');
		case 'layout_unmanaged':
			return _('Entry file should only contain include { config.d/*.dae api.dae } for kdae managed editing.') + (d ? ' (' + d + ')' : '');
		case 'reload_failed':
			return _('Failed to reload service');
		case 'restart_failed':
			return _('Failed to restart service');
		case 'invalid_url':
			return _('Invalid URL');
		case 'unsafe_target':
			return _('Refusing to deploy to an unsafe target directory');
		case 'script_missing':
			return _('Download script not found') + (d ? ': ' + d : '');
		case 'download_failed':
			return _('Failed to start download task');
		case 'invalid_dashboard_type':
			return _('Invalid dashboard type');
		case 'native_secret_required':
			return _('native_api.config_write requires secret or password_auth.');
		case 'native_listen_not_numeric':
			return _('native_api.listen must be a numeric IP:port (for example 0.0.0.0:9527).');
		}
	}

	return (res && res.message) || fallback;
}

function switchDashboardAndWait(type, deferApply) {
	return callSwitchDashboardApi(type, !!deferApply).then(function(resp) {
		if (!resp || resp.success === false)
			throw new Error(msgText(resp, _('Service did not accept the request')));

		if (resp.pending_download)
			return { pending: true };

		if (deferApply || !isServiceEnabled())
			return { pending: false, running: null };

		return waitForServiceState(true).then(function(st) {
			return { pending: false, running: st.running };
		});
	});
}

var DOWNLOAD_MAX_TICKS = 900;
var DOWNLOAD_STALE_TICKS = 90;
var activeDownloadCancel = null;

function triggerDashboardDownload(url, type, logBox, progressWrap, onFinish) {
	progressWrap.style.display = 'block';
	logBox.innerText = _('Initializing download task...\n');

	var ticks = 0, stale = 0, lastStatus = '', lastLog = '', pollFn = null;

	if (activeDownloadCancel)
		activeDownloadCancel();

	function stop() {
		if (pollFn) {
			poll.remove(pollFn);
			pollFn = null;
		}

		if (activeDownloadCancel === cancel)
			activeDownloadCancel = null;
	}

	function cancel() {
		stop();

		if (onFinish)
			onFinish(false);
	}

	activeDownloadCancel = cancel;

	function fail(message) {
		stop();
		if (message) {
			logBox.innerText += message + '\n';
			logBox.scrollTop = logBox.scrollHeight;
		}
		if (onFinish)
			onFinish(false);
	}

	callDownloadDashboard(url, type).then(function(resp) {
		if (!resp || resp.success === false) {
			fail(_('Failed to trigger download:') + ' ' + (resp ? msgText(resp, _('Unknown error')) : _('Unknown error')));
			return;
		}

		pollFn = function() {
			if (!document.body.contains(progressWrap)) {
				stop();
				return Promise.resolve();
			}

			if (++ticks > DOWNLOAD_MAX_TICKS) {
				fail(_('Download did not finish in time.'));
				return Promise.resolve();
			}

			return callDownloadStatus().then(function(sResp) {
				if (!sResp)
					return;

				if (sResp.status !== lastStatus || sResp.log !== lastLog) {
					lastStatus = sResp.status;
					lastLog = sResp.log || '';
					stale = 0;
				} else {
					stale++;
				}

				if (sResp.log) {
					logBox.innerText = sResp.log;
					logBox.scrollTop = logBox.scrollHeight;
				}

				if (sResp.status === 'SUCCESS') {
					stop();
					logBox.scrollTop = logBox.scrollHeight;
					if (onFinish)
						onFinish(true);
				} else if (sResp.status === 'FAILED') {
					fail(null);
				} else if (stale > DOWNLOAD_STALE_TICKS) {
					fail(_('Download task stopped reporting progress.'));
				}
			}).catch(function() { });
		};

		poll.add(pollFn, 1);
	}).catch(function(err) {
		fail(_('Download error:') + ' ' + (err.message || err));
	});
}

function readFile(path) {
	if (fs.read_direct) {
		return fs.read_direct(path).catch(function() {
			return L.resolveDefault(fs.read(path), '');
		});
	}
	return L.resolveDefault(fs.read(path), '');
}

function writeFile(path, content) {
	var clean = (content || '').replace(/\r\n/g, '\n');
	return fs.write(path, clean);
}

function loadStyle(href) {
	if (!document.querySelector('link[href="' + href + '"]')) {
		var link = document.createElement('link');
		link.rel = 'stylesheet';
		link.href = href;
		document.head.appendChild(link);
	}
}

function loadScript(src) {
	return new Promise(function(resolve, reject) {
		var existing = document.querySelector('script[src="' + src + '"]');
		if (existing) {
			resolve();
			return;
		}
		var s = document.createElement('script');
		s.src = src;
		s.async = false;
		s.onload = function() { resolve(); };
		s.onerror = function() { reject(new Error('Failed to load ' + src)); };
		document.head.appendChild(s);
	});
}

function ensureEditorStyles() {
	if (document.getElementById('daeu-editor-custom-style')) return;

	var style = document.createElement('style');
	style.id = 'daeu-editor-custom-style';
	style.textContent = [
		'.cbi-value.hidden { display: none !important; }',
		'.daeu-status-field { display: inline-flex !important; align-items: center !important; justify-content: flex-start !important; gap: 16px !important; flex-wrap: wrap !important; min-height: 32px !important; }',
		'.daeu-editor-toolbar { margin-bottom: 6px !important; margin-top: 0 !important; display: flex !important; align-items: center !important; justify-content: flex-start !important; }',
		'.cm-format-btn { margin: 0 !important; cursor: pointer !important; }',
		'.daeu-code-row { display: block !important; }',
		'.daeu-code-row > .cbi-value-title { display: block !important; width: auto !important; flex: none !important; padding: 0 0 6px 0 !important; }',
		'.daeu-code-row > .cbi-value-field { display: block !important; width: auto !important; flex: none !important; }',
		'.daeu-editor { display: block !important; width: 100% !important; min-width: 0 !important; }',
		'.daeu-editor > .CodeMirror { width: 100% !important; }',
		'.daeu-editor-compact > .CodeMirror { min-height: 240px !important; }',
		'.CodeMirror {',
		'	border: 1px solid var(--border, #d5d9de) !important;',
		'	border: 1px solid var(--border, light-dark(#d5d9de, #2a2f37)) !important;',
		'	border-radius: var(--radius-base, 4px);',
		'	height: auto;',
		'	min-height: 480px;',
		'	font-family: var(--font-mono, monospace);',
		'	font-size: 13px;',
		'	background: var(--background, var(--background-color-high, #ffffff)) !important;',
		'	background: var(--background, var(--background-color-high, light-dark(#ffffff, #16181c))) !important;',
		'	color: var(--foreground, var(--text, var(--text-color-highest, #1f2328))) !important;',
		'	color: var(--foreground, var(--text, var(--text-color-highest, light-dark(#1f2328, #e6e8ea)))) !important;',
		'	box-shadow: none;',
		'}',
		'.CodeMirror-gutters {',
		'	border-right: 1px solid var(--border, light-dark(#e3e6ea, #262b33)) !important;',
		'	background: var(--surface-raised, var(--surface-sunken, var(--background-color-low, #f7f7f7))) !important;',
		'	background: var(--surface-raised, var(--surface-sunken, var(--background-color-low, light-dark(#f7f7f7, #111317)))) !important;',
		'}',
		'.CodeMirror-linenumber { color: var(--muted-foreground, var(--text-muted, #8a919b)) !important; }',
		'.CodeMirror-linenumber { color: var(--muted-foreground, var(--text-muted, light-dark(#8a919b, #6b7686))) !important; }',
		'.CodeMirror-cursor { border-left: 1px solid var(--foreground, var(--text, light-dark(#1f2328, #e6e8ea))) !important; }',
		'.CodeMirror-activeline-background { background: light-dark(#f3f6f9, #1b2027) !important; }',
		'div.CodeMirror-selected { background: light-dark(#d9e2ec, #2b3440) !important; }',
		'.CodeMirror-focused div.CodeMirror-selected { background: light-dark(#b9cfe7, #33414f) !important; }',
		'.cm-s-default .cm-comment { color: light-dark(#a50, #7b8794) !important; }',
		'.cm-s-default .cm-keyword { color: light-dark(#708, #c792ea) !important; }',
		'.cm-s-default .cm-string { color: light-dark(#a11, #7ec699) !important; }',
		'.cm-s-default .cm-number { color: light-dark(#164, #f78c6c) !important; }',
		'.cm-s-default .cm-def { color: light-dark(#00f, #82aaff) !important; }',
		'.cm-s-default .cm-variable { color: light-dark(#1f2328, #e6e8ea) !important; }',
		'.cm-s-default .cm-variable-2 { color: light-dark(#05a, #82aaff) !important; }',
		'.cm-s-default .cm-variable-3, .cm-s-default .cm-type { color: light-dark(#085, #7fdbca) !important; }',
		'.cm-s-default .cm-operator { color: light-dark(#1f2328, #a8b3c2) !important; }',
		'.cm-s-default .cm-bracket { color: light-dark(#997, #8b98a9) !important; }',
		'.cm-s-default .cm-meta, .cm-s-default .cm-qualifier { color: light-dark(#555, #8b98a9) !important; }',
		'.cm-s-default .cm-builtin { color: light-dark(#30a, #c792ea) !important; }',
		'.cm-s-default .cm-tag { color: light-dark(#170, #7ec699) !important; }',
		'.cm-s-default .cm-attribute { color: light-dark(#00c, #82aaff) !important; }',
		'.CodeMirror-foldmarker { color: light-dark(#1f2328, #e6e8ea) !important; background: light-dark(#eef2f6, #262b33) !important; }'
	].join('\n');
	document.head.appendChild(style);
}

var _cmPromise = null;

function ensureCodeMirror() {
	if (_cmPromise) {
		return _cmPromise;
	}

	loadStyle(L.resource('daeuniverse/lib/codemirror.css'));
	loadStyle(L.resource('daeuniverse/addon/fold/foldgutter.css'));
	ensureEditorStyles();

	if (window.CodeMirror && window.CodeMirror.modes && window.CodeMirror.modes.dae) {
		_cmPromise = Promise.resolve(window.CodeMirror);
		return _cmPromise;
	}

	_cmPromise = loadScript(L.resource('daeuniverse/lib/codemirror.js'))
		.then(function() {
			return Promise.all([
				loadScript(L.resource('daeuniverse/addon/edit/matchbrackets.js')),
				loadScript(L.resource('daeuniverse/addon/edit/closebrackets.js')),
				loadScript(L.resource('daeuniverse/addon/fold/foldcode.js')),
				loadScript(L.resource('daeuniverse/addon/fold/foldgutter.js')),
				loadScript(L.resource('daeuniverse/addon/fold/indent-fold.js')),
				loadScript(L.resource('daeuniverse/mode/dae/dae.js'))
			]);
		})
		.then(function() {
			return window.CodeMirror;
		}).catch(function(err) {
			_cmPromise = null;
			throw err;
		});

	return _cmPromise;
}

function preloadCodeMirror() {
	if (window.requestIdleCallback) {
		requestIdleCallback(function() {
			ensureCodeMirror().catch(function() {});
		}, { timeout: 2000 });
	} else {
		setTimeout(function() {
			ensureCodeMirror().catch(function() {});
		}, 300);
	}
}

function formatEditor(ed) {
	ed.operation(function() {
		var cursor = ed.getCursor();
		var content = ed.getValue();

		var exprPrefixes = [
			'geosite', 'geoip', 'keyword', 'full', 'suffix', 'regex', 'domain',
			'pname', 'subtag', 'name', 'mac', 'dip', 'sip', 'dport', 'sport',
			'l4proto', 'ipversion_prefer', 'fallback', 'qtype', 'qname',
			'upstream', 'ip', 'tag', 'inlist'
		];
		var exprRegex = new RegExp('\\b(' + exprPrefixes.join('|') + ')\\s*:\\s*', 'g');

		var formatCodeSegment = function(str) {
			str = str.replace(/\s*->\s*/g, ' -> ');
			str = str.replace(/\s*&&\s*/g, ' && ');
			str = str.replace(/([^\s])\s*\{/g, '$1 {');
			str = str.replace(/\s*,\s*/g, ', ');
			str = str.replace(exprRegex, '$1: ');
			return str;
		};

		var formatLineCode = function(lineStr) {
			lineStr = lineStr.replace(/^(\s*[a-zA-Z0-9_-]+)\s*:\s*(\S.*)$/, '$1: $2');
			lineStr = lineStr.replace(/^(\s*[a-zA-Z0-9_-]+)\s*:\s*$/, '$1:');

			var out = '';
			var seg = '';
			var inQuote = '';
			var escaped = false;
			for (var j = 0; j < lineStr.length; j++) {
				var ch = lineStr.charAt(j);
				if (inQuote) {
					out += ch;
					if (escaped) {
						escaped = false;
					} else if (ch === '\\') {
						escaped = true;
					} else if (ch === inQuote) {
						inQuote = '';
					}
					continue;
				}
				if (ch === "'" || ch === '"') {
					out += formatCodeSegment(seg) + ch;
					seg = '';
					inQuote = ch;
					continue;
				}
				if (ch === '#') {
					var formattedSeg = formatCodeSegment(seg);
					if (formattedSeg.length > 0 && !/\s$/.test(formattedSeg)) {
						formattedSeg += ' ';
					}
					out += formattedSeg + lineStr.slice(j).trimEnd();
					seg = '';
					return out.trimEnd();
				}
				seg += ch;
			}
			out += formatCodeSegment(seg);
			return out.trimEnd();
		};

		var lines = content.split('\n');
		var formattedLines = lines.map(function(line) {
			var trimmed = line.trim();
			if (!trimmed) {
				return '';
			}

			if (trimmed.startsWith('#')) {
				var afterComment = trimmed.slice(1);

				var kvMatch = afterComment.match(/^(\s*)([a-zA-Z0-9_-]+)\s*:\s*(.*)$/);
				if (kvMatch) {
					var space = kvMatch[1];
					var key = kvMatch[2];
					var val = kvMatch[3].trim();
					return (line.match(/^\s*/)[0] + '#' + space + key + ': ' + val).trimEnd();
				}

				if (afterComment.indexOf('->') !== -1 || afterComment.indexOf('&&') !== -1) {
					var leadingWs = line.match(/^\s*/)[0];
					var formattedCommentCode = formatLineCode(afterComment);
					return (leadingWs + '#' + (afterComment.startsWith(' ') ? ' ' : '') + formattedCommentCode.trim()).trimEnd();
				}

				return line.trimEnd();
			}

			return formatLineCode(line);
		});

		ed.setValue(formattedLines.join('\n'));

		for (var i = 0; i < ed.lineCount(); i++) {
			ed.indentLine(i, 'smart');
		}
		ed.setCursor(cursor);
	});
}

function bindCodeMirrorToMap(m, onSaveCallback) {
	if (!m || m._cmHooked) return;
	m._cmHooked = true;
	ensureEditorStyles();

	var origRenderContents = m.renderContents;
	m.renderContents = function() {
		return origRenderContents.apply(this, arguments).then(function(mapNode) {
			var target = mapNode || m.root || document.getElementById('cbi-' + m.config) || document;
			target.querySelectorAll('textarea').forEach(function(ta) {
				if (ta.dataset.cmInitialized === 'true' || ta._editor) return;

				if (ta.offsetParent !== null) {
					initCodeMirror(ta, onSaveCallback);
				} else if (window.IntersectionObserver) {
					var row = ta.closest('.cbi-value') || ta;
					var io = new IntersectionObserver(function(entries) {
						if (entries[0] && entries[0].isIntersecting) {
							io.disconnect();
							initCodeMirror(ta, onSaveCallback).then(function(editor) {
								if (editor) {
									requestAnimationFrame(function() {
										editor.refresh();
									});
								}
							});
						}
					});
					io.observe(row);
				} else {
					initCodeMirror(ta, onSaveCallback);
				}
			});
			return mapNode;
		});
	};
}

function initCodeMirror(textarea, onSaveCallback) {
	if (textarea.dataset.cmInitialized === 'true' || textarea._editor) {
		return Promise.resolve(textarea._editor);
	}
	textarea.dataset.cmInitialized = 'true';

	return ensureCodeMirror().then(function(CodeMirror) {
		var editor = CodeMirror.fromTextArea(textarea, {
			mode: 'dae',
			indentUnit: 4,
			tabSize: 4,
			styleActiveLine: true,
			lineNumbers: true,
			theme: 'default',
			lineWrapping: true,
			matchBrackets: true,
			autoCloseBrackets: true,
			foldGutter: true,
			gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter']
		});
		textarea._editor = editor;

		var syncTextarea = function() {
			textarea.value = editor.getValue();
			textarea.dispatchEvent(new Event('input', { bubbles: true }));
			textarea.dispatchEvent(new Event('change', { bubbles: true }));
			if (typeof onSaveCallback === 'function') {
				onSaveCallback(textarea.value);
			}
		};

		editor.on('change', syncTextarea);

		var formatBtn = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cm-format-btn',
			'click': function() {
				try {
					formatEditor(editor);
					syncTextarea();
					formatBtn.textContent = '\u2713 ' + _('Formatted');
					formatBtn.classList.add('cbi-button-positive');
					clearTimeout(formatBtn._resetTimer);
					formatBtn._resetTimer = setTimeout(function() {
						formatBtn.textContent = _('Format Code');
						formatBtn.classList.remove('cbi-button-positive');
					}, 1500);
				} catch (e) {
					console.error('Format failed:', e);
					showNotification(null, E('p', _('Failed to format code:') + ' ' + (e.message || e)), 'error');
				}
			}
		}, _('Format Code'));

		var toolbar = E('div', { 'class': 'daeu-editor-toolbar' }, [ formatBtn ]);

		var wrapper = editor.getWrapperElement();
		var holderClass = (textarea.rows && parseInt(textarea.rows, 10) < 20)
			? 'daeu-editor daeu-editor-compact'
			: 'daeu-editor';
		var holder = E('div', { 'class': holderClass });

		wrapper.parentNode.insertBefore(holder, wrapper);
		holder.appendChild(toolbar);
		holder.appendChild(wrapper);

		var row = textarea.closest('.cbi-value');
		if (row)
			row.classList.add('daeu-code-row');

		editor.refresh();

		if (window.IntersectionObserver) {
			var observer = new IntersectionObserver(function(entries) {
				for (var i = 0; i < entries.length; i++) {
					if (entries[i].isIntersecting) {
						editor.refresh();
					}
				}
			});
			observer.observe(wrapper);
		}

		var mapEl = textarea.closest('.cbi-map');
		if (mapEl) {
			var mapInst = (window.L && window.L.dom) ? window.L.dom.findClassInstance(mapEl) : null;
			if (mapInst && !mapInst._cmHooked) {
				bindCodeMirrorToMap(mapInst, onSaveCallback);
			}
		}

		return editor;
	});
}

function renderHiddenPage(title, reason) {
	var hint = (reason === 'advanced')
		? _('This page belongs to the advanced mode. Enable Advanced Settings in the global settings to use it.')
		: _('This page belongs to a web dashboard. Select one in the global settings to use it.');

	return E('div', { 'class': 'cbi-map' }, [
		E('style', {}, '.cbi-page-actions { display: none !important; }'),
		E('h2', {}, title),
		E('div', { 'class': 'cbi-section' }, [
			E('p', {}, hint),
			E('p', {}, E('a', {
				'class': 'btn cbi-button cbi-button-action',
				'href': L.url('admin', 'services', 'daeuniverse', 'global')
			}, _('Open Global Settings')))
		])
	]);
}

function resolveConfigEntries(filesOrPath, core, fieldTitle) {
	var resolved = (typeof filesOrPath === 'function') ? filesOrPath(core) : filesOrPath;
	if (Array.isArray(resolved))
		return resolved;
	return [{ name: '_content', path: resolved, title: fieldTitle, rows: 25 }];
}

function createConfigFileView(filesOrPath, mapTitle, mapDesc, fieldTitle, successMsg, needRestart, opts) {
	var initialCore = 'honk';

	return view.extend({
		load: function() {
			return uci.load('daeuniverse').then(function() {
				initialCore = getConfiguredCore();
			});
		},

		render: function() {
			var reason = hiddenTabReason(currentTab());

			if (reason)
				return renderHiddenPage(mapTitle, reason);

			var entries = resolveConfigEntries(filesOrPath, initialCore, fieldTitle);
			var desc = (typeof mapDesc === 'function') ? mapDesc(initialCore) : mapDesc;
			var m = new form.Map('daeuniverse', mapTitle, desc);

			var s = m.section(form.NamedSection, '_status');
			s.render = function() {
				return renderStatusHeader();
			};

			if (opts && typeof opts.renderBanner === 'function') {
				var banner = m.section(form.NamedSection, '_core_hint');
				banner.render = function() {
					return opts.renderBanner(initialCore);
				};
			}

			s = m.section(form.TypedSection, 'daeuniverse');
			s.anonymous = true;
			s.addremove = false;

			entries.forEach(function(entry, idx) {
				var optName = entry.name || ('_content_' + idx);
				var o = s.option(form.TextValue, optName, entry.title, entry.description || undefined);
				o.rows = entry.rows || 25;
				o.wrap = 'off';
				o.load = function() {
					return readFile(entry.path).then(function(content) {
						return content || '';
					});
				};
				o.write = function(section_id, formvalue) {
					return writeFile(entry.path, formvalue);
				};
			});

			bindCodeMirrorToMap(m);
			return m.render();
		},

		handleSaveApply: function(ev, mode) {
			var core = initialCore;
			return this.handleSave(ev).then(function() {
				if (!isServiceEnabled())
					return { skipped: true };

				return callValidateConfig(core).then(function(vres) {
					if (vres && vres.valid === false)
						throw new Error(msgText(vres, _('Configuration validation failed')));

					if (vres && vres.warning)
						showNotification(null, E('p', msgText(vres.warning)), 'warning', 6000);

					var call = needRestart ? callRestart : callReload;
					return call().then(function(resp) {
						if (!resp || resp.success === false)
							throw new Error(msgText(resp, _('Service did not accept the request')));

						return needRestart ? waitForServiceState(true) : callStatus().then(function(st) {
							updateStatus(st);
							return { running: !!(st && st.running) };
						});
					});
				});
			}).then(function(st) {
				if (st.skipped) {
					showNotification(null, E('p', _('Configuration saved. DAE Universe is disabled, so the service was not started.')), 'info');
					return;
				}

				if (st.running === false)
					throw new Error(_('Service did not come back up; check the logs'));

				if (st.running === null) {
					showNotification(null, E('p', _('Configuration saved, but the service state could not be confirmed.')), 'warning');
					return;
				}

				showNotification(null, E('p', successMsg || _('Configuration applied and service reloaded.')), 'info');
			}).catch(function(err) {
				showNotification(null, E('p', _('Failed to apply configuration:') + ' ' + (err.message || err)), 'error', 6000);
			});
		}
	});
}

var ADVANCED_TABS = [ 'dns', 'node', 'route' ];
var MENU_BASE_KEY = 'daeu-menu-base';
var MENU_STATE_KEY = 'daeu-menu-state';

function daeSettings() {
	return uci.get_first('daeuniverse', 'daeuniverse') || {};
}

function getHiddenTabs() {
	var settings = daeSettings();
	var hidden = [];

	if (settings.advanced !== '1')
		hidden = hidden.concat(ADVANCED_TABS);

	if (settings.dashboard === 'none')
		hidden.push('api');

	return hidden;
}

function hiddenTabReason(tab) {
	var settings = daeSettings();

	if (tab && ADVANCED_TABS.indexOf(tab) !== -1 && settings.advanced !== '1')
		return 'advanced';

	if (tab === 'api' && settings.dashboard === 'none')
		return 'dashboard';

	return null;
}

function currentTab() {
	var dispatch = (window.L && L.env && Array.isArray(L.env.dispatchpath)) ? L.env.dispatchpath : [];
	var fromUrl = window.location.pathname.match(/\/daeuniverse\/([a-z0-9_-]+)/);

	return (dispatch.length > 3) ? dispatch[3] : (fromUrl ? fromUrl[1] : '');
}

function daeuMenuNode(tree) {
	var node = tree;

	[ 'admin', 'services', 'daeuniverse' ].forEach(function(name) {
		node = (node && node.children) ? node.children[name] : null;
	});

	return node || null;
}

function hideMenuEntries(hidden) {
	var state = hidden.join(',');

	return ui.menu.load().then(function(tree) {
		if (!L.isObject(tree) || !L.isObject(tree.children))
			return;

		var cached = session.getLocalData('menu');
		var base = session.getLocalData(MENU_BASE_KEY);

		if (!L.isObject(cached) || !L.isObject(base)) {
			base = JSON.parse(JSON.stringify(tree));
			session.setLocalData(MENU_BASE_KEY, base);
		}

		if (L.isObject(cached) && session.getLocalData(MENU_STATE_KEY) === state)
			return;

		var filtered = JSON.parse(JSON.stringify(base));
		var root = daeuMenuNode(filtered);

		if (root && L.isObject(root.children)) {
			hidden.forEach(function(name) {
				if (root.children[name])
					root.children[name].satisfied = false;
			});
		}

		ui.menu.menu = filtered;

		session.setLocalData('menu', filtered);
		session.setLocalData(MENU_STATE_KEY, state);
	}).catch(function() {});
}

function hideTabLinks(hidden) {
	var allTargets = {};
	ADVANCED_TABS.concat(['api']).forEach(function(name) {
		allTargets[L.url('admin', 'services', 'daeuniverse', name)] = hidden.indexOf(name) !== -1;
	});

	document.querySelectorAll('a[href]').forEach(function(link) {
		if (link.closest('#view') || !(link.pathname in allTargets))
			return;

		var el = link.closest('li') || link;
		if (allTargets[link.pathname]) {
			el.style.setProperty('display', 'none', 'important');
		} else {
			el.style.removeProperty('display');
		}
	});
}

var lateLinks = null;

function watchLateLinks() {
	if (lateLinks || !window.MutationObserver)
		return;

	var queued = false;

	lateLinks = new MutationObserver(function() {
		if (queued)
			return;

		queued = true;

		window.setTimeout(function() {
			queued = false;
			hideTabLinks(getHiddenTabs());
		}, 100);
	});

	lateLinks.observe(document.body, { childList: true, subtree: true });
}

function applyTabVisibility() {
	return uci.load('daeuniverse').then(function() {
		var hidden = getHiddenTabs();

		hideTabLinks(hidden);
		watchLateLinks();

		return hideMenuEntries(hidden);
	}).catch(function() {
	});
}

function refreshTabVisibility() {
	uci.unload('daeuniverse');

	return applyTabVisibility();
}

applyTabVisibility();

function renderStatusHeader() {
	var statusEl = E('span', { 'id': 'daeu_status', 'style': 'font-weight: 500;' }, [
		E('em', {}, _('Collecting data...'))
	]);

	var reloadBtn = E('button', {
		'type': 'button',
		'class': 'btn cbi-button cbi-button-action',
		'click': function(ev) {
			var btn = ev.target;
			btn.disabled = true;
			btn.innerText = _('Reloading...');
			callReload().then(function() {
				btn.disabled = false;
				btn.innerText = _('Reload Service');
				showNotification(null, E('p', _('Service reload triggered successfully.')), 'info');
			}).catch(function(err) {
				btn.disabled = false;
				btn.innerText = _('Reload Service');
				showNotification(null, E('p', _('Failed to reload service:') + ' ' + (err.message || err)), 'error');
			});
		}
	}, _('Reload Service'));

	var section = E('fieldset', { 'class': 'cbi-section' }, [
		E('legend', {}, _('Status')),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Running Status')),
			E('div', { 'class': 'cbi-value-field daeu-status-field' }, [
				statusEl,
				reloadBtn
			])
		])
	]);

	callStatus().then(function(st) {
		updateStatus(st, statusEl);
	});

	var pollStatusFn = function() {
		return callStatus().then(function(st) {
			updateStatus(st, statusEl);
		}).catch(function() { });
	};

	addElementPoll(pollStatusFn, statusEl, 5);

	return section;
}

preloadCodeMirror();

return baseclass.extend({
	applyTabVisibility: applyTabVisibility,
	refreshTabVisibility: refreshTabVisibility,
	callStatus: callStatus,
	callGetCores: callGetCores,
	callPrepareCoreSwitch: callPrepareCoreSwitch,
	callValidateConfig: callValidateConfig,
	callReload: callReload,
	callRestart: callRestart,
	callGetLog: callGetLog,
	callClearLog: callClearLog,
	callDashboardInfo: callDashboardInfo,
	callDownloadDashboard: callDownloadDashboard,
	callDownloadStatus: callDownloadStatus,
	callSwitchDashboardApi: callSwitchDashboardApi,
	readFile: readFile,
	writeFile: writeFile,
	ensureCodeMirror: ensureCodeMirror,
	preloadCodeMirror: preloadCodeMirror,
	formatEditor: formatEditor,
	initCodeMirror: initCodeMirror,
	bindCodeMirrorToMap: bindCodeMirrorToMap,
	renderStatusHeader: renderStatusHeader,
	createConfigFileView: createConfigFileView,
	triggerDashboardDownload: triggerDashboardDownload,
	waitForServiceState: waitForServiceState,
	switchDashboardAndWait: switchDashboardAndWait,
	isServiceEnabled: isServiceEnabled,
	getConfiguredCore: getConfiguredCore,
	coreLabel: coreLabel,
	showNotification: showNotification,
	msgText: msgText,
	updateStatus: updateStatus,
	addElementPoll: addElementPoll
});
