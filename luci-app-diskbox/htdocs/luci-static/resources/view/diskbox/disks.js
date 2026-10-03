'use strict';
// Copyright (C) 2026 permails <https://github.com/permails/luci-app-diskbox>
// Licensed under the GNU General Public License v3.0
//
// Modern Storage Manager (4-tab single page): 物理磁盘 / 分区管理 / RAID / Btrfs.
// Ported to the LuCI AMD view architecture from the DESIGN_SPEC demo. Every
// action is wired to the real `luci.diskbox` rpcd backend; no mock data. All
// protection rules are preserved: is_boot partitions are locked, / , /rom and
// /overlay* are brick-level (never unmountable), mount targets require
// >= 64 MiB, and the backend's destructive `mk_partition_table` (parted
// mklabel) is only offered on disks that have no partitions yet.
'require view';
'require rpc';
'require ui';
'require dom';

var callListDevices = rpc.declare({
	object: 'luci.diskbox',
	method: 'list_devices',
	expect: { devices: {} }
});

var callGetDiskInfo = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_disk_info',
	params: ['device']
});

var callGetSmartAttr = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_smart_attr',
	params: ['device']
});

var callGetFormatCmd = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_format_cmd',
	expect: { formats: {} }
});

var callFormatPartition = rpc.declare({
	object: 'luci.diskbox',
	method: 'format_partition',
	params: ['partition', 'filesystem', 'force']
});

var callMkPartitionTable = rpc.declare({
	object: 'luci.diskbox',
	method: 'mk_partition_table',
	params: ['device', 'table']
});

var callCreatePartition = rpc.declare({
	object: 'luci.diskbox',
	method: 'create_partition',
	params: ['device', 'start_sec', 'end_sec', 'type']
});

var callRemovePartition = rpc.declare({
	object: 'luci.diskbox',
	method: 'remove_partition',
	params: ['device', 'number']
});

var callEjectDevice = rpc.declare({
	object: 'luci.diskbox',
	method: 'eject_device',
	params: ['device']
});

var callRescanDisks = rpc.declare({
	object: 'luci.diskbox',
	method: 'rescan_disks'
});

var callGetMountPoints = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_mount_points',
	expect: { mount_points: [] }
});

var callMount = rpc.declare({
	object: 'luci.diskbox',
	method: 'mount',
	params: ['device', 'point', 'fs', 'options']
});

var callUmount = rpc.declare({
	object: 'luci.diskbox',
	method: 'umount',
	params: ['point']
});

var callListRaidDevices = rpc.declare({
	object: 'luci.diskbox',
	method: 'list_raid_devices',
	expect: { raid_devices: {} }
});

var callCreateRaid = rpc.declare({
	object: 'luci.diskbox',
	method: 'create_raid',
	params: ['name', 'level', 'members']
});

var callListBtrfsDevices = rpc.declare({
	object: 'luci.diskbox',
	method: 'list_btrfs_devices',
	expect: { btrfs_devices: {} }
});

var callGetBtrfsInfo = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_btrfs_info',
	params: ['uuid']
});

var callGetBtrfsSubvolumes = rpc.declare({
	object: 'luci.diskbox',
	method: 'get_btrfs_subvolumes',
	params: ['uuid'],
	expect: { subvolumes: [] }
});

var callCreateBtrfs = rpc.declare({
	object: 'luci.diskbox',
	method: 'create_btrfs',
	params: ['label', 'level', 'members']
});

var callBtrfsSetLabel = rpc.declare({
	object: 'luci.diskbox',
	method: 'btrfs_set_label',
	params: ['uuid', 'label']
});

var callBtrfsSubvolCreate = rpc.declare({
	object: 'luci.diskbox',
	method: 'btrfs_subvol_create',
	params: ['uuid', 'path']
});

var callBtrfsSubvolDelete = rpc.declare({
	object: 'luci.diskbox',
	method: 'btrfs_subvol_delete',
	params: ['uuid', 'path']
});

var callBtrfsSubvolSetDefault = rpc.declare({
	object: 'luci.diskbox',
	method: 'btrfs_subvol_set_default',
	params: ['uuid', 'path']
});

var callBtrfsSnapshotCreate = rpc.declare({
	object: 'luci.diskbox',
	method: 'btrfs_snapshot_create',
	params: ['uuid', 'source', 'dest', 'readonly']
});

// Minimum size for a meaningful mount target (bytes). System/boot partitions
// (is_boot) and tiny firmware slivers (< 64 MiB) are excluded from the mount
// picker so they can never be chosen as a mount point.
var MIN_MOUNT_BYTES = 64 * 1024 * 1024;

// Cache-busting token for the component stylesheet (bump on each CSS change).
var DISKBOX_CSS_V = '20260919_a';

