#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Print a file's git blob id: sha1("blob <byte-length>\0" + content).
 *
 * That is the identifier GitHub reports for a path in a commit (the `.sha`
 * field of the contents API), so the resource updater can check that the bytes
 * it just downloaded are the bytes that commit contains. The download URL is
 * already pinned to a commit, which is a guarantee about *where* the bytes
 * come from, not about their content - a mirror, a CDN edge or anything else
 * between the router and it can answer for that URL with something else.
 *
 * It lives in its own file rather than as a few lines inside
 * update_resources.sh because the shell has no SHA-1: the target's busybox
 * ships sha256sum but not sha1sum, and the GitHub API only offers SHA-1 blob
 * ids. ucode-mod-digest is already a package dependency (md5() is used by the
 * subscription updater), so this adds no new requirement.
 *
 * Usage: ucode -S resource_blob_sha.uc <file>
 * Prints the hex digest and exits 0, or writes a message to stderr and exits 1.
 *
 * The failures use warn() + exit(1) rather than die(): on the target's ucode
 * (2026.01.16) die() exits 254, and the caller's contract is "nothing on stdout
 * means cannot verify", so a predictable status is worth having for anything
 * that does look at it.
 */

'use strict';

import { sha1 } from 'digest';
import { readfile } from 'fs';

if (!length(ARGV) || ARGV[0] == null) {
	warn('usage: resource_blob_sha.uc <file>\n');
	exit(1);
}

const data = readfile(ARGV[0]);

/* readfile() returns null when the file cannot be read and '' for an empty
 * one. The empty file has a real blob id (e69de29b...), so the two must not be
 * conflated - and neither may be reported as a digest. */
if (type(data) !== 'string') {
	warn(sprintf('cannot read %s\n', ARGV[0]));
	exit(1);
}

/* length() counts bytes, which is what git hashes; chr(0) is the NUL git puts
 * between the header and the content. */
printf('%s\n', sha1(sprintf('blob %d', length(data)) + chr(0) + data));
