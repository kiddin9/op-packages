#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Turn a plain CIDR list into a sing-box local rule-set, so the route side and
 * the firewall decide "is this destination mainland China" from the same bytes.
 *
 * The firewall's homeproxy_mainland_addr_v4 set is filled by firewall_post.ut
 * straight from /etc/homeproxy-pro/resources/china_ip4.txt, while the route rule
 * used the upstream geoip-cn.srs.  Those two disagree: the bundled list carries
 * 8.152.0.0/13 (Alibaba Cloud) which geoip-cn.srs does not, so a connection to
 * segmentfault.com or ctrip.com resolved into that range is redirected by the
 * firewall (not in the nft set) and then sent *direct* by the route rule (not
 * in geoip-cn.srs) - the opposite of what the mode promises.
 *
 * Reading the same text file on both sides removes the disagreement, and it
 * has to survive the resource updater replacing the list: the generated
 * rule-set is written with a local `type: local` entry in the client config,
 * which sing-box watches with fswatch, so replacing the file is enough - no
 * service restart, no second copy of the data.
 *
 * Usage: ucode -S china_ip_ruleset.uc <source .txt> <destination .json>
 * Exit 0 when the file was written, 1 (with a message on stderr) otherwise.
 * An unreadable or empty source is *not* an error: the caller may legitimately
 * have no list yet, and a missing rule-set file is handled by the generator
 * (it emits the local rule only when the file exists).
 */

'use strict';

import { readfile, writefile, rename, unlink } from 'fs';

if (length(ARGV) < 2 || ARGV[0] == null || ARGV[1] == null) {
	warn('usage: china_ip_ruleset.uc <source .txt> <destination .json>\n');
	exit(1);
}

const src = ARGV[0];
const dst = ARGV[1];

const data = readfile(src);
if (type(data) !== 'string') {
	warn(sprintf('cannot read %s\n', src));
	exit(1);
}

/* One `ip_cidr` array is one netipx.IPSet on the sing-box side, which is a
 * prefix-compressed structure with a binary search per query; splitting the
 * list into several rules would only add rules to walk per packet.
 *
 * The entries are validated here rather than trusted.  netip.ParsePrefix() is
 * what sing-box uses, it is strict (no leading zeros, no out-of-range octets),
 * and one bad entry makes it reject the *whole* rule-set - which would take
 * the client's start with it.  A malformed line is therefore skipped and
 * reported, exactly like the blank lines and comments a list may carry. */
function is_v4(addr) {
	const parts = split(addr, '.');
	if (length(parts) != 4)
		return false;
	for (let part in parts) {
		if (!match(part, /^[0-9]{1,3}$/))
			return false;
		/* Go's parser rejects "01"; match it so the file it accepts and
		 * the file we emit cannot disagree. */
		if (length(part) > 1 && substr(part, 0, 1) == '0')
			return false;
		if (int(part) > 255)
			return false;
	}
	return true;
}

function is_v6(addr) {
	/* Deliberately structural, not exhaustive: the point is to keep a
	 * malformed line out, and the strict parser on the other side is the
	 * authority for what a valid address is. */
	if (!match(addr, /^[0-9a-fA-F:]+$/))
		return false;
	if (!match(addr, /:/))
		return false;
	if (match(addr, /:::/))
		return false;
	return true;
}

function valid_cidr(entry) {
	const slash = index(entry, '/');
	if (slash <= 0)
		return false;
	const addr = substr(entry, 0, slash);
	const bits = substr(entry, slash + 1);
	if (!match(bits, /^[0-9]{1,3}$/))
		return false;
	if (is_v4(addr))
		return int(bits) <= 32;
	if (is_v6(addr))
		return int(bits) <= 128;
	return false;
}

const prefixes = [];
let skipped = 0;
for (let line in split(data, /\n/)) {
	const entry = trim(line);
	if (entry == '')
		continue;
	/* The updater's lists are bare CIDRs, but a stray comment or a host
	 * address must not make sing-box reject the whole rule-set at start. */
	if (match(entry, /^[#;]/))
		continue;
	if (!valid_cidr(entry)) {
		skipped++;
		continue;
	}
	push(prefixes, entry);
}

if (skipped > 0)
	warn(sprintf('skipped %d malformed entries in %s\n', skipped, src));

if (length(prefixes) == 0) {
	warn(sprintf('no usable CIDR entries in %s\n', src));
	exit(1);
}

/* The temporary name is a sibling so the rename stays on one filesystem: the
 * watcher must never read a half-written file.  `%.J` is the same serializer
 * the config generator uses, so the output is the canonical sing-box form. */
const rendered = sprintf('%.J\n', {
	version: 3,
	rules: [
		{ ip_cidr: prefixes }
	]
});

const tmp = dst + '.tmp';
if (!writefile(tmp, rendered)) {
	warn(sprintf('cannot write %s\n', tmp));
	exit(1);
}
if (!rename(tmp, dst)) {
	unlink(tmp);
	warn(sprintf('cannot install %s\n', dst));
	exit(1);
}

printf('%d prefixes\n', length(prefixes));
