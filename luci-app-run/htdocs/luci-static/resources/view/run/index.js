'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

// ====================== 纯JSON国际化 · 中英双语 ======================
const RUN_LANG = (function () {
	try {
		const m = document.cookie.match(/luci_lang=([a-zA-Z-]+)/);
		if (m) return m[1].substring(0, 2).toLowerCase();

		if (window.L && L.env && L.env.lang)
			return L.env.lang.substring(0, 2).toLowerCase();

		return 'zh';
	} catch (e) {
		return 'zh';
	}
})();

const I18N = {
	zh: {
		title: "Run安装器",
		desc: "在路由器上上传并执行 .run 安装包或 .sh 脚本，注意架构务必匹配。",
		drop_tip: "拖入一个 .run 或 .sh 文件，或从电脑选择。",
		choose_file: "选择 .run 或 .sh 文件",
		execute: "执行",
		clean_up: "清理",
		upload_title: "上传安装脚本 (.run / .sh)",
		log_title: "执行日志",
		clean_done: "临时文件与日志已清理。",
		only_run: "仅支持 .run 和 .sh 文件。",
		prepare_upload: "准备上传：%s (%s)",
		upload_failed: "上传失败。",
		uploading: "正在上传 %s：%d%%",
		upload_err: "上传请求失败。",
		upload_invalid: "上传返回格式无效。",
		upload_done: "上传完成：%s (%s)",
		starting: "正在启动安装器...",
		started: "安装器已启动，PID %d。",
		running: "安装器正在运行。",
		last_file: "上一次安装包：%s"
	},
	en: {
		title: "Run Installer",
		desc: "Upload and execute .run packages or .sh scripts on this router, ensuring architecture compatibility.",
		drop_tip: "Drop a .run or .sh file here, or choose one from your computer.",
		choose_file: "Choose .run or .sh file",
		execute: "Execute",
		clean_up: "Clean up",
		upload_title: "Upload installer script (.run / .sh)",
		log_title: "Execution log",
		clean_done: "Temporary files and logs were removed.",
		only_run: "Only .run and .sh files are accepted.",
		prepare_upload: "Preparing upload: %s (%s)",
		upload_failed: "Upload failed.",
		uploading: "Uploading %s: %d%%",
		upload_err: "Upload request failed.",
		upload_invalid: "Invalid upload response.",
		upload_done: "Upload complete: %s (%s)",
		starting: "Starting installer...",
		started: "Installer started, PID %d.",
		running: "Installer is running.",
		last_file: "Last installer: %s"
	}
};

function _(key) {
	const str = I18N[RUN_LANG]?.[key] || I18N.zh[key] || key;
	return str.format.apply(str, Array.prototype.slice.call(arguments, 1));
}
// ====================================================================

var uploadStart = rpc.declare({
	object: 'luci-app-run',
	method: 'upload_start',
	params: ['filename', 'size']
});

var uploadChunk = rpc.declare({
	object: 'luci-app-run',
	method: 'upload_chunk',
	params: ['id', 'data', 'index']
});

var uploadFinish = rpc.declare({
	object: 'luci-app-run',
	method: 'upload_finish',
	params: ['id']
});

var runInstaller = rpc.declare({
	object: 'luci-app-run',
	method: 'run',
	params: ['id']
});

var getStatus = rpc.declare({
	object: 'luci-app-run',
	method: 'status'
});

var readLog = rpc.declare({
	object: 'luci-app-run',
	method: 'read_log',
	params: ['offset']
});

var cleanup = rpc.declare({
	object: 'luci-app-run',
	method: 'cleanup'
});

function formatBytes(size) {
	if (size >= 1024 * 1024)
		return '%.1f MiB'.format(size / 1024 / 1024);

	if (size >= 1024)
		return '%.1f KiB'.format(size / 1024);

	return '%d B'.format(size);
}

function bufferToBase64(buffer) {
	var bytes = new Uint8Array(buffer);
	var parts = [];
	var chunk = 0x8000;

	for (var i = 0; i < bytes.length; i += chunk)
		parts.push(String.fromCharCode.apply(null, bytes.subarray(i, i + chunk)));

	return btoa(parts.join(''));
}

