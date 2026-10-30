// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import { from_system_root, from_statvfs } from '../root/usr/share/rpcd/ucode/smartsafehub/apps-storage.uc';
function check(ok, message) {
	if (!ok) {
		warn(`FAIL: ${message}\n`);
		exit(1);
	}
};
let s = from_system_root({ total: 65536, avail: 40960 });
check(s?.mount == '/' && s?.totalBytes == 67108864 && s?.availableBytes == 41943040,
      'procd root stats must convert KiB to bytes');
check(from_system_root({ total: 500, avail: 501 }) == null, 'invalid root counters');
check(from_system_root({ total: '65536', avail: '40960' }) == null, 'reject string counters');
check(from_system_root({ total: 9007199254740991, avail: 1 }) == null, 'reject integer overflow');
check(from_system_root(null) == null, 'missing procd statistics must be optional');
check(from_system_root({ total: 42, avail: 0 })?.availableBytes == 0, 'allow a full filesystem');
let t = from_statvfs({ frsize: 4096, blocks: 20000, bavail: 13000 }, '/overlay');
check(t?.totalBytes == 81920000 && t?.availableBytes == 53248000, 'statvfs basic units');
check(from_statvfs({ frsize: 0, bsize: 4096, blocks: 20000, bavail: 0 }, '/')?.availableBytes == 0,
      'fall back to bsize if frsize is zero');
check(from_statvfs({ frsize: 4096, blocks: 20000, bavail: 20001 }, '/') == null,
      'reject invalid available blocks');
check(from_statvfs({ frsize: 4096, blocks: 20000, bavail: 1 }, '/tmp') == null,
      'must never use tmpfs instead of APK storage');
check(from_statvfs(null, '/overlay') == null, 'missing statvfs stats must be optional');
print('PASS: Apps storage procd and ucode statvfs conversions\n');
