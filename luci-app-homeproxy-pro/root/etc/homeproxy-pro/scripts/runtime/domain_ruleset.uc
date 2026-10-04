#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     runtime/domain_ruleset.uc <source .txt> <destination .json>
 *
 * The domain-list counterpart of china_ip_ruleset.uc: turn a bare host-name
 * list into a sing-box source rule-set of `domain_suffix` rules, so the DNS
 * side of the China split reads a local file instead of downloading
 * geosite-geolocation-cn.srs from GitHub on a schedule.
 *
 * Why this exists, in the terms that decided it: the two consumers of the
 * China split - the nft mainland set and the sing-box rule-set - were reading
 * two different files. The kernel's came from china_ip4.txt, the resolver's
 * from a remote .srs, and the remote copy is what a cold start has to wait for
 * (through the node, when download_detour says so) before the inbounds bind.
 * With the local copy there is nothing to wait for and nothing to keep in step.
 *
 * The entry is a suffix, not an exact domain: china_list.txt holds registrable
 * domains ("163.com", "taobao.com"), and the DNS rule has to match every name
 * under them, which is what `domain_suffix` means to sing-box. `domain` would
 * match only the name itself and quietly stop matching www.<domain> for the
 * entire list.
 *
 * One rule holding the whole list, for the same reason china_ip_ruleset.uc
 * gives: sing-box matches rule-sets by walking a prefix-compressed structure,
 * and splitting the list would only add rules to walk per query.
 *
 * Entries are validated here rather than trusted. The strict parser on the
 * other side is the authority for what a valid name is, and one bad entry
 * makes it reject the *whole* rule-set - which would take the client's start
 * with it. A malformed line is skipped and reported, exactly like the blank
 * lines and comments a list may carry.
 */
'use strict';
import { readfile, writefile, rename, unlink } from 'fs';

if (length(ARGV) < 2 || ARGV[0] == null || ARGV[1] == null) {
	warn(sprintf('usage: domain_ruleset.uc <source .txt> <destination .json>\n'));
	exit(1);
}
const src = ARGV[0];
const dst = ARGV[1];
const data = readfile(src);
if (type(data) !== 'string') {
	warn(sprintf('cannot read %s\n', src));
	exit(1);
}

const suffixes = [];
let skipped = 0;

/* A structural hostname check, in process.
 *
 * validation() from homeproxy-pro.uc is the obvious tool and the wrong one here:
 * it shells out to /sbin/validate_data once per call, and this list is 111k
 * lines. That is 111k process spawns. china_ip_ruleset.uc makes the same call
 * for the same reason - its is_v4/is_v6 are hand-written rather than delegated.
 *
 * Deliberately structural, not exhaustive: the goal is to keep a line that
 * cannot be a domain out of the file, since one bad entry makes sing-box reject
 * the whole rule-set and take the client's start with it. The strict parser on
 * the other side stays the authority for what is really valid. */
function is_hostname(entry) {
	if (length(entry) < 1 || length(entry) > 253)
		return false;

	/* Anything outside this set is a path, a URL, a port, an email, or a
	 * comment marker that survived the updater's filter. */
	if (!match(entry, /^[A-Za-z0-9.-]+$/))
		return false;

	/* A leading dot, a doubled dot, or a trailing dot all mean the list is
	 * not in the bare form this emits; sing-box treats them differently from
	 * what the DNS rule expects to match. */
	if (substr(entry, 0, 1) == '.' || substr(entry, -1, 1) == '.')
		return false;
	if (match(entry, /\.\./))
		return false;

	for (let label in split(entry, '.')) {
		if (length(label) < 1 || length(label) > 63)
			return false;
		/* A label may not start or end with a hyphen (RFC 1035). */
		if (substr(label, 0, 1) == '-' || substr(label, -1, 1) == '-')
			return false;
	}

	/* An all-numeric set of labels is a bare IPv4 address, not a domain:
	 * the structure above accepts "192.168.1.1" quite happily, and a
	 * domain_suffix rule holding an address never matches a query.  No TLD
	 * is all digits, so this cannot cost a real name.  IPv6 never reaches
	 * here at all - it carries colons and was rejected above. */
	let all_numeric = true;
	for (let label in split(entry, '.')) {
		if (!match(label, /^[0-9]+$/)) {
			all_numeric = false;
			break;
		}
	}
	if (all_numeric)
		return false;

	return true;
}

for (let line in split(data, /\n/)) {
	const entry = trim(line);
	if (entry == '')
		continue;
	if (match(entry, /^[#;]/))
		continue;

	/* The updater already strips `full:` prefixes and anything with a colon
	 * (update_resources.sh's china_list case), so what arrives here is a bare
	 * name. Anything that is not still a hostname is dropped rather than
	 * passed on. */
	if (!is_hostname(entry)) {
		skipped++;
		continue;
	}
	push(suffixes, entry);
}

if (skipped > 0)
	warn(sprintf('skipped %d malformed entries in %s\n', skipped, src));

/* An empty rule-set is worse than no rule-set: it matches nothing, so every
 * name the list should have covered falls through to whatever the DNS side
 * defaults to. Refuse rather than install one - the previous file stays. */
if (length(suffixes) == 0) {
	warn(sprintf('no usable domain entries in %s\n', src));
	exit(1);
}

/* The temporary name is a sibling so the rename stays on one filesystem: the
 * watcher must never read a half-written file. `%.J` is the same serializer
 * the config generator uses, so the output is the canonical sing-box form. */
const rendered = sprintf('%.J\n', {
	version: 3,
	rules: [
		{ domain_suffix: suffixes }
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

printf('%d domain suffixes\n', length(suffixes));