return view.extend({
	handleSave: null,
	handleReset: null,
	handleSaveApply: null,

	logOffset: 0,
	currentUploadId: null,

	load: function () {
		return getStatus().catch(function () {
			return {};
		});
	},

	render: function (status) {
		var self = this;

		var fileInput = E('input', {
			'type': 'file',
			accept: '.run,.sh,application/x-shellscript,application/octet-stream',
			style: 'display:none'
		});

		var progress = E('progress', {
			max: 100,
			value: 0,
			style: 'width:100%;display:none'
		});

		var state = E('div', { 'class': 'cbi-value-description' }, _('drop_tip'));

		var log = E('pre', {
			id: 'run-log',
			style: 'min-height:16em;max-height:32em;overflow:auto;background:#111;color:#eee;padding:1em;white-space:pre-wrap',
		}, ['']);

		var pickButton = E('button', {
			class: 'btn cbi-button cbi-button-apply',
			click: function (ev) {
				ev.preventDefault();
				fileInput.click();
			}
		}, [_('choose_file')]);

		var runButton = E('button', {
			class: 'btn cbi-button cbi-button-action',
			disabled: true,
			style: 'min-width:140px;padding:8px 32px;',
			click: function (ev) {
				ev.preventDefault();
				self.startRun(runButton, state);
			}
		}, [_('execute')]);

		var cleanButton = E('button', {
			class: 'btn cbi-button cbi-button-reset',
			style: 'margin-left:35px;',
			click: function (ev) {
				ev.preventDefault();
				cleanup().then(function (res) {
					if (res && res.error)
						throw new Error(res.error);

					self.currentUploadId = null;
					self.logOffset = 0;
					runButton.disabled = true;
					log.textContent = '';
					progress.style.display = 'none';
					state.textContent = _('clean_done');
				}).catch(function (err) {
					ui.addNotification(null, E('p', [err.message || err]), 'danger');
				});
			}
		}, [_('clean_up')]);

		var drop = E('div', {
			class: 'cbi-section',
			style: 'border:2px dashed var(--border-color-high,#999);padding:2em;text-align:center',
			dragover: function (ev) {
				ev.preventDefault();
				drop.style.borderStyle = 'solid';
			},
			dragleave: function () {
				drop.style.borderStyle = 'dashed';
			},
			drop: function (ev) {
				ev.preventDefault();
				drop.style.borderStyle = 'dashed';
				if (ev.dataTransfer.files && ev.dataTransfer.files.length)
					self.uploadFile(ev.dataTransfer.files[0], progress, state, runButton);
			}
		}, [
			E('h3', [_('upload_title')]),
			E('p', [state]),
			E('p', [pickButton, ' ', runButton, cleanButton]),
			progress,
			fileInput
		]);

		fileInput.addEventListener('change', function () {
			if (fileInput.files && fileInput.files.length)
				self.uploadFile(fileInput.files[0], progress, state, runButton);
		});

		poll.add(function () {
			return self.refreshLog(log, state);
		}, 1);

		this.applyStatus(status, state);

		return E('div', { class: 'cbi-map' }, [
			E('h2', [_('title')]),
			E('div', { class: 'cbi-map-descr', style: 'margin-bottom:15px' }, [_('desc')]),
			drop,
			E('div', { class: 'cbi-section' }, [
				E('h3', [_('log_title')]),
				log
			])
		]);
	},

	applyStatus: function (status, state) {
		if (!status) return;

		if (status.running)
			state.textContent = _('running');
		else if (status.file)
			state.textContent = _('last_file', status.file);
	},

	uploadFile: function (file, progress, state, runButton) {
		var self = this;

		// 支持 .run 和 .sh 文件
		if (!file.name.match(/\.(run|sh)$/i)) {
			ui.addNotification(null, E('p', [_('only_run')]), 'danger');
			return Promise.reject();
		}

		progress.style.display = '';
		progress.value = 0;
		runButton.disabled = true;
		state.textContent = _('prepare_upload', file.name, formatBytes(file.size));

		return uploadStart(file.name, file.size).then(function (res) {
			if (res && res.error)
				throw new Error(res.error);

			self.currentUploadId = res.id;
			return self.uploadFileFast(res, file, progress, state, runButton);
		}).catch(function (err) {
			progress.style.display = 'none';
			state.textContent = _('upload_failed');
			ui.addNotification(null, E('p', [err.message || err]), 'danger');
		});
	},

	uploadFileFast: function (session, file, progress, state, runButton) {
		var self = this;
		var url = '/cgi-bin/luci-app-run-upload?id=' +
			encodeURIComponent(session.id) + '&token=' + encodeURIComponent(session.token);

		return new Promise(function (resolve, reject) {
			var xhr = new XMLHttpRequest();
			xhr.open('POST', url, true);
			xhr.setRequestHeader('Content-Type', 'application/octet-stream');

			xhr.upload.onprogress = function (ev) {
				if (!ev.lengthComputable) return;
				progress.value = Math.floor(ev.loaded * 100 / ev.total);
				state.textContent = _('uploading', file.name, progress.value);
			};

			xhr.onerror = function () {
				document.querySelector('.cbi-button-action').disabled = false;
				reject(new Error(_('upload_err')));
			};

			xhr.onload = function () {
				document.querySelector('.cbi-button-action').disabled = false;
				progress.value = 100;

				uploadFinish(session.id).then(function () {
					state.textContent = _('upload_done', file.name, formatBytes(file.size));
				}).catch(function () {
					state.textContent = _('upload_done', file.name, formatBytes(file.size));
				});

				resolve();
			};

			xhr.send(file);
		});
	},

	startRun: function (runButton, state) {
		var self = this;

		if (!this.currentUploadId) return;

		runButton.disabled = true;
		state.textContent = _('starting');

		return runInstaller(this.currentUploadId).then(function (res) {
			if (res && res.error)
				throw new Error(res.error);

			self.logOffset = 0;
			state.textContent = _('started', res.pid);
		}).catch(function (err) {
			runButton.disabled = false;
			ui.addNotification(null, E('p', [err.message || err]), 'danger');
		});
	},

	refreshLog: function (log, state) {
		var self = this;

		return readLog(this.logOffset).then(function (res) {
			if (!res || res.error) return;

			if (res.data) {
				log.textContent += res.data;
				log.scrollTop = log.scrollHeight;
			}

			self.logOffset = res.offset || self.logOffset;

			if (res.running)
				state.textContent = _('running');
		}).catch(function () { });
	}
});