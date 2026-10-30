// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

const MAX_BYTES = 9007199254740991; // JavaScript Number.MAX_SAFE_INTEGER

function valid_counter(value) {
	return (type(value) == 'int' || type(value) == 'double') &&
		value >= 0 && value <= MAX_BYTES;
}

function storage_bytes(total, available, mount) {
	if (!valid_counter(total) || !valid_counter(available) ||
		total <= 0 || available > total)
		return null;
	return { mount: mount, totalBytes: total, availableBytes: available };
}

// procd system.info.root.total/avail are KiB, NOT bytes. In OpenWrt
// with overlayfs, / is the writable union and its free blocks come
// from the underlying writable overlay filesystem.
export function from_system_root(root) {
	if (!root || !valid_counter(root.total) || !valid_counter(root.avail) ||
		root.total > MAX_BYTES / 1024 || root.avail > root.total)
		return null;
	return storage_bytes(root.total * 1024, root.avail * 1024, '/');
};

// Filesystem fallback for firmware without procd root statistics.
// The ucode type() builtin calls integers "int", not "integer".
export function from_statvfs(stats, mount) {
	if (!stats || (mount != '/overlay' && mount != '/'))
		return null;
	const frsize = valid_counter(stats.frsize) && stats.frsize > 0
		? stats.frsize : stats.bsize;
	if (!valid_counter(frsize) || frsize <= 0 ||
		!valid_counter(stats.blocks) || !valid_counter(stats.bavail) ||
		stats.blocks <= 0 || stats.bavail > stats.blocks ||
		stats.blocks > MAX_BYTES / frsize)
		return null;
	return storage_bytes(stats.blocks * frsize, stats.bavail * frsize, mount);
};
