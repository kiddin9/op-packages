// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import {
	failure,
	run_command,
	string_value,
	success
} from './core.uc';

const BACKUP_FILE = '/tmp/smartsafehub/config-backup.tar.gz';
const BACKUP_HELPER = '/usr/libexec/smartsafehub-backup';
const MAX_BACKUP_BYTES = 16777216;

function safe_upload_filename(value) {
	const filename = string_value(value, 'backup.tar.gz');
	return match(filename, /^[A-Za-z0-9._ +()-]{1,128}$/) != null
		? filename
		: 'backup.tar.gz';
}

export function validate_uploaded_backup(request) {
	const stat = fs.stat(BACKUP_FILE);
	if (stat == null || stat?.size <= 0) {
		return failure('SYSTEM_BACKUP_UPLOAD_MISSING', '업로드된 설정 백업 파일을 찾지 못했습니다.');
	}
	if (stat.size > MAX_BACKUP_BYTES) {
		fs.unlink(BACKUP_FILE);
		return failure('SYSTEM_BACKUP_TOO_LARGE', '설정 백업 파일은 16MB 이하여야 합니다.');
	}

	if (!run_command([ BACKUP_HELPER, 'validate' ], 20000)) {
		fs.unlink(BACKUP_FILE);
		return failure(
			'SYSTEM_BACKUP_INVALID',
			'올바른 OpenWrt 설정 백업 파일이 아닙니다. 같은 장치에서 생성한 백업인지 확인해 주세요.'
		);
	}

	return success({
		validated: true,
		filename: safe_upload_filename(request.args.filename),
		sizeBytes: stat.size,
	});
};

export function restore_uploaded_backup(request) {
	if (request.args.confirm != 'restore') {
		return failure('SYSTEM_BACKUP_CONFIRM_REQUIRED', '설정 복원을 다시 확인해 주세요.');
	}

	let status;
	try {
		status = system([ BACKUP_HELPER, 'restore' ], 30000);
	}
	catch (e) {
		status = -1;
	}

	if (status == 75) {
		return failure(
			'SYSTEM_BACKUP_BUSY',
			'업데이트 또는 펌웨어 작업이 진행 중입니다. 작업이 끝난 뒤 다시 복원해 주세요.'
		);
	}
	if (status != 0) {
		return failure(
			'SYSTEM_BACKUP_RESTORE_FAILED',
			'설정 백업을 복원하지 못했습니다. 백업 파일과 장치 호환성을 확인해 주세요.'
		);
	}

	return success({
		accepted: true,
		rebooting: true,
	});
};

export function discard_uploaded_backup() {
	if (!run_command([ BACKUP_HELPER, 'discard' ], 5000)) {
		return failure('SYSTEM_BACKUP_DISCARD_FAILED', '업로드한 설정 백업 파일을 삭제하지 못했습니다.');
	}

	return success({ discarded: true });
};
