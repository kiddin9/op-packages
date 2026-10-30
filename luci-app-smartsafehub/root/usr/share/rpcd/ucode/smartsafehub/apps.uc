// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import { failure, success } from './core.uc';
import { ensure_job, job_state, request_job } from './rpc-jobs.uc';

const CATALOG_FILE = '/tmp/smartsafehub/apps-catalog.json';

function text(value, max_length) {
	return type(value) == 'string' && length(value) <= max_length ? value : '';
}

// Only open LuCI pages served by this router. Reject query strings, fragments,
// percent escapes, scheme-relative URLs and path traversal from catalog data.
function luci_web_ui_path(value) {
	if (!text(value, 160) ||
		match(value, /^\/cgi-bin\/luci\/admin\/[a-z0-9_-]+(\/[a-z0-9_-]+)*$/) == null)
		return '';
	return value;
}

// This endpoint is *read-only*. The catalog never supplies executable
// commands, repository URLs or permissions to a package installer. The
// separate privileged installer must revalidate every approval in the future.
export function read_apps_catalog(request) {
	// Never perform an HTTP request on rpcd's event loop. Serve a last-known
	// display-only snapshot while the detached worker updates it atomically.
	if (request?.args?.refresh == true) request_job('catalog');
	else ensure_job('catalog');
	const operation = job_state('catalog');
	const raw = fs.readfile(CATALOG_FILE);
	const pending = operation.phase == 'starting' || operation.phase == 'running';
	if (type(raw) != 'string' || length(raw) < 2) {
		return success({ schema: 1, deviceCode: '', firmwareBuildId: '', channel: '', apps: [],
			ready: false, refreshing: pending, refreshFailed: operation.phase == 'failed' });
	}
	if (length(raw) > 131072) {
		return failure('APPS_CATALOG_INVALID', '앱 목록 데이터가 올바르지 않습니다.');
	}

	let data;
	try {
		data = json(raw);
	}
	catch (e) {
		return failure('APPS_CATALOG_INVALID', '앱 목록을 읽지 못했습니다.');
	}
	if (type(data) != 'object' || data?.schema != 1 || type(data?.apps) != 'array' ||
		length(data.apps) > 100 || !text(data?.device_code, 80) ||
		!text(data?.firmware_build_id, 80)) {
		return failure('APPS_CATALOG_INVALID', '앱 목록 형식이 올바르지 않습니다.');
	}

	// A firmware change invalidates the old catalog before any cards are shown.
	// The ROM metadata takes precedence over writable overlay metadata.
	let metadataRaw = fs.readfile('/rom/usr/share/smartsafehub/firmware.json');
	if (type(metadataRaw) != 'string' || !length(metadataRaw))
		metadataRaw = fs.readfile('/usr/share/smartsafehub/firmware.json');
	if (type(metadataRaw) == 'string' && length(metadataRaw)) {
		let metadata = null;
		try { metadata = json(metadataRaw); } catch (e) { /* reject stale catalog below */ }
		if (metadata == null || metadata?.device_code != data.device_code ||
			metadata?.build_id != data.firmware_build_id ||
			(metadata?.channel ?? 'stable') != (data?.channel ?? 'stable'))
			return success({ schema: 1, deviceCode: '', firmwareBuildId: '', channel: '', apps: [],
				ready: false, refreshing: pending, refreshFailed: operation.phase == 'failed' });
	}
	const apps = [];
	for (let item in data.apps) {
		if (type(item) != 'object' || item.runtime != 'router' || item.installer != 'apk') {
			continue;
		}
		const id = text(item?.id, 80);
		const name = text(item?.name, 120);
		if (!length(id) || !length(name) || match(id, /^[a-z0-9][a-z0-9-]{0,79}$/) == null) {
			continue;
		}
		// Backward-compatible route for the already approved nlbwmon catalog.
		// The page is only launchable if its UI package is actually installed.
		let path = '';
		if (id == 'wake-on-lan') {
			if (item?.web_ui?.type == 'luci' &&
				item?.web_ui?.path == '/cgi-bin/luci/admin/services/wol' &&
				item?.web_ui?.package == 'luci-app-wol')
				path = '/cgi-bin/luci/admin/services/wol';
		}
		else if (item?.web_ui?.type == 'luci')
			path = luci_web_ui_path(item.web_ui.path);
		else if (id == 'retro-arcade' && item?.web_ui?.type == 'static' &&
			item?.web_ui?.path == '/retro-arcade/' &&
			item?.web_ui?.package == 'smartsafehub-app-retro-arcade')
			path = '/retro-arcade/';
		else if (id == 'network-usage-monitor')
			path = '/cgi-bin/luci/admin/services/nlbw/display';
		// Only UI copy crosses into the unprivileged browser. All package hashes,
		// permissions and install descriptors remain server-side until an installer
		// with independent verification is implemented.
		push(apps, {
			id: id,
			name: name,
			summary: text(item?.summary, 320),
			description: text(item?.description, 2000),
			category: text(item?.category, 64),
			version: text(item?.version, 64),
			webUi: length(path) ? { type: id == 'retro-arcade' && path == '/retro-arcade/' ? 'static' : 'luci', path: path } : null,
		});
	}
	return success({
		schema: 1,
		deviceCode: data.device_code,
		firmwareBuildId: data.firmware_build_id,
		channel: text(data?.channel, 16),
		apps: apps,
		ready: true,
		refreshing: pending,
		refreshFailed: operation.phase == 'failed',
	});
};
