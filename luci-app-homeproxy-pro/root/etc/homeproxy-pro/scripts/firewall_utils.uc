/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Field validators for the nftables statements firewall_post.ut renders.
 *
 * Why this module exists: every UCI value the template concatenates into an
 * nft expression is an injection surface.  A malformed entry closes a set
 * expression with `}`, and the next thing nft sees is whatever the attacker
 * put after it - up to and including `accept` for a chain that should be a
 * drop, or a `reject` outside any chain that the fw4 reload fails to
 * compile, taking the whole router firewall with it.  The homeproxy-pro section
 * in /etc/config/homeproxy-pro is UCI-writable from the subscription updater,
 * from any shell on the LAN and from any cron job the user has not locked
 * down; `tests/ucode/test_firewall_validators.uc` covers that the helpers
 * drop these inputs rather than letting them through, and `tests/arch-guard.sh`
 * guard 11 covers that firewall_post.ut routes every field of these families
 * through the helpers.
 *
 * Each helper returns a defensive shape:
 *   - null when the input was empty or every entry was rejected
 *   - otherwise `{ v1, v2, ... }` (the nftables anonymous-set spelling)
 * so the template can plug the result into a statement unchanged.  Invalid
 * entries are dropped, matching the IPv6 helper's behaviour so the IPv4
 * path is finally as defensive as the IPv6 path was.
 *
 * No logging on the drop path: utpl templates render to stdout, and any
 * print() here would inject text into the nft ruleset.  If a debug trail
 * is ever wanted, do it from the template itself, not from these helpers.
 */

'use strict';

/* isEmpty() lives in homeproxy-pro.uc, not in the ucode globals.  Without this
 * import every helper below threw "access to undeclared variable isEmpty" the
 * moment it was called, which no host-side test caught because the test
 * harness stages its own stand-in module. */
import { isEmpty } from './homeproxy-pro.uc';

/* IPv4 (with optional /CIDR) - the regex is the standard four-octet body
 * followed by an optional /0..32.  Anything outside that - "1.2.3.4.5",
 * "1.2.3", " 1.2.3.4 ", "1.2.3.4 " - is rejected.
 *
 * Spelled out as one literal rather than built with `new RegExp(...)`: ucode
 * has no `new` keyword, so the constructor form was a compile error
 * ("Unexpected token") and the module never loaded.  The capture groups are
 * plain `(...)` because ucode regexes go through POSIX regcomp(), which has
 * no `(?:...)` non-capturing group; nothing here reads the captures, so the
 * extra ones are harmless. */
const IPV4_CIDR_RE = /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\/(3[0-2]|[12]?[0-9]))?$/;

export function isValidIPv4(s) {
	if (!s || type(s) !== 'string')
		return false;
	return !!match(s, IPV4_CIDR_RE);
};

export function ipv4_to_nftarr(list) {
	if (isEmpty(list))
		return null;

	let out = [];
	for (let ip in list) {
		if (isValidIPv4(ip))
			push(out, ip);
	}

	return isEmpty(out) ? null : `{ ${join(', ', uniq(out))} }`;
};

/* MAC address: six colon-separated hex octets, case-insensitive. */
const MAC_RE = /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/;

export function isValidMAC(s) {
	if (!s || type(s) !== 'string')
		return false;
	return !!match(s, MAC_RE);
};

export function mac_to_nftarr(list) {
	if (isEmpty(list))
		return null;

	let out = [];
	for (let m in list) {
		if (isValidMAC(m))
			push(out, m);
	}

	return isEmpty(out) ? null : `{ ${join(', ', uniq(out))} }`;
};

/* Linux interface names: alnum, dot, underscore, hyphen.  Anything that
 * would survive `ip link show` parsing is accepted here. */
const IFACE_RE = /^[A-Za-z0-9._-]+$/;

export function isValidIface(s) {
	if (!s || type(s) !== 'string')
		return false;
	return !!match(s, IFACE_RE);
};

export function iface_to_nftarr(list) {
	if (isEmpty(list))
		return null;

	let out = [];
	for (let i in list) {
		if (isValidIface(i))
			push(out, i);
	}

	return isEmpty(out) ? null : `{ ${join(', ', uniq(out))} }`;
};

/* Routing-port validator.  UCI delivers routing_port as a comma-separated
 * string ('22,53,80,443,...'), so we split first and then validate each
 * piece as a single port.  The old template did `split(routing_port, ',')`
 * and `join(', ', ...)` directly: an entry like '7890; reject' or '22,foo'
 * would land verbatim in an nft inet_service set. */
const PORT_RE = /^[0-9]+$/;

export function isValidPort(s) {
	if (!s || type(s) !== 'string')
		return false;
	if (!match(s, PORT_RE))
		return false;
	const n = +s;
	/* Port 0 is not a port: nft rejects `th dport 0` and `redirect to :0`, and a
	 * ruleset that carries one is rolled back as a whole by fw4.  The callers
	 * use this as "the value is usable", so 0 has to be a rejection. */
	return n >= 1 && n <= 65535;
};

export function ports_to_nftarr(s) {
	if (isEmpty(s) || type(s) !== 'string')
		return null;

	let out = [];
	for (let p in split(s, ',')) {
		const t = trim(p);
		if (isValidPort(t))
			push(out, t);
	}

	return isEmpty(out) ? null : `{ ${join(', ', uniq(out))} }`;
};