// Active top tab (module-level so it survives re-renders within a page load).
// Persisted in the URL hash (#partitions) so a location.reload() fired after a
// mount / delete / eject / rescan returns the user to the SAME tab instead of
// bouncing back to the default Physical Disks tab and hiding the result.
var MAIN_TAB_KEYS = ['disks', 'partitions', 'raid', 'btrfs'];
var activeMainTab = (function() {
	try {
		var h = (typeof location !== 'undefined' && location.hash)
			? location.hash.replace(/^#/, '') : '';
		if (MAIN_TAB_KEYS.indexOf(h) !== -1) return h;
	} catch (e) { /* ignore */ }
	return 'disks';
})();
// Reflect the active tab in the URL hash. replaceState (not location.hash=)
// keeps the back button clean - no new history entry per tab click.
function syncTabHash() {
	try {
		if (typeof history !== 'undefined' && history.replaceState)
			history.replaceState(null, '', '#' + activeMainTab);
	} catch (e) { /* some embedded contexts block replaceState */ }
}
// Set by render(); lets buttons deep in a tab switch to another tab + redraw.
var currentDraw = null;
// Per-disk get_disk_info cache (this page's JS context). Re-selecting the
// Partition Management tab then renders instantly instead of re-running the
// slow smartctl-based backend query. Every mutating action ends in
// location.reload(), which rebuilds the context and resets this cache.
var _diskInfoCache = {};

// Inject the component stylesheet once. There is no LuCI template for this
// view, so we add a <link> to document.head from the render step.
function ensureStyles() {
	if (typeof document === 'undefined' || document.getElementById('diskbox-static-css')) return;
	var link = document.createElement('link');
	link.id = 'diskbox-static-css';
	link.rel = 'stylesheet';
	link.href = '/luci-static/resources/view/diskbox/diskbox.css?v=' + DISKBOX_CSS_V;
	(document.head || document.getElementsByTagName('head')[0]).appendChild(link);
}

// Switch to another top tab, redraw, and (optionally) scroll to a per-disk
// section by id `disk-group-<name>`.
function gotoTab(key, devName) {
	activeMainTab = key;
	syncTabHash();
	if (typeof currentDraw === 'function') currentDraw();
	if (devName) {
		setTimeout(function() {
			var el = document.getElementById('disk-group-' + devName);
			if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
		}, 80);
	}
}

function translatePowerStatus(status) {
	if (!status || status === '-') return '-';
	var map = {
		'ACTIVE': _('Active'),
		'STANDBY': _('Standby'),
		'SLEEP': _('Sleep')
	};
	return map[status] || status;
}

function translateHealth(health) {
	if (!health || health === '-') return '-';
	var map = {
		'Normal': _('Normal'),
		'PASSED': _('Passed'),
		'Warning': _('Warning'),
		'Urgent': _('Urgent'),
		'FAILED': _('Failed')
	};
	return map[health] || health;
}

function translateFs(fs, type) {
	if (type === 'extended' || fs === 'extended') return _('Extended Partition');
	if (fs === 'Free Space' || type === 'free') return _('Free Space');
	if (fs === 'raw') return _('Unformatted');
	if (!fs || fs === '-') return '-';
	return fs.toUpperCase();
}

// Human-readable size from a byte count (1024-based), e.g. 113.17 GB.
function formatBytes(bytes) {
	if (!bytes || bytes <= 0) return '0 B';
	var units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
	var b = bytes, i = 0;
	while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
	return (i === 0 ? b.toFixed(0) : b.toFixed(2)) + ' ' + units[i];
}

// Five-state semantic classification purely from backend facts (no size
// guessing): is_boot -> protected; mounted -> in use; unmounted + fstype ->
// data present; unmounted + no fs -> empty/safe. Unallocated is computed
// separately by the bar/chip builders.
function partState(p) {
	var fstype = (p.fstype || p.fs) || '';
	var mounted = p.mount_point && p.mount_point !== '-';
	if (p.is_boot) return { cls: 'part-state-boot', tag: _('Boot / Firmware (protected)') };
	if (mounted) return { cls: 'part-state-inuse', tag: _('Data (in use)') };
	var hasFs = fstype && fstype !== 'raw' && fstype !== '-' && fstype !== 'unknown' &&
		fstype !== 'Free Space' && fstype.toLowerCase() !== 'free space';
	if (hasFs) return { cls: 'part-state-unmounted', tag: _('Data (unmounted)') };
	return { cls: 'part-state-raw', tag: _('Empty (no filesystem)') };
}

// A label+checkbox "member" chip for the RAID / Btrfs creation forms.
function memberChip(value, label) {
	var cb = E('input', { 'type': 'checkbox', 'value': value });
	return E('label', { 'class': 'checkbox-chip' }, [ cb, E('span', {}, label) ]);
}

// Whether a partition / whole-disk entry is already mounted. Mounted devices
// must never be RAID/Btrfs members - creating the array/filesystem would
// ERASE them.
function isMountedPart(p) {
	return p.inuse === true || (p.mount_point && p.mount_point !== '-');
}

// Build the group of selectable member chips from the device list. Eligible
// members = free, unmounted, non-boot partitions (or a whole disk with no
// partitions). System disks, is_boot partitions and anything already mounted
// are excluded - they are never safe RAID/Btrfs members. When no member
// qualifies, emptyMsg (if given) is shown in place of the chips so the field
// reads as "nothing to pick" rather than a missing control.
function buildMemberChips(devices, emptyMsg) {
	var group = E('div', { 'class': 'checkbox-chip-group' });
	Object.keys(devices).forEach(function(k) {
		var dev = devices[k];
		if (!dev) return;
		var parts = dev.partitions || [];
		if (parts.length === 0) {
			if (!dev.is_system && !isMountedPart(dev)) {
				group.appendChild(memberChip(dev.path, dev.path + ' ' + (dev.size_formated || '')));
			}
		} else {
			parts.forEach(function(p) {
				// eMMC hardware boot partitions (mmcblkXboot0/1) hold firmware /
				// bootloader data. Even when the backend's is_boot flag misses
				// them, never offer them as RAID/Btrfs members.
				var isBootDev = (p.name || '').indexOf('boot') !== -1;
				if (!p.is_boot && !isMountedPart(p) && !isBootDev) {
					group.appendChild(memberChip(p.path, p.path + ' ' + (p.size_formated || '')));
				}
			});
		}
	});
	if (!group.firstChild && emptyMsg) {
		group.appendChild(E('div', { 'class': 'chip-empty-box' }, emptyMsg));
	}
	return group;
}

// Find a mount point for a given /dev/... device in the mount-point list.
function mountPointFor(mountPoints, devPath) {
	if (!mountPoints || !devPath) return null;
	for (var i = 0; i < mountPoints.length; i++) {
		if (mountPoints[i] && mountPoints[i].device === devPath) return mountPoints[i].mount_point;
	}
	return null;
}

// Find the mount point of any member device of a Btrfs pool (a pool is mounted
// through one of its member devices).
function btrfsMountPoint(mountPoints, membersStr) {
	if (!membersStr) return null;
	var members = membersStr.split(',').map(function(s) { return s.trim(); }).filter(Boolean);
	for (var i = 0; i < members.length; i++) {
		var mp = mountPointFor(mountPoints, members[i]);
		if (mp) return mp;
	}
	return null;
}

return view.extend({
	load: function() {
		return Promise.all([
			callListDevices(),
			callGetMountPoints(),
			callListRaidDevices(),
			callListBtrfsDevices(),
			callGetFormatCmd()
		]);
	},

	// On-theme confirmation dialog (replaces native confirm()). Cancel is
	// neutral, the destructive confirm is negative - consistent with the
	// rest of the app's modals. onDismiss runs on Cancel (if given).
	showConfirm: function(title, message, onConfirm, onDismiss) {
		ui.showModal(title, [
			E('p', { 'style': 'white-space:pre-line; margin:0 0 1.25rem 0;' }, message),
			E('div', { 'class': 'right', 'style': 'margin-top:1rem; display:flex; justify-content:flex-end; gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'click': function(ev) { ev.preventDefault(); ui.hideModal(); if (typeof onDismiss === 'function') onDismiss(); }
				}, _('Cancel')),
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': function(ev) { ev.preventDefault(); ui.hideModal(); if (typeof onConfirm === 'function') onConfirm(); }
				}, _('Confirm'))
			])
		]);
	},

	showRaidInfoModal: function(r) {
		var members = (r.members_str || '').split(',').map(function(s) { return s.trim(); }).filter(Boolean);
		var rows = [
			[ _('RAID Level'), r.level || '-' ],
			[ _('Status'), ((r.active || '') + (r.status ? ' / ' + r.status : '')) || '-' ],
			[ _('Size'), r.size_formated || '-' ],
			[ _('Members'), members.join(', ') || '-' ]
		];
		var t = E('table', { 'class': 'table cbi-section-table' }, [
			rows.map(function(row) {
				return E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'font-weight:600; width:40%;' }, row[0]),
					E('td', { 'class': 'td' }, row[1])
				]);
			})
		]);
		ui.showModal(_('RAID Details') + ' - ' + (r.path || r.name), [ t ]);
	},

	showSmartModal: function(dev) {
		ui.showModal(_('S.M.A.R.T Attributes') + ' - /dev/' + dev, [
			E('p', { 'class': 'spinning' }, _('Collecting data...'))
		]);

		callGetSmartAttr(dev).then(function(res) {
			var attrs = (res && res.attributes) ? res.attributes : (Array.isArray(res) ? res : []);
			if (attrs.length === 0) {
				ui.showModal(_('S.M.A.R.T Attributes') + ' - /dev/' + dev, [
					E('p', { 'style': 'font-style:italic; padding:1rem;' }, _('No SMART attributes to display.'))
				]);
				return;
			}

			var modalContent;
			if (attrs[0].key !== undefined) {
				var table = E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('Key')),
						E('th', { 'class': 'th' }, _('Value'))
					])
				]);
				attrs.forEach(function(item) {
					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, item.key),
						E('td', { 'class': 'td' }, item.value)
					]));
				});
				modalContent = table;
			} else {
				var table = E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('ID')),
						E('th', { 'class': 'th' }, _('Attribute')),
						E('th', { 'class': 'th' }, _('Flag')),
						E('th', { 'class': 'th' }, _('Value')),
						E('th', { 'class': 'th' }, _('Worst')),
						E('th', { 'class': 'th' }, _('Thresh')),
						E('th', { 'class': 'th' }, _('Type')),
						E('th', { 'class': 'th' }, _('Updated')),
						E('th', { 'class': 'th' }, _('Raw'))
					])
				]);

				attrs.forEach(function(item) {
					var isCritical = ((item.id === '05' || item.id === 'C5') && item.raw !== '0');
					var rowStyle = isCritical ? 'background-color:rgba(var(--error-color-high-rgb), 0.25) !important;' : '';

					table.appendChild(E('tr', { 'class': 'tr', 'style': rowStyle }, [
						E('td', { 'class': 'td' }, E('code', {}, item.id)),
						E('td', { 'class': 'td' }, item.attrbute || item.attribute),
						E('td', { 'class': 'td' }, item.flag || '-'),
						E('td', { 'class': 'td' }, item.value || '-'),
						E('td', { 'class': 'td' }, item.worst || '-'),
						E('td', { 'class': 'td' }, item.thresh || '-'),
						E('td', { 'class': 'td' }, item.type || '-'),
						E('td', { 'class': 'td' }, item.updated || '-'),
						E('td', { 'class': 'td' }, E('strong', {}, item.raw || '-'))
					]));
				});
				modalContent = table;
			}

			ui.showModal(_('S.M.A.R.T Attributes') + ' - /dev/' + dev, [
				E('div', { 'style': 'max-height:70vh; overflow-y:auto;' }, [ modalContent ]),
				E('div', { 'class': 'right', 'style': 'margin-top:1rem;' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-neutral',
						'click': ui.hideModal
					}, _('Close'))
				])
			]);
		});
	},

	showFormatModal: function(partName, formatCmds, currentFs, onSuccess) {
		var selFs = E('select', { 'class': 'cbi-input-select', 'style': 'width:100%;' });
		Object.keys(formatCmds).forEach(function(fs) {
			var opt = E('option', { 'value': fs }, fs.toUpperCase());
			if (fs === currentFs) opt.selected = true;
			selFs.appendChild(opt);
		});

		var statusP = E('p', { 'style': 'color:var(--error-color-high); font-weight:bold; margin-top:8px;' });

		ui.showModal(_('Format partition: /dev/%s').format(partName), [
			E('p', {}, _('Formatting partition will ERASE all data stored on it.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('File System')),
				E('div', { 'class': 'cbi-value-field' }, selFs)
			]),
			statusP,
			E('div', { 'class': 'right', 'style': 'margin-top:1.5rem; display:flex; justify-content:flex-end; gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-reset',
					'click': ui.hideModal
				}, _('Cancel')),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': function(ev) {
						ev.preventDefault();
						var targetFs = selFs.value;
						this.disabled = true;
						callFormatPartition(partName, targetFs).then(function(res) {
							if (res && res.code === 3) {
								// Soft block: partition holds data - ask for confirmation then retry with force
								this.disabled = false;
								dom.content(statusP, [ E('p', { 'style': 'color:var(--warn-color-high); font-weight:bold;' }, (res.error || _('This partition contains data.')) + ' ') ]);
								var confirmBtn = E('button', {
									'class': 'btn cbi-button cbi-button-apply',
									'click': function() {
										this.disabled = true;
										dom.content(statusP, [ E('span', { 'class': 'spinning' }, _('Formatting...')) ]);
										callFormatPartition(partName, targetFs, 1).then(function(r2) {
											if (r2 && r2.code === 0) {
												ui.addNotification(null, E('p', {}, _('Partition formatted successfully!')));
												ui.hideModal();
												if (typeof onSuccess === 'function') {
													onSuccess();
												} else {
													location.reload();
												}
											} else {
												this.disabled = false;
												dom.content(statusP, r2 ? (r2.error || _('Format failed.')) : _('Format failed.'));
											}
										}.bind(this));
									}
								}, _('Force Format'));
								var cancelBtn = E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.hideModal }, _('Cancel'));
								statusP.appendChild(E('div', { 'style': 'display:flex; gap:8px; margin-top:8px;' }, [confirmBtn, cancelBtn]));
							} else if (res && res.code === 0) {
								ui.addNotification(null, E('p', {}, _('Partition formatted successfully!')));
								ui.hideModal();
								if (typeof onSuccess === 'function') onSuccess();
								else location.reload();
							} else {
								this.disabled = false;
								dom.content(statusP, res ? (res.error || _('Format failed.')) : _('Format failed.'));
							}
						}.bind(this));
					}
				}, _('Format'))
			])
		]);
	},

	// Mount / re-mount dialog. Candidates are non-boot partitions >= 64 MiB (or
	// a whole non-system disk if it has no partitions). Prefills the selected
	// partition's current point + options when editing an existing mount.
	showMountModal: function(devName, dev, info, selectedPart, data) {
		var mountPoints = data[1] || [];
		var parts = (info && info.partitions) || (dev && dev.partitions) || [];
		var candidates = [];
		parts.forEach(function(p) {
			if (p.is_boot) return;
			if ((p.size || 0) < MIN_MOUNT_BYTES) return;
			if (p.number && p.number > 0) candidates.push({ path: p.path, label: p.path + ' ' + (p.size_formated || '') });
		});
		if (candidates.length === 0 && dev && !dev.is_system) {
			candidates.push({ path: dev.path, label: dev.path + ' ' + (dev.size_formated || '') });
		}

		var curPoint = (selectedPart && selectedPart.mount_point && selectedPart.mount_point !== '-')
			? selectedPart.mount_point : '/mnt/';
		if (selectedPart && curPoint === '/mnt/' && selectedPart.name) curPoint = '/mnt/' + selectedPart.name;
		var curOpts = 'rw,noatime';
		mountPoints.forEach(function(mp) {
			if (selectedPart && mp.device === selectedPart.path && mp.mount_options) curOpts = mp.mount_options;
		});

		var devSel = E('select', { 'class': 'cbi-input-select', 'style': 'width:100%;' });
		if (candidates.length === 0) {
			devSel.appendChild(E('option', { 'value': '' }, _('-- No mountable partitions --')));
		}
		candidates.forEach(function(c) {
			var o = E('option', { 'value': c.path }, c.label);
			if (selectedPart && c.path === selectedPart.path) o.selected = true;
			devSel.appendChild(o);
		});

		var fsSel = E('select', { 'class': 'cbi-input-select', 'style': 'width:100%;' }, [
			E('option', { 'value': 'auto', 'selected': 'selected' }, 'auto'),
			E('option', { 'value': 'ext4' }, 'ext4'),
			E('option', { 'value': 'ext3' }, 'ext3'),
			E('option', { 'value': 'ext2' }, 'ext2'),
			E('option', { 'value': 'vfat' }, 'vfat'),
			E('option', { 'value': 'exfat' }, 'exfat'),
			E('option', { 'value': 'ntfs' }, 'ntfs'),
			E('option', { 'value': 'btrfs' }, 'btrfs')
		]);
		var pointIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': curPoint });
		var optsIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': curOpts });

		ui.showModal(_('Mount a device'), [
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Device')), E('div', { 'class': 'cbi-value-field' }, devSel) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('File System')), E('div', { 'class': 'cbi-value-field' }, fsSel) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Mount Point')), E('div', { 'class': 'cbi-value-field' }, pointIn) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Mount Options')), E('div', { 'class': 'cbi-value-field' }, optsIn) ]),
			E('div', { 'class': 'right', 'style': 'margin-top:1.5rem; display:flex; justify-content:flex-end; gap:8px;' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.hideModal }, _('Cancel')),
				E('button', {
					'class': 'btn cbi-button cbi-button-add',
					'click': function(ev) {
						ev.preventDefault();
						var d = devSel.value, p = pointIn.value;
						if (!d || !p) {
							ui.addNotification(null, E('p', {}, _('Please select a device and input mount point!')));
							return;
						}
						this.disabled = true;
						ui.showModal(_('Mounting'), [ E('p', { 'class': 'spinning' }, _('Mounting device...')) ]);
						callMount(d, p, fsSel.value, optsIn.value).then(function(res) {
							if (res && res.code !== 0) {
								ui.addNotification(null, E('p', {}, res.error || _('Failed to mount.')));
							}
							location.reload();
						});
					}
				}, _('Mount'))
			])
		]);
	},

	// Create-partition dialog. Start sector is auto-detected (rounded UP to the
	// next 2048-sector / 1 MiB boundary after the last partition) and a size +
	// unit are converted to an end sector. The helper shows the max free space.
	showCreatePartitionModal: function(devName, info) {
		var secSize = (info && info.logic_sec) || 512;
		var totalSectors = (info && info.size) ? Math.floor(info.size / secSize) : 0;
		var maxUsable = totalSectors > 34 ? totalSectors - 34 : totalSectors;
		var parts = (info && info.partitions) || [];
		var GB = 1073741824, MB = 1048576;

		var maxEnd = -1;
		parts.forEach(function(p) { if ((p.sec_end | 0) > maxEnd) maxEnd = p.sec_end | 0; });
		var autoStart = maxEnd >= 0 ? Math.ceil((maxEnd + 1) / 2048) * 2048 : 2048;
		var remainBytes = Math.max(0, maxUsable - autoStart + 1) * secSize;
		var remainFmt = formatBytes(remainBytes);

		var defaultUnit = 'GB', defaultVal = 1;
		if (remainBytes >= GB) { defaultUnit = 'GB'; defaultVal = Math.min(50, Math.max(1, Math.floor(remainBytes / GB))); }
		else if (remainBytes >= MB) { defaultUnit = 'MB'; defaultVal = Math.max(1, Math.floor(remainBytes / MB)); }

		var startIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': autoStart, 'style': 'width:140px;' });
		var sizeIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': defaultVal, 'style': 'width:140px;' });
		var unitSel = E('select', { 'class': 'cbi-input-select', 'style': 'width:100px;' }, [
			E('option', { 'value': 'TB' }, 'TB'),
			E('option', { 'value': 'GB' }, 'GB'),
			E('option', { 'value': 'MB' }, 'MB'),
			E('option', { 'value': 'sectors' }, _('sectors'))
		]);
		unitSel.value = defaultUnit;
		var helper = E('div', { 'class': 'cbi-value-description' }, _('Maximum available: %s').format(remainFmt));

		ui.showModal(_('Create Partition'), [
			E('p', { 'style': 'margin:0 0 1rem 0;' }, _('New partition on /dev/%s. Start sector auto-detected and aligned to 1 MiB.').format(devName)),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Start Sector')),
				E('div', { 'class': 'cbi-value-field' }, startIn)
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Partition Size')),
				E('div', { 'class': 'cbi-value-field' }, [ sizeIn, unitSel, helper ])
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:1.5rem; display:flex; justify-content:flex-end; gap:8px;' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': ui.hideModal }, _('Cancel')),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': function(ev) {
						ev.preventDefault();
						var start = parseInt(startIn.value, 10);
						var sizeVal = parseFloat(sizeIn.value);
						var unit = unitSel.value;
						if (isNaN(start) || start <= 0) {
							ui.addNotification(null, E('p', {}, _('Invalid Start sector!')));
							return;
						}
						if (isNaN(sizeVal) || sizeVal <= 0) {
							ui.addNotification(null, E('p', {}, _('Invalid Partition size!')));
							return;
						}
						var unitBytes = { 'TB': 1099511627776, 'GB': GB, 'MB': MB, 'sectors': secSize }[unit];
						var sectors = Math.max(1, Math.round((sizeVal * unitBytes) / secSize));
						var end = start + sectors - 1;
						if (end > maxUsable) {
							ui.addNotification(null, E('p', {}, _('Size exceeds the available free space.')));
							return;
						}
						this.disabled = true;
						ui.showModal(_('Creating Partition'), [ E('p', { 'class': 'spinning' }, _('Creating new partition...')) ]);
						callCreatePartition(devName, start, end, 'primary').then(function(res) {
							if (res && res.code !== 0) {
								ui.addNotification(null, E('p', {}, res.error || _('Failed to create partition.')));
							}
							location.reload();
						});
					}
				}, _('Create'))
			])
		]);
	},

	// --- shared builders ----------------------------------------------------

	// Colored, underlined SMART/health link (open the attributes modal on click).
	buildSmartLink: function(devName, health) {
		var raw = (health || '').trim().replace(/[-\s]+$/, '').trim();
		var cls = 'passed';
		if (raw && (raw.indexOf('Warning') !== -1 || raw.indexOf('Urgent') !== -1 || raw.indexOf('FAILED') !== -1)) cls = 'failed';
		else if (raw && raw.indexOf('Normal') !== -1) cls = 'passed';
		return E('a', {
			'href': '#',
			'class': 'smart-status-link ' + cls,
			'title': _('Click to view SMART & Health details'),
			'click': function(ev) { ev.preventDefault(); this.showSmartModal(devName); }.bind(this)
		}, translateHealth(raw) || '-');
	},

	// Bus/transport badge inferred from the device path.
	busBadge: function(dev) {
		var p = (dev.path || '').toLowerCase();
		if (p.indexOf('nvme') !== -1) return 'NVMe';
		if (p.indexOf('mmcblk') !== -1) return 'eMMC';
		if (p.indexOf('md') !== -1) return 'RAID';
		return 'SATA';
	},

	// The 5-state legend strip.
	buildLegend: function() {
		var items = [
			['part-state-boot', _('Boot / Firmware (protected)')],
			['part-state-inuse', _('Data (in use)')],
			['part-state-unmounted', _('Data (unmounted)')],
			['part-state-raw', _('Empty (no filesystem)')],
			['part-state-unalloc', _('Unallocated Space')]
		];
		return E('div', { 'class': 'disk-partition-legend' }, items.map(function(it) {
			return E('span', { 'class': 'legend-item' }, [
				E('span', { 'class': 'legend-color-dot ' + it[0] }),
				it[1]
			]);
		}));
	},

	// The 14px pill partition bar. flex-grow still reflects relative size so a
	// big data partition dwarfs the boot slivers, but each segment carries a CSS
	// min-width so the partition name always fits — proportions stay
	// approximate, legibility stays hard. Full detail via the hover tooltip.
	buildPillBar: function(dev, parts) {
		var totalSize = dev.size || 1;
		var used = 0;
		var segs = [];
		function makeSeg(cls, pct, tipText, nameLabel) {
			var grow = Math.max(1, Math.round(pct));
			return E('div', {
				'class': 'part-segment ' + cls,
				'style': 'flex:' + grow + ' 1 0;'
			}, [
				nameLabel,
				E('span', { 'class': 'part-tooltip' }, tipText)
			]);
		}
		if (!parts || parts.length === 0) {
			var st = partState({ is_boot: dev.is_system, mount_point: dev.mount_point, fstype: dev.fstype });
			segs.push(makeSeg(st.cls, 100, dev.name + ' - ' + st.tag, dev.name));
		} else {
			parts.forEach(function(p) {
				used += (p.size || 0);
				var st = partState(p);
				var pct = (p.size / totalSize) * 100;
				var tip = p.name + ' (' + (p.size_formated || '') + ') - ' + st.tag +
					(p.fstype ? ' · ' + p.fstype : '') +
					(p.mount_point && p.mount_point !== '-' ? ' -> ' + p.mount_point : '');
				segs.push(makeSeg(st.cls, pct, tip, p.name));
			});
			var unalloc = totalSize - used;
			if (unalloc > totalSize * 0.015 && unalloc > 0) {
				var upct = (unalloc / totalSize) * 100;
				segs.push(makeSeg('part-state-unalloc', upct,
					_('Unallocated') + ' (' + formatBytes(unalloc) + ')', _('Unallocated')));
			}
		}
		return E('div', { 'class': 'disk-partition-bar' }, segs);
	},

	// Compact overview card (physical-disks tab): header + pill bar.
	buildDiskPartitionCard: function(dev) {
		var self = this;
		var parts = dev.partitions || [];
		var card = E('div', { 'class': 'disk-partition-card' });

		card.appendChild(E('div', { 'class': 'disk-part-card-header' }, [
			E('div', { 'class': 'disk-part-card-title' }, [
				E('span', { 'class': 'disk-bus-badge' }, this.busBadge(dev)),
				E('span', { 'class': 'disk-part-path' }, dev.path),
				E('span', { 'class': 'disk-part-model' }, dev.model || '')
			]),
			E('span', { 'class': 'disk-part-spec' }, (dev.size_formated || '') + (dev.p_table && dev.p_table !== '-' ? ' · ' + dev.p_table : ''))
		]));

		card.appendChild(E('div', { 'class': 'disk-part-card-meta' }, [
			E('span', { 'class': 'disk-meta-tag' }, [_('Partitions: %d').format(parts.length)]),
			E('span', { 'class': 'disk-meta-tag' }, [_('Serial: %s').format(dev.sn || '-')])
		]));

		card.appendChild(this.buildPillBar(dev, parts));

		return card;
	},

	// Detailed per-disk section (partition-management tab): header + bar/chips +
	// master partition table + bottom action bar. All protection rules apply.
	buildDiskCard: function(dev, info, data) {
		var self = this;
		var devName = dev.name;
		var mountPoints = data[1] || [];
		var formatCmds = data[4] || {};
		var parts = (info && info.partitions) || (dev.partitions) || [];

		var isSystem = !!(dev.is_system || (info && info.is_system));
		var anyMounted = parts.some(function(p) { return p.mount_point && p.mount_point !== '-'; });
		var hasPartitions = parts.some(function(p) { return p.number > 0; });
		var pTableVal = (info && info.p_table) || (dev.p_table || '');

		var card = E('fieldset', { 'class': 'disk-card-section', 'id': 'disk-group-' + devName });

		// Header (legend): identity left, size/table/SMART right.
		card.appendChild(E('legend', {}, [
			E('span', { 'style': 'display:flex; align-items:center; gap:8px; flex-wrap:wrap;' }, [
				E('span', { 'class': 'disk-bus-badge' }, this.busBadge(dev)),
				E('span', { 'style': 'font-size:14px; font-weight:600; color:var(--text-color-highest);' }, dev.path),
				E('span', { 'class': 'disk-part-model' }, dev.model || '')
			]),
			E('span', { 'style': 'display:flex; align-items:center; gap:12px; font-size:12px; color:var(--text-color-medium);' }, [
				((info && info.size_formated) || (dev.size_formated || '')),
				((info && info.p_table) || (dev.p_table || '')),
				this.buildSmartLink(devName, (info && info.health) || (dev.health_status))
			])
		]));

		// Pill bar only (the chips row was removed: the master partition table
		// below already lists name / size / fs / mount for every partition).
		var barWrap = E('div', { 'class': 'disk-card-bar-wrap' });
		barWrap.appendChild(this.buildPillBar(dev, parts));
		card.appendChild(barWrap);

		// Master partition table
		var optByDev = {};
		mountPoints.forEach(function(mp) { optByDev[mp.device] = mp.mount_options; });

		var partTable = E('table', { 'class': 'table cbi-section-table disk-card-table', 'style': 'min-width:1080px;' }, [
			E('colgroup', {}, [
				E('col', { 'style': 'width:11%;' }),
				E('col', { 'style': 'width:13%;' }),
				E('col', { 'style': 'width:16%;' }),
				E('col', { 'style': 'width:8%;' }),
				E('col', { 'style': 'width:9%;' }),
				E('col', { 'style': 'width:15%;' }),
				E('col', { 'style': 'width:7%;' }),
				E('col', { 'style': 'width:21%;' })
			]),
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Device')),
				E('th', { 'class': 'th' }, _('File System')),
				E('th', { 'class': 'th' }, _('Mount Point')),
				E('th', { 'class': 'th' }, _('Size')),
				E('th', { 'class': 'th' }, _('Usage')),
				E('th', { 'class': 'th' }, _('Mount Options')),
				E('th', { 'class': 'th' }, _('Auto Mount')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);

		parts.forEach(function(part) {
			var isFree = (part.number === -1 || part.fs === 'Free Space' || part.type === 'free');
			var isMounted = part.mount_point && part.mount_point !== '-';
			var isSystemPart = !!part.is_boot;
			var isExtended = (part.type === 'extended' || part.fs === 'extended');
			var opt = optByDev[part.path] || '—';

			if (isFree) {
				// Small firmware slivers (< 64 MiB) are not worth carving a new
				// partition on, so we don't offer a "New" button on them.
				var canCreate = (part.size || 0) >= MIN_MOUNT_BYTES;
				partTable.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'font-style:italic; color:var(--text-color-medium);' }, _('Free Space')),
					E('td', { 'class': 'td' }, part.size_formated || '-'),
					E('td', { 'class': 'td' }, '—'),
					E('td', { 'class': 'td' }, part.size_formated || '-'),
					E('td', { 'class': 'td' }, '—'),
					E('td', { 'class': 'td' }, '—'),
					E('td', { 'class': 'td' }, '—'),
					E('td', { 'class': 'td cbi-section-actions' }, canCreate
						? E('button', {
							'class': 'btn cbi-button cbi-button-add',
							'title': _('Create a partition in this free region'),
							'click': function(ev) { ev.preventDefault(); self.showCreatePartitionModal(devName, info); }
						}, _('New'))
						: E('span', { 'class': 'label label-cbi-state-disabled' }, _('Unallocated')))
				]));
				return;
			}

			var fsCell = E('span', {
				'title': isSystemPart ? _('System partition, protected') : null
			}, translateFs(part.fs, part.type));

			// Unmounted non-system partitions show a plain dash in the mount-point
			// column - state is already obvious from the FS column and the pill bar.
			// System/boot segments on a FIT-based eMMC are consumed by the bootloader
			// and kernel (e.g. the FIT image) and are never mounted as a filesystem;
			// a bare "—" here read as "unused", so spell the real role out instead.
			var mountCell;
			if (isMounted) {
				mountCell = [ E('span', { 'class': 'badge badge-status badge-mounted' }, _('Mounted')), ' ', E('code', {}, part.mount_point) ];
			} else if (isSystemPart) {
				mountCell = E('span', {
					'style': 'font-style:italic; color:var(--text-color-medium);',
					'title': _('Loaded by the bootloader and kernel from the FIT image; not mounted as a separate filesystem.')
				}, _('Kernel-managed (FIT)'));
			} else {
				mountCell = '—';
			}

			var usageCell = (isMounted && part.usage)
				? E('div', { 'style': 'display:flex; align-items:center; gap:6px;' }, [
					E('div', { 'style': 'width:60px; height:6px; background:var(--background-color-medium); border-radius:3px; overflow:hidden;' }, [
						E('div', { 'style': 'width:' + part.usage + '; height:100%; background:var(--primary-color-high);' })
					]),
					E('span', { 'style': 'font-size:11px; color:var(--text-color-medium);' }, part.usage)
				])
				: '—';

			// Unmounted partitions show a plain dash in the auto-mount column -
			// labelling an unmounted partition "Disabled" read as contradictory.
			var autoCell = isMounted
				? E('span', { 'style': 'color:var(--success-color-high); font-size:12px;' }, _('Enabled'))
				: '—';

			var actions = [];
			if (isSystemPart) {
				// System partitions are not operable at all.
				actions.push(E('span', { 'class': 'label label-cbi-state-disabled' }, _('System partition, protected')));
			} else {
				var hasLogicals = parts.some(function(p) { return p.type === 'logical'; });
				if (isMounted) {
					actions.push(E('button', {
						'class': 'btn cbi-button cbi-button-neutral',
						'title': _('Detach this partition from its mount point; data is kept'),
						'click': function(ev) {
							ev.preventDefault();
							self.showConfirm(_('Unmount'),
								_('Are you sure you want to unmount %s?').format(part.mount_point),
								function() {
									ui.showModal(_('Unmounting'), [ E('p', { 'class': 'spinning' }, _('Unmounting %s...').format(part.mount_point)) ]);
									callUmount(part.mount_point).then(function(res) {
										if (res && res.code !== 0) {
											ui.addNotification(null, E('p', {}, res.error || _('Failed to unmount.')));
										}
										location.reload();
									});
								});
						}
					}, _('Unmount')));
					actions.push(E('button', {
						'class': 'btn cbi-button cbi-button-edit',
						'title': _('Change mount point / options'),
						'click': function(ev) { ev.preventDefault(); self.showMountModal(devName, dev, info, part, data); }
					}, _('Edit Mount')));
				} else {
					// Unmounted: Mount + Format (non-extended); Delete unless it's
					// an extended container still holding logicals.
					if (!isExtended) {
						actions.push(E('button', {
							'class': 'btn cbi-button cbi-button-add',
							'title': _('Mount this partition'),
							'click': function(ev) { ev.preventDefault(); self.showMountModal(devName, dev, info, part, data); }
						}, _('Mount')));
					}
					if (!isExtended) {
						actions.push(E('button', {
							'class': 'btn cbi-button cbi-button-negative',
							'title': _('Formatting erases all data on the partition'),
							'click': function(ev) {
								ev.preventDefault();
								self.showFormatModal(part.name, formatCmds, part.fs, function() { location.reload(); });
							}
						}, _('Format')));
					}
					if (!(isExtended && hasLogicals)) {
						actions.push(E('button', {
							'class': 'btn cbi-button cbi-button-negative',
							'title': _('Remove this partition from the table; its space becomes unallocated'),
							'click': function(ev) {
								ev.preventDefault();
								self.showConfirm(_('Delete Partition'),
									_('Are you sure you want to delete partition %s?').format(part.name),
									function() {
										ui.showModal(_('Deleting Partition'), [ E('p', { 'class': 'spinning' }, _('Removing partition...')) ]);
										callRemovePartition(devName, part.number).then(function(res) {
											if (res && res.code !== 0) {
												ui.addNotification(null, E('p', {}, res.error || _('Failed to remove partition.')));
											}
											location.reload();
										});
									});
							}
						}, _('Delete')));
					}
				}
			}

			partTable.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td col-device' }, E('strong', {}, part.name || ('/' + devName + part.number))),
				E('td', { 'class': 'td col-fs' }, fsCell),
				E('td', { 'class': 'td col-mount' }, mountCell),
				E('td', { 'class': 'td' }, part.size_formated || '-'),
				E('td', { 'class': 'td' }, usageCell),
				E('td', { 'class': 'td' }, E('span', { 'class': 'mount-options-text', 'title': opt }, opt)),
				E('td', { 'class': 'td col-automount' }, autoCell),
				E('td', { 'class': 'td cbi-section-actions' }, [ E('div', { 'class': 'btn-group-actions' }, actions) ])
			]));
		});

		// (The inline quick-mount row was removed: every unmounted partition row
		// already has a Mount button that opens showMountModal, which lists all
		// mountable partitions on this disk — the inline row duplicated that.)

		card.appendChild(partTable);

		// Bottom action bar
		var left = E('div', { 'class': 'disk-actions-left' });
		var right = E('div', { 'class': 'disk-actions-right' });
		if (!isSystem) {
			left.appendChild(E('button', {
				'class': 'btn cbi-button cbi-button-add',
				'title': _('Create a new partition from the largest free region'),
				'click': function(ev) { ev.preventDefault(); self.showCreatePartitionModal(devName, info); }
			}, _('New Partition')));
			left.appendChild(E('button', {
				'class': 'btn cbi-button cbi-button-negative',
				'disabled': anyMounted || null,
				'click': function(ev) {
					ev.preventDefault();
					if (anyMounted) {
						ui.addNotification(null, E('p', {}, _('Device is in use! Please unmount all partitions first!')));
						return;
					}
					self.showConfirm(_('Eject Device'),
						_('Are you sure you want to eject/remove this device?'),
						function() {
							ui.showModal(_('Ejecting'), [ E('p', { 'class': 'spinning' }, _('Ejecting device...')) ]);
							callEjectDevice(devName).then(function(res) {
								if (res && res.code !== 0) {
									ui.addNotification(null, E('p', {}, res.error || _('Failed to eject device.')));
								}
								location.reload();
							});
						});
				}
			}, _('Eject')));
		}
		// The backend's mk_partition_table is `parted mklabel` (destructive wipe),
		// so it is only offered on a disk with NO partitions yet - never on a disk
		// that already has a layout (protects the eMMC / any real disk).
		if (!hasPartitions && !isSystem && pTableVal && pTableVal.indexOf('Raid') === -1) {
			var ptSel = E('select', { 'class': 'cbi-input-select' }, [
				E('option', { 'value': 'GPT' }, 'GPT'),
				E('option', { 'value': 'MBR' }, 'MBR')
			]);
			right.appendChild(ptSel);
			right.appendChild(E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'title': _('Create a fresh GPT/MBR partition table'),
				'click': function(ev) {
					ev.preventDefault();
					var label = ptSel.value === 'MBR' ? 'MBR' : 'GPT';
					self.showConfirm(_('Change Partition Table'),
						_('Warning !!\nTHIS WILL OVERWRITE EXISTING PARTITIONS!!\nModify the partition table to %s?').format(label),
						function() {
							ui.showModal(_('Modifying Partition Table'), [ E('p', { 'class': 'spinning' }, _('Applying partition table...')) ]);
							callMkPartitionTable(devName, ptSel.value).then(function(res) {
								if (res && res.code !== 0) {
									ui.addNotification(null, E('p', {}, res.error || _('Failed to modify partition table.')));
								}
								location.reload();
							});
						});
				}
			}, _('Apply Table')));
		}

		card.appendChild(E('div', { 'class': 'disk-card-actions-bar' }, [
			E('div', { 'class': 'disk-actions-flex' }, [ left, right ])
		]));

		return card;
	},

	// --- RAID -----------------------------------------------------------------

	buildRaidForm: function(data) {
		var self = this;
		var devices = data[0] || {};
		var form = E('fieldset', { 'class': 'cbi-section disk-card-section' });
		form.appendChild(E('legend', {}, [
			E('span', {}, [
				_('Create RAID'),
				E('span', { 'style': 'font-size:12px; font-weight:normal; color:var(--text-color-medium); margin-left:8px;' },
					'(' + _('Select two or more free partitions to build a high-reliability or high-performance array') + ')')
			])
		]));
		var node = E('div', { 'class': 'cbi-section-node' });
		var nameIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': '/dev/md1', 'style': 'width:240px;' });
		var levelSel = E('select', { 'class': 'cbi-input-select', 'style': 'min-width:320px;' }, [
			E('option', { 'value': '1', 'selected': true }, 'RAID 1 ' + _('(Mirror - recommended dual-disk data fault tolerance, doubled read speed)')),
			E('option', { 'value': '0' }, 'RAID 0 ' + _('(Stripe - high throughput, no redundancy, full capacity)')),
			E('option', { 'value': '5' }, 'RAID 5 ' + _('(Distributed parity redundancy - needs at least 3 partitions)')),
			E('option', { 'value': '6' }, 'RAID 6 ' + _('(Double parity fault tolerance - needs at least 4 partitions)')),
			E('option', { 'value': '10' }, 'RAID 10 ' + _('(Mirror + Stripe hybrid - performance with high fault tolerance)'))
		]);
		var chipGroup = buildMemberChips(devices, _('No free partitions available to select.'));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('RAID Name')),
			E('div', { 'class': 'cbi-value-field' }, [
				nameIn,
				E('div', { 'class': 'cbi-value-description', 'style': 'font-size:11px; color:var(--text-color-medium); margin-top:3px;' },
					_('Standard software RAID block device path, defaults to /dev/md1, /dev/md2...'))
			])
		]));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('RAID Level')),
			E('div', { 'class': 'cbi-value-field' }, levelSel)
		]));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('RAID Members')),
			E('div', { 'class': 'cbi-value-field' }, [
				chipGroup,
				E('div', { 'class': 'cbi-value-description', 'style': 'font-size:11px; color:var(--text-color-medium); margin-top:4px;' },
					_('All currently unmounted free storage partitions are listed automatically.'))
			])
		]));
		form.appendChild(node);
		var createBtn = E('button', {
			'class': 'btn cbi-button cbi-button-action important',
			'click': function(ev) {
				ev.preventDefault();
				var members = [];
				var boxes = chipGroup.querySelectorAll('input[type="checkbox"]');
				for (var i = 0; i < boxes.length; i++) { if (boxes[i].checked) members.push(boxes[i].value); }
				if (members.length < 2) {
					ui.addNotification(null, E('p', {}, _('Select at least two RAID members!')));
					return;
				}
				self.showConfirm(_('Create RAID'),
					_('Creating a RAID array will ERASE the selected members. Continue?'),
					function() {
						ui.showModal(_('Creating RAID'), [ E('p', { 'class': 'spinning' }, _('Creating RAID device...')) ]);
						callCreateRaid(nameIn.value, levelSel.value, members).then(function(res) {
							if (res && res.code !== 0) {
								ui.addNotification(null, E('p', {}, res.error || _('Failed to create RAID.')));
							}
							location.reload();
						});
					});
			}
		}, _('Create RAID'));
		var resetBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': function(ev) { ev.preventDefault(); if (typeof currentDraw === 'function') currentDraw(); }
		}, _('Reset'));
		form.appendChild(E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:16px; display:flex; gap:10px;' }, [ createBtn, resetBtn ]));
		return form;
	},

	// --- Btrfs ----------------------------------------------------------------

	buildBtrfsCard: function(pool, info, subs, data) {
		var self = this;
		var uuid = pool.uuid;
		var mountPoints = data[1] || [];
		var members = (pool.members || '').split(/\s*,\s*/).filter(Boolean);
		var mp = btrfsMountPoint(mountPoints, pool.members);
		var infoObj = info || {};
		var usagePct = parseFloat(infoObj.usage) || 0;

		var card = E('fieldset', { 'class': 'cbi-section disk-card-section btrfs-pool-card' });

		// legend:  Btrfs: <label>  (副标题 + 健康badge)      UUID
		card.appendChild(E('legend', {}, [
			E('span', {}, [
				_('Btrfs') + ': ',
				E('code', {}, pool.label || uuid),
				E('span', { 'style': 'font-size:12px; font-weight:normal; color:var(--text-color-medium); margin-left:8px;' }, [
					'(' + _('next-gen CoW write-time-copy storage pool') + ' | ',
					E('span', { 'class': 'badge-status badge-mounted', 'style': 'margin:0 4px;' }, _('Healthy / Online')),
					')'
				])
			]),
			E('span', { 'style': 'font-size:11px; font-weight:normal; color:var(--text-color-medium); font-family:monospace; margin-left:12px;' },
				'UUID: ' + uuid)
		]));

		// pool overview bar
		var mpCell = mp
			? [ E('span', { 'class': 'badge-status badge-mounted' }, _('Mounted')), E('code', {}, ' ' + mp) ]
			: [ E('span', { 'class': 'badge-status badge-unmounted' }, _('Unmounted')) ];
		card.appendChild(E('div', { 'class': 'pool-meta-bar' }, [
			E('div', { 'class': 'pool-meta-item' }, [
				E('span', { 'style': 'color:var(--text-color-medium);' }, _('Mount Point') + ': '), mpCell
			]),
			E('div', { 'class': 'pool-meta-item' }, [
				E('span', { 'style': 'color:var(--text-color-medium);' }, _('Members') + ': '),
				members.map(function(m) { return E('span', { 'class': 'badge-member' }, m); })
			]),
			E('div', { 'class': 'pool-meta-item' }, [
				E('span', { 'style': 'color:var(--text-color-medium);' }, _('Data Profile') + ': '),
				E('span', { 'class': 'badge-tech' }, 'Data: ' + (infoObj.data_raid_level || 'single') + ' | Meta: ' + (infoObj.metadata_raid_level || 'dup'))
			]),
			E('div', { 'class': 'pool-meta-item' }, [
				E('span', { 'style': 'color:var(--text-color-medium);' }, _('Usage') + ': '),
				E('span', {}, (pool.used_formated || '0 B') + ' / ' + (pool.size_formated || '-'))
			])
		]));

		// capacity allocation progress bar
		card.appendChild(E('div', { 'style': 'margin:0 0 16px 0;' }, [
			E('div', { 'class': 'cbi-progressbar', 'title': pool.used_formated || '' }, [
				E('div', { 'style': 'width:' + usagePct + '%;' })
			])
		]));

		// subvolumes heading
		card.appendChild(E('h4', { 'style': 'margin:14px 0 8px 0; font-size:13px; font-weight:normal; color:var(--text-color-highest);' }, _('Subvolumes & Snapshots')));

		// subvolumes & snapshots table (6 columns)
		var subTable = E('table', { 'class': 'table cbi-section-table disk-card-table' }, [
			E('colgroup', {}, [
				E('col', { 'style': 'width:8%' }),
				E('col', { 'style': 'width:16%' }),
				E('col', { 'style': 'width:24%' }),
				E('col', { 'style': 'width:16%' }),
				E('col', { 'style': 'width:16%' }),
				E('col', { 'style': 'width:20%' })
			]),
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('ID')),
				E('th', { 'class': 'th' }, _('Subvolume')),
				E('th', { 'class': 'th' }, _('Mount Path')),
				E('th', { 'class': 'th' }, _('Attributes')),
				E('th', { 'class': 'th' }, _('Size')),
				E('th', { 'class': 'th cbi-section-actions' }, _('Actions'))
			])
		]);
		subs.forEach(function(sv) {
			var isRoot = (sv.id === '5' || sv.path === '/');
			var isDefault = !!sv.default_subvolume;
			var mountPathCell = mp ? E('code', {}, mp + sv.path) : E('span', { 'style': 'color:var(--text-color-medium);' }, '-');
			var attrCell = isDefault
				? E('span', { 'class': 'badge-status badge-mounted' }, _('Default'))
				: E('span', { 'style': 'color:var(--text-color-medium); font-size:12px;' }, _('Read/Write'));
			var setDefBtn = E('button', {
				'class': 'btn cbi-button cbi-button-edit',
				'disabled': (isDefault || isRoot) || null,
				'click': function(ev) {
					ev.preventDefault();
					ui.showModal(_('Setting Default'), [ E('p', { 'class': 'spinning' }, _('Setting default subvolume...')) ]);
					callBtrfsSubvolSetDefault(uuid, sv.path).then(function(res) {
						if (res && res.code !== 0) {
							ui.addNotification(null, E('p', {}, res.error || _('Failed to set default subvolume.')));
						}
						location.reload();
					});
				}
			}, _('Set Default'));
			var delBtn = E('button', {
				'class': 'btn cbi-button cbi-button-negative',
				'disabled': (isRoot || isDefault) || null,
				'click': function(ev) {
					ev.preventDefault();
					self.showConfirm(_('Delete Subvolume'),
						_('Are you sure you want to delete subvolume %s?').format(sv.path),
						function() {
							ui.showModal(_('Deleting Subvolume'), [ E('p', { 'class': 'spinning' }, _('Deleting subvolume...')) ]);
							callBtrfsSubvolDelete(uuid, sv.path).then(function(res) {
								if (res && res.code !== 0) {
									ui.addNotification(null, E('p', {}, res.error || _('Failed to delete subvolume.')));
								}
								location.reload();
							});
						});
				}
			}, _('Delete'));
			var snapBtn = E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': function(ev) {
					ev.preventDefault();
					ui.showModal(_('Creating Snapshot'), [ E('p', { 'class': 'spinning' }, _('Creating Btrfs snapshot...')) ]);
					callBtrfsSnapshotCreate(uuid, sv.path, '', false).then(function(res) {
						if (res && res.code !== 0) {
							ui.addNotification(null, E('p', {}, res.error || _('Failed to create snapshot.')));
						}
						location.reload();
					});
				}
			}, _('Snapshot'));
			subTable.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, sv.id),
				E('td', { 'class': 'td' }, E('strong', {}, sv.path)),
				E('td', { 'class': 'td' }, mountPathCell),
				E('td', { 'class': 'td' }, attrCell),
				E('td', { 'class': 'td' }, E('span', { 'style': 'color:var(--text-color-medium);' }, '-')),
				E('td', { 'class': 'td cbi-section-actions' }, [ E('div', { 'class': 'btn-group-actions' }, [ setDefBtn, delBtn, snapBtn ]) ])
			]));
		});
		card.appendChild(subTable);

		// pool maintenance action bar:  + New Subvolume (real: btrfs_subvol_create)
		var newSubvPath = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': '/new_subvolume', 'style': 'width:200px;' });
		var newSubvBtn = E('button', {
			'class': 'btn cbi-button cbi-button-add',
			'click': function(ev) {
				ev.preventDefault();
				var p = newSubvPath.value;
				if (!p || p.charAt(0) !== '/') {
					ui.addNotification(null, E('p', {}, _("Subvolume path must start with '/'")));
					return;
				}
				ui.showModal(_('Creating Subvolume'), [ E('p', { 'class': 'spinning' }, _('Creating subvolume...')) ]);
				callBtrfsSubvolCreate(uuid, p).then(function(res) {
					if (res && res.code !== 0) {
						ui.addNotification(null, E('p', {}, res.error || _('Failed to create subvolume.')));
					}
					location.reload();
				});
			}
		}, '+ ' + _('New Subvolume'));
		card.appendChild(E('div', {
			'class': 'cbi-section-node disk-card-actions-bar',
			'style': 'margin-top:12px; padding:8px 12px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;'
		}, [
			E('div', { 'style': 'display:flex; gap:8px; align-items:center;' }, [ newSubvBtn, newSubvPath ])
		]));

		return card;
	},

	buildBtrfsForm: function(data) {
		var self = this;
		var devices = data[0] || {};
		var form = E('fieldset', { 'class': 'cbi-section disk-card-section' });
		form.appendChild(E('legend', {}, [
			E('span', {}, [
				_('Create Btrfs Pool'),
				E('span', { 'style': 'font-size:12px; font-weight:normal; color:var(--text-color-medium); margin-left:8px;' },
					'(' + _('Format and create a modern filesystem with snapshots, transparent compression and online growth') + ')')
			])
		]));
		var node = E('div', { 'class': 'cbi-section-node' });
		var labelIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': 'Vault_Btrfs_Pool', 'style': 'width:240px;' });
		var profileSel = E('select', { 'class': 'cbi-input-select', 'style': 'min-width:320px;' }, [
			E('option', { 'value': 'single', 'selected': true }, 'Single ' + _('(single-device, maximizes usable capacity)')),
			E('option', { 'value': 'dup' }, 'DUP ' + _('(double metadata copies, recommended for important data)')),
			E('option', { 'value': 'raid1' }, 'RAID 1 ' + _('(multi-device mirror redundancy)')),
			E('option', { 'value': 'raid0' }, 'RAID 0 ' + _('(multi-device stripe for fast I/O)'))
		]);
		var chipGroup = buildMemberChips(devices, _('No free partitions available to select.'));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Pool Label')),
			E('div', { 'class': 'cbi-value-field' }, [
				labelIn,
				E('div', { 'class': 'cbi-value-description', 'style': 'font-size:11px; color:var(--text-color-medium); margin-top:3px;' },
					_('Storage pool volume label, used as the mount / management identifier.'))
			])
		]));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Members')),
			E('div', { 'class': 'cbi-value-field' }, [
				chipGroup,
				E('div', { 'class': 'cbi-value-description', 'style': 'font-size:11px; color:var(--text-color-medium); margin-top:4px;' },
					_('All currently unmounted free storage partitions are listed automatically.'))
			])
		]));
		node.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Data Profile')),
			E('div', { 'class': 'cbi-value-field' }, profileSel)
		]));
		form.appendChild(node);
		var createBtn = E('button', {
			'class': 'btn cbi-button cbi-button-action important',
			'click': function(ev) {
				ev.preventDefault();
				var members = [];
				var boxes = chipGroup.querySelectorAll('input[type="checkbox"]');
				for (var i = 0; i < boxes.length; i++) { if (boxes[i].checked) members.push(boxes[i].value); }
				if (members.length === 0) {
					ui.addNotification(null, E('p', {}, _('Please select at least one Btrfs member!')));
					return;
				}
				self.showConfirm(_('Create Btrfs Pool'),
					_('Creating Btrfs will ERASE the selected members. Continue?'),
					function() {
						ui.showModal(_('Creating Btrfs'), [ E('p', { 'class': 'spinning' }, _('Creating Btrfs filesystem...')) ]);
						callCreateBtrfs(labelIn.value, profileSel.value, members).then(function(res) {
							if (res && res.code !== 0) {
								ui.addNotification(null, E('p', {}, res.error || _('Failed to create Btrfs.')));
							}
							location.reload();
						});
					});
			}
		}, _('Create Btrfs Pool'));
		var resetBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': function(ev) { ev.preventDefault(); if (typeof currentDraw === 'function') currentDraw(); }
		}, _('Reset'));
		form.appendChild(E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:16px; display:flex; gap:10px;' }, [ createBtn, resetBtn ]));
		return form;
	},

	// --- tabs -----------------------------------------------------------------

	renderDisksTab: function(data) {
		var self = this;
		var devices = data[0] || {};
		var devKeys = Object.keys(devices);
		var root = E('div', { 'class': 'disks-tab' });

		if (devKeys.length === 0) {
			root.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('p', { 'style': 'text-align:center; color:var(--text-color-medium); font-style:italic; padding:2rem;' }, _('No disks detected.'))
			]));
			return root;
		}

		// Disks table
		var diskTable = E('table', { 'class': 'table cbi-section-table disk-card-table disk-overview-table', 'style': 'min-width:1000px;' }, [
			E('colgroup', {}, [
				E('col', { 'style': 'width:11%;' }),
				E('col', { 'style': 'width:14%;' }),
				E('col', { 'style': 'width:13%;' }),
				E('col', { 'style': 'width:8%;' }),
				E('col', { 'style': 'width:7%;' }),
				E('col', { 'style': 'width:8%;' }),
				E('col', { 'style': 'width:9%;' }),
				E('col', { 'style': 'width:15%;' }),
				// Actions column: fixed px (not %) so its width is guaranteed at
				// any table width. A %-width + table min-width lets Chromium keep
				// the column at 150px even though the cell's min-width is 175px,
				// which clips the "Manage Partitions" button once cell padding is
				// subtracted. 180px leaves ~164px usable (8px cell padding each
				// side), comfortably wider than the button at any theme font size.
				E('col', { 'style': 'width:180px;' })
			]),
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Path')),
				E('th', { 'class': 'th' }, _('Model')),
				E('th', { 'class': 'th' }, _('Serial Number')),
				E('th', { 'class': 'th' }, _('Size')),
				E('th', { 'class': 'th' }, _('Temp')),
				E('th', { 'class': 'th' }, _('Partition Table')),
				E('th', { 'class': 'th' }, _('SATA Version')),
				E('th', { 'class': 'th' }, _('Health Status')),
				E('th', { 'class': 'th' }, _('Actions'))
			])
		]);
		devKeys.forEach(function(k) {
			var dev = devices[k];
			var pwr = translatePowerStatus(dev.status);
			var healthCell = [ self.buildSmartLink(dev.name, dev.health_status) ];
			if (pwr && pwr !== '-') {
				healthCell.push(E('span', { 'style': 'color:var(--text-color-medium); font-size:11px; margin-left:4px;' }, '(' + pwr + ')'));
			}
			diskTable.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', {}, dev.path)),
				E('td', { 'class': 'td' }, dev.model || '-'),
				E('td', { 'class': 'td' }, dev.sn || '-'),
				E('td', { 'class': 'td' }, dev.size_formated || '-'),
				E('td', { 'class': 'td' }, dev.temp || '-'),
				E('td', { 'class': 'td' }, dev.p_table || '-'),
				E('td', { 'class': 'td' }, dev.sata_ver || '-'),
				E('td', { 'class': 'td' }, healthCell),
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': function(ev) { ev.preventDefault(); gotoTab('partitions', dev.name); }
					}, _('Manage Partitions'))
				])
			]));
		});
		root.appendChild(E('div', { 'class': 'cbi-section', 'style': 'margin-bottom:16px; overflow-x:auto;' }, [ diskTable ]));

		// Legend + per-disk cards
		root.appendChild(this.buildLegend());
		devKeys.forEach(function(k) {
			root.appendChild(self.buildDiskPartitionCard(devices[k]));
		});

		return root;
	},

	renderPartitionsTab: function(data) {
		var self = this;
		var devices = data[0] || {};
		var devKeys = Object.keys(devices);
		var wrap = E('div', { 'class': 'partitions-tab' });

		if (devKeys.length === 0) {
			wrap.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('p', { 'style': 'text-align:center; color:var(--text-color-medium); font-style:italic; padding:2rem;' }, _('No disks detected.'))
			]));
			return wrap;
		}

		// Per-disk rich data (sectors / used / free / usage) needs get_disk_info.
		var loading = E('div', { 'class': 'cbi-section' }, [ E('p', { 'class': 'spinning' }, _('Loading...')) ]);
		wrap.appendChild(loading);
		wrap.appendChild(this.buildLegend());

		// Cache get_disk_info per disk so re-selecting this tab is instant
		// (the backend query runs smartctl and is slow). Mutating actions all
		// end in location.reload(), which clears the cache by rebuilding context.
		var jobs = devKeys.map(function(k) {
			return (_diskInfoCache && _diskInfoCache[k])
				? Promise.resolve(_diskInfoCache[k])
				: callGetDiskInfo(k).then(function(res) {
					if (!_diskInfoCache) _diskInfoCache = {};
					_diskInfoCache[k] = res;
					return res;
				});
		});
		Promise.all(jobs).then(function(infos) {
			// remove the loading container entirely (not just the spinner)
			if (loading.parentNode) loading.parentNode.removeChild(loading);
			var cards = [];
			devKeys.forEach(function(k, i) {
				var dev = devices[k];
				var info = infos[i] || {};
				if (info.error || !info.size) {
					cards.push(E('div', { 'class': 'cbi-section', 'id': 'disk-group-' + k }, [
						E('p', { 'style': 'color:var(--error-color-high);' },
							_('Device /dev/%s not found or has no media.').format(k))
					]));
				} else {
					cards.push(self.buildDiskCard(dev, info, data));
				}
			});
			cards.forEach(function(c) { wrap.appendChild(c); });
		}).catch(function() {
			dom.content(wrap, [
				E('div', { 'class': 'cbi-section' }, [
					E('p', { 'style': 'color:var(--error-color-high);' }, _('Failed to load disk info.'))
				])
			]);
		});

		return wrap;
	},

	renderRaidTab: function(data) {
		var self = this;
		var raidDevices = data[2] || {};
		var mountPoints = data[1] || [];
		var keys = Object.keys(raidDevices);
		var root = E('div', { 'class': 'raid-tab' });

		// --- Section 1: Active RAID Arrays ---
		var sec = E('fieldset', { 'class': 'cbi-section disk-card-section raid-pool-card' });
		sec.appendChild(E('legend', {}, [
			E('span', {}, [
				_('Active RAID Arrays'),
				E('span', { 'style': 'font-size:12px; font-weight:normal; color:var(--text-color-medium); margin-left:8px;' },
					'(' + _('Linux mdadm redundant array monitoring') + ')')
			])
		]));

		if (keys.length === 0) {
			sec.appendChild(E('p', { 'style': 'color:var(--text-color-medium); font-style:italic; padding:8px 0;' }, _('No RAID arrays.')));
			root.appendChild(sec);
			root.appendChild(this.buildRaidForm(data));
			return root;
		}

		var table = E('table', { 'class': 'table cbi-section-table disk-card-table' }, [
			E('colgroup', {}, [
				E('col', { 'style': 'width:12%' }),
				E('col', { 'style': 'width:14%' }),
				E('col', { 'style': 'width:10%' }),
				E('col', { 'style': 'width:14%' }),
				E('col', { 'style': 'width:16%' }),
				E('col', { 'style': 'width:20%' }),
				E('col', { 'style': 'width:14%' })
			]),
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Device')),
				E('th', { 'class': 'th' }, _('RAID Level')),
				E('th', { 'class': 'th' }, _('Size')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Mount Point')),
				E('th', { 'class': 'th' }, _('Members')),
				E('th', { 'class': 'th cbi-section-actions' }, _('Actions'))
			])
		]);

		keys.forEach(function(k) {
			var r = raidDevices[k];
			var members = (r.members_str || '').split(',').map(function(s) { return s.trim(); }).filter(Boolean);
			var mp = mountPointFor(mountPoints, r.path);
			var mounted = !!mp;
			var detailBtn = E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': function(ev) { ev.preventDefault(); self.showRaidInfoModal(r); }
			}, _('Detail'));
			var stopBtn = E('button', {
				'class': 'btn cbi-button cbi-button-neutral',
				'click': function(ev) {
					ev.preventDefault();
					self.showConfirm(_('Stop Array'),
						_('Are you sure you want to stop and remove RAID array %s?').format(r.path),
						function() {
							ui.showModal(_('Stopping Array'), [ E('p', { 'class': 'spinning' }, _('Stopping RAID array...')) ]);
							callEjectDevice(r.name).then(function(res) {
								if (res && res.code !== 0) {
									ui.addNotification(null, E('p', {}, res.error || _('Failed to stop array.')));
								}
								location.reload();
							});
						});
				}
			}, _('Stop'));
			var statusCell = [
				E('span', { 'class': 'badge-status ' + (r.active === 'ACTIVE' ? 'badge-mounted' : 'badge-unmounted') }, r.active || '-')
			];
			if (r.status) {
				statusCell.push(E('span', { 'style': 'font-size:11px; color:var(--success-color-high); margin-left:4px;' }, r.status));
			}
			var mountCell = mounted
				? [ E('span', { 'class': 'badge-status badge-mounted' }, _('Mounted')), E('code', {}, ' ' + mp) ]
				: [ E('span', { 'class': 'badge-status badge-unmounted' }, _('Unmounted')) ];
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td col-device' }, E('strong', {}, r.path)),
				E('td', { 'class': 'td' }, E('span', { 'class': 'badge-status badge-mounted' }, r.level || '-')),
				E('td', { 'class': 'td' }, r.size_formated || '-'),
				E('td', { 'class': 'td' }, statusCell),
				E('td', { 'class': 'td' }, mountCell),
				E('td', { 'class': 'td' }, members.map(function(m) { return E('span', { 'class': 'badge-member' }, m); })),
				E('td', { 'class': 'td cbi-section-actions' }, [ E('div', { 'class': 'btn-group-actions' }, [ detailBtn, stopBtn ]) ])
			]));
		});

		sec.appendChild(table);
		root.appendChild(sec);
		root.appendChild(this.buildRaidForm(data));
		return root;
	},

	renderBtrfsTab: function(data) {
		var self = this;
		var btrfsDevices = data[3] || {};
		var keys = Object.keys(btrfsDevices);
		var root = E('div', { 'class': 'btrfs-tab' });
		var createForm = this.buildBtrfsForm(data);

		if (keys.length === 0) {
			var bsec = E('fieldset', { 'class': 'cbi-section disk-card-section btrfs-pool-card' });
			bsec.appendChild(E('legend', {}, [
				E('span', {}, [
					_('Btrfs Pools'),
					E('span', { 'style': 'font-size:12px; font-weight:normal; color:var(--text-color-medium); margin-left:8px;' },
						'(' + _('next-gen CoW write-time-copy storage pool') + ')')
				])
			]));
			bsec.appendChild(E('p', { 'style': 'color:var(--text-color-medium); font-style:italic; padding:8px 0;' }, _('No Btrfs filesystems.')));
			root.appendChild(bsec);
			root.appendChild(createForm);
			return root;
		}

		var placeholder = E('div', { 'class': 'cbi-section' }, [ E('p', { 'class': 'spinning' }, _('Loading...')) ]);
		root.appendChild(placeholder);
		root.appendChild(createForm);

		// Fetch pool info (usage / data+meta profile) AND subvolumes for every pool.
		var jobs = [];
		keys.forEach(function(k) {
			jobs.push(callGetBtrfsInfo(k));
			jobs.push(callGetBtrfsSubvolumes(k));
		});
		Promise.all(jobs).then(function(results) {
			if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
			var cards = [];
			keys.forEach(function(k, i) {
				var info = results[i * 2] || {};
				// get_btrfs_subvolumes declares expect {subvolumes:[]}, so LuCI
				// resolves the ubus result to the BARE ARRAY (same as
				// get_mount_points). Accept it directly; fall back to the wrapped
				// shape for robustness against a future expect change.
				var subsRaw = results[i * 2 + 1];
				var subs = Array.isArray(subsRaw) ? subsRaw
					: ((subsRaw && subsRaw.subvolumes) || []);
				cards.push(self.buildBtrfsCard(btrfsDevices[k], info, subs, data));
			});
			cards.forEach(function(c) { root.insertBefore(c, createForm); });
		}).catch(function() {
			dom.content(placeholder, [
				E('p', { 'style': 'color:var(--error-color-high);' }, _('Failed to load Btrfs pools.'))
			]);
		});

		return root;
	},

	renderTab: function(key, data) {
		if (key === 'partitions') return this.renderPartitionsTab(data);
		if (key === 'raid') return this.renderRaidTab(data);
		if (key === 'btrfs') return this.renderBtrfsTab(data);
		return this.renderDisksTab(data);
	},

	// --- top-level shell ------------------------------------------------------

	render: function(data) {
		ensureStyles();
		var self = this;
		var container = E('div', { 'class': 'cbi-map' });

		container.appendChild(E('div', { 'style': 'margin-bottom:1rem;' }, [
			E('h2', { 'style': 'margin-bottom:0.25rem;' }, _('DiskManager')),
			E('div', { 'class': 'cbi-map-descr', 'style': 'margin-bottom:0.75rem;' }, _('Manage disks, partitions, RAID and Btrfs over LuCI.')),
			E('div', { 'style': 'margin-bottom:0.5rem;' }, [
				E('button', {
					'class': 'cbi-button cbi-button-add',
					'click': function(ev) {
						ev.preventDefault();
						ui.showModal(_('Rescan Disks'), [ E('p', { 'class': 'spinning' }, _('Rescanning SCSI and RAID devices...')) ]);
						callRescanDisks().then(function() { location.reload(); });
					}
				}, _('Rescan Disks'))
			])
		]));

		var nav = E('div', { 'class': 'cbi-tabmenu', 'style': 'margin-bottom:0.5rem;' });
		var content = E('div', { 'class': 'diskbox-tab-content' });
		container.appendChild(nav);
		container.appendChild(content);

		var tabs = [
			{ key: 'disks', label: _('Physical Disks') },
			{ key: 'partitions', label: _('Partition Management') },
			{ key: 'raid', label: _('RAID Arrays') },
			{ key: 'btrfs', label: _('Btrfs Pools') }
		];

		function draw() {
			dom.content(nav, tabs.map(function(t) {
				return E('li', { 'class': 'cbi-tab' + (activeMainTab === t.key ? ' cbi-tab-active active' : '') }, [
					E('a', {
						'href': '#',
						'click': function(ev) {
							ev.preventDefault();
							if (activeMainTab !== t.key) { activeMainTab = t.key; syncTabHash(); draw(); }
						}
					}, t.label)
				]);
			}));
			dom.content(content, [ self.renderTab(activeMainTab, data) ]);
		}
		currentDraw = draw;
		draw();

		return container;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
