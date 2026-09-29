#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Exceptional-path test for executeCommand(): the copy of homeproxy.uc staged
 * next to this file has its `system()` call replaced by `die()`, so every call
 * throws before the descriptors are read. ucode has no `finally`, so this
 * checks that the catch block still closes both descriptors.
 */

'use strict';

import { lsdir } from 'fs';
import { executeCommand } from 'homeproxy';

let failures = 0;

function fd_count() {
	let n = 0;
	for (let _entry in lsdir('/proc/self/fd'))
		n++;
	return n;
}

const before = fd_count();
let caught = 0;

for (let i = 0; i < 50; i++) {
	try {
		executeCommand('true');
	} catch (e) {
		caught++;
	}
}

const after = fd_count();

if (caught !== 50) {
	printf('FAIL: expected 50 propagated exceptions, got %d\n', caught);
	failures++;
}

if (after > before) {
	printf('FAIL descriptor leak on the exceptional path: %d -> %d\n', before, after);
	failures++;
}

if (failures === 0)
	printf('PASS: injected failure propagated and both descriptors were closed\n');

exit(failures === 0 ? 0 : 1);
