/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 HomeProxy Custom
 */

'use strict';
'require fs';
'require rpc';
'require ui';
'require view';

// 当前页面会话里的动态路径状态
let currentBackupPath = null;
let currentRestorePath = null;

const callBackupCreate = rpc.declare({
	object: 'luci.homeproxy_backup',
	method: 'backup_create',
	expect: { '': {} }
});

const callBackupGetUploadPath = rpc.declare({
	object: 'luci.homeproxy_backup',
	method: 'backup_get_upload_path',
	expect: { '': {} }
});

const callBackupCleanup = rpc.declare({
	object: 'luci.homeproxy_backup',
	method: 'backup_cleanup',
	params: ['path'],
	expect: { '': {} }
});

const callBackupValidate = rpc.declare({
	object: 'luci.homeproxy_backup',
	method: 'backup_validate',
	params: ['path'],
	expect: { '': {} }
});

const callBackupRestore = rpc.declare({
	object: 'luci.homeproxy_backup',
	method: 'backup_restore',
	params: ['path'],
	expect: { '': {} }
});

function downloadFile(path, filename) {
	return fs.read_direct(path, 'blob').then((blob) => {
		const url = window.URL.createObjectURL(blob);
		let a = document.createElement('a');

		a.style.display = 'none';
		a.href = url;
		a.download = filename;
		document.body.appendChild(a);
		a.click();
		window.setTimeout(() => {
			a.remove();
			window.URL.revokeObjectURL(url);
		}, 100);
	});
}

function renderFileList(files) {
	if (!files || !files.length)
		return E('em', _('No files.'));

	return E('ul', {}, files.map((file) => E('li', {}, file)));
}

function setButtonText(btn, text) {
	if (btn && btn.firstChild)
		btn.firstChild.data = text;
}

return view.extend({
	handleCreateBackup(ev) {
		const btn = ev.currentTarget || ev.target;

		setButtonText(btn, _('Generating backup file...'));

		return L.resolveDefault(callBackupCreate(), {}).then((res) => {
			if (!res.result)
				throw new Error(res.error || _('Failed to generate backup file.'));

			// 记录后端生成的备份路径，供浏览器下载
			currentBackupPath = res.download_path || res.path;
			if (!currentBackupPath)
				throw new Error(_('Backup file path was not returned.'));

			const filename = 'homeproxy-backup-%s.tar.gz'.format((new Date()).toISOString().replace(/[:.]/g, '-'));

			return downloadFile(currentBackupPath, filename).then(() => {
				ui.addNotification(null, E('p', _('Backup file has been generated and download has started.')), 'info');
				// 下载后清理后端临时备份文件，避免证书和私钥留在 /tmp
				return L.resolveDefault(callBackupCleanup(currentBackupPath), {});
			});
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
		}).finally(() => {
			setButtonText(btn, _('Generate backup file'));
		});
	},

	handleUploadRestore(ev) {
		const btn = ev.currentTarget || ev.target;

		setButtonText(btn, _('Uploading backup file...'));

		// 先向后端申请本次上传路径
		return L.resolveDefault(callBackupGetUploadPath(), {}).then((res) => {
			if (!res.upload_path)
				throw new Error(_('Failed to get upload path'));

			currentRestorePath = res.upload_path;

			return ui.uploadFile(currentRestorePath);
		}).then(() => {
			setButtonText(btn, _('Checking backup file...'));
			return L.resolveDefault(callBackupValidate(currentRestorePath), {});
		}).then((res) => {
			if (!res.valid)
				throw new Error(res.error || _('The uploaded backup file is invalid.'));

			ui.showModal(_('Restore HomeProxy backup?'), [
				E('p', _('The uploaded backup file contains the following HomeProxy source configuration. Restoring it will overwrite the current HomeProxy settings, custom direct/proxy lists, and uploaded certificates and private keys.')),
				renderFileList(res.files),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(this, () => {
							return L.resolveDefault(callBackupCleanup(currentRestorePath), {}).finally(ui.hideModal);
						})
					}, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(this, 'handleRestoreConfirm')
					}, [ _('Continue') ])
				])
			]);
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
			return L.resolveDefault(callBackupCleanup(currentRestorePath), {});
		}).finally(() => {
			setButtonText(btn, _('Upload backup file...'));
		});
	},

	handleRestoreConfirm() {
		ui.showModal(_('Restoring HomeProxy backup...'), [
			E('p', { 'class': 'spinning' }, _('Applying backup file and restarting HomeProxy.'))
		]);

		return L.resolveDefault(callBackupRestore(currentRestorePath), {}).then((res) => {
			if (!res.result)
				throw new Error(res.error || _('Restore failed.'));

			ui.showModal(_('Restore complete'), [
				E('p', _('HomeProxy configuration has been restored and the service has restarted.')),
				E('p', _('The rollback archive for the previous HomeProxy configuration has been saved to %s.').format(res.rollback || '/tmp/homeproxy-rollback.tar.gz')),
				renderFileList(res.files),
				E('div', { 'class': 'right' },
					E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('Close') ])
				)
			]);
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
			ui.hideModal();
		});
	},

	render() {
		const readonly = !L.hasViewPermission();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('HomeProxy configuration backup / restore')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Export and import HomeProxy source configuration to fully restore WebUI settings after reinstallation.')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Backup')),
				E('div', { 'class': 'cbi-section-descr' },
					_('Download a tar.gz backup containing /etc/config/homeproxy, custom direct/proxy lists, and uploaded certificates and private keys. The backup contains plaintext private keys; keep it safe and avoid transmitting or storing it through untrusted channels. Restore only verifies file integrity (SHA-256 manifest), not source authenticity.')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Download backup')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-action important',
							'disabled': readonly || null,
							'click': ui.createHandlerFn(this, 'handleCreateBackup')
						}, [ _('Generate backup file') ])
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Restore')),
				E('div', { 'class': 'cbi-section-descr' },
					_('Upload a HomeProxy backup file and overwrite the current HomeProxy source configuration. A rollback archive is saved automatically before restore.')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Restore backup')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-action important',
							'disabled': readonly || null,
							'click': ui.createHandlerFn(this, 'handleUploadRestore')
						}, [ _('Upload backup file...') ])
					])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
