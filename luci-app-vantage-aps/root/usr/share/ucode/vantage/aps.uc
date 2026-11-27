// luci-app-vantage-aps: the pairing codes and the access points' reports,
// checked one way for luci.vantage.pair and the collector.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Codes, one line each, fields apart by blanks:
//
//   vantage-router 1 ssh-ed25519 <key> <name>                 (router -> AP)
//   vantage-ap 1 ssh-ed25519 <host key> <addr> <port> <mac> <name>   (AP -> router)
//
// <key> is the base64 of an Ed25519 public key blob and nothing else.

'use strict';

const MAX_APS = 16;        // per router
const MAX_ROUTERS = 8;     // per access point
const MAX_CODE = 512;      // bytes of a pasted code
const MAX_NET = 64;        // bytes of a network's name

const ED25519 = 'ssh-ed25519';
const BLOB_HEAD = '\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20';
const RE_KEY = /^AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+\/]{43}$/;
const RE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;
const RE_NOT_NAME = /[^A-Za-z0-9._-]/g;
const RE_LEAD = /^[^A-Za-z0-9]+/;
const RE_ID = /^[0-9a-f]{16}$/;
const RE_IPV4 = /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/;
const RE_IPV6 = /^[0-9a-f:]{2,39}$/;
const RE_GROUP = /^[0-9a-f]{1,4}$/;
const RE_PORT = /^[0-9]{1,5}$/;
const RE_SPACE = /[ \t\r\n]+/;
const RE_MAC = /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/;
const RE_NETDEV = /^[A-Za-z0-9_.-]{1,15}$/;
const RE_NET = /^[A-Za-z0-9_]+$/;

const MAX_SSIDS = 16;
const MAX_STATIONS = 256;
const MAX_WIRED = 128;
const MAX_PORTS = 32;
const MAX_OWN = 64;        // of an access point's own addresses
const MAX_BYTES = 0x7fffffffffffffff;
const MAX_STEP = 0x10000000000;   // bytes between two reports that still make a rate (1 TiB)

/* ------------------------------------------------------------ fields */

// a string without a NUL byte: ucode matches a regular expression against
// the bytes before the first one only, so "name\0anything" would pass as
// "name"
function str(v) {
	return type(v) == 'string' && index(v, "\x00") < 0;
}

// an Ed25519 public key blob in base64: exactly 51 bytes, its header ours
function key(v) {
	if (!str(v) || !match(v, RE_KEY))
		return null;

	let b = b64dec(v);

	return (type(b) == 'string' && length(b) == 51 && substr(b, 0, 19) == BLOB_HEAD) ? v : null;
}

function name(v) {
	return (str(v) && match(v, RE_NAME)) ? v : null;
}

// a hostname as a code's name: what a name may not hold becomes '-'
function name_of(host, fallback) {
	let n = str(host) ? substr(replace(replace(host, RE_NOT_NAME, '-'), RE_LEAD, ''), 0, 63) : '';

	return name(n) ?? fallback;
}

function id(v) {
	return (str(v) && match(v, RE_ID)) ? v : null;
}

function ipv4(v) {
	let m = match(v, RE_IPV4);

	if (!m)
		return false;

	for (let i = 1; i <= 4; i++)
		if (+m[i] > 255 || (length(m[i]) > 1 && substr(m[i], 0, 1) == '0'))
			return false;

	// unicast, not 0/8, loopback nor link-local
	return +m[1] >= 1 && +m[1] <= 223 && +m[1] != 127 && !(+m[1] == 169 && +m[2] == 254);
}

// an IPv6 address, lower case -> its eight groups, :: filled in; null
// when it is none
function groups6(v) {
	if (!match(v, RE_IPV6) || index(v, ':::') >= 0)
		return null;

	let parts = split(v, '::'), sides = [ [], [] ];

	if (length(parts) > 2)
		return null;

	for (let k = 0; k < length(parts); k++) {
		if (parts[k] == '')
			continue;

		for (let g in split(parts[k], ':')) {
			if (!match(g, RE_GROUP))
				return null;

			push(sides[k], hex(g));
		}
	}

	let n = length(sides[0]) + length(sides[1]);

	if ((length(parts) == 2) ? n > 7 : n != 8)
		return null;

	let groups = [ ...sides[0] ];

	for (let k = n; k < 8; k++)
		push(groups, 0);

	return [ ...groups, ...sides[1] ];
}

function ipv6(v) {
	// judged by value, however spelled
	let groups = groups6(v);

	// ::/8 holds no host to reach (unspecified, loopback, IPv4-mapped);
	// link-local needs a zone, multicast is no host
	return groups != null && groups[0] >= 0x100 && (groups[0] & 0xffc0) != 0xfe80 && groups[0] < 0xff00;
}

// an address to reach an access point at: unicast IPv4, or IPv6 without
// brackets or zone
function addr(v) {
	if (!str(v))
		return null;

	v = lc(v);

	return (ipv4(v) || ipv6(v)) ? v : null;
}

// a unicast MAC, lower case
function mac(v) {
	v = str(v) ? lc(v) : null;

	return (v && match(v, RE_MAC) && v != '00:00:00:00:00:00' && !(hex(substr(v, 0, 2)) & 1)) ? v : null;
}

function netdev(v) {
	return (str(v) && match(v, RE_NETDEV)) ? v : null;
}

// one of this device's networks by its name ("lan"): netifd names an
// interface after its section in /etc/config/network, and uci takes
// letters, digits and '_' in a section's name. The length is counted
// here: the report loads this file on every run, and a counted repeat
// costs musl milliseconds to compile
function net(v) {
	return (str(v) && length(v) <= MAX_NET && match(v, RE_NET)) ? v : null;
}

function port(v) {
	if (str(v) && match(v, RE_PORT))
		v = +v;

	return (type(v) == 'int' && v >= 1 && v <= 65535) ? v : null;
}

/* ------------------------------------------------------------- codes */

function fields(s) {
	return (str(s) && length(s) <= MAX_CODE) ? split(trim(s), RE_SPACE) : [];
}

function router_code(k, n) {
	return join(' ', [ 'vantage-router', '1', ED25519, k, n ]);
}

function ap_code(k, a, p, m, n) {
	return join(' ', [ 'vantage-ap', '1', ED25519, k, a, '' + p, m, n ]);
}

// { key, name } or null
function parse_router(s) {
	let f = fields(s);

	if (length(f) != 5 || f[0] != 'vantage-router' || f[1] != '1' || f[2] != ED25519 || !key(f[3]) || !name(f[4]))
		return null;

	return { key: f[3], name: f[4] };
}

// { key, addr, port, mac, name } or null; mac: the access point's LAN
// MAC, by which the router finds it again when its address changes
function parse_ap(s) {
	let f = fields(s);

	if (length(f) != 8 || f[0] != 'vantage-ap' || f[1] != '1' || f[2] != ED25519 || !key(f[3]) ||
	    !addr(f[4]) || !port(f[5]) || !mac(f[6]) || !name(f[7]))
		return null;

	return { key: f[3], addr: addr(f[4]), port: port(f[5]), mac: mac(f[6]), name: f[7] };
}

/* --------------------------------------------- a router's key line */

// What a router's key may do on an access point: run the report, and
// nothing else. The line's comment names the router and its key (the
// first 8 of the key's 32 bytes, in hex): Dropbear hands the comment of
// the line that let a caller in to the command it runs (SSH_PUBKEYINFO,
// the first word of it, of letters, digits and .,_-+@ only), and the
// report looks for that line again.
const KEY_OPTIONS = 'command="/usr/libexec/vantage/report",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding';
const COMMENT = 'vantage-router@';
const RE_TAIL = /[ \r]+$/;

function key_id(k) {
	let b = b64dec(k), h = '';

	for (let i = 19; i < 27; i++)
		h += sprintf('%02x', ord(b, i));

	return h;
}

// the authorized_keys line for router key k, named n (both checked by
// the caller: key(), name())
function auth_line(k, n) {
	return KEY_OPTIONS + ' ssh-ed25519 ' + k + ' ' + COMMENT + n + '+' + key_id(k);
}

// such a line back: { key, name, comment }, or null for any other line.
// Blanks or a carriage return after it (an editor's) leave it that line:
// Dropbear takes it all the same, and names it by the same comment. Not
// a tab: with one, Dropbear names no comment at all to the report.
function parse_auth_line(line) {
	let f = str(line) ? split(replace(line, RE_TAIL, ''), ' ') : [];

	if (length(f) != 4 || f[0] != KEY_OPTIONS || f[1] != ED25519 || !key(f[2]) || substr(f[3], 0, length(COMMENT)) != COMMENT)
		return null;

	let rest = split(substr(f[3], length(COMMENT)), '+');

	return (length(rest) == 2 && name(rest[0]) && rest[1] === key_id(f[2])) ? { key: f[2], name: rest[0], comment: f[3] } : null;
}

// Dropbear's options as it reads them (svr-runopts.c, 2025.89): a word
// after the program is a "-" and one or more option letters. Those of
// DROPBEAR_VALUE take a value, which ends the word: the rest of that
// word, or else the whole next word. The others take none.
const DROPBEAR_VALUE = 'bcdrDpPlGWKITA2';
const DROPBEAR_FLAG = 'aBeEFghijkmRstuvVwz';

// Whether a dropbear command line (argv: the program, then its words)
// takes root and runs a command of its own: a c among its options (uci's
// ForceCommand) and no w (RootLogin off), read the way dropbear reads
// them, letters in one word and a value in the same word included
// ("-Fsc x", "-c/bin/x"). A value is never read as options: it is
// passed over with the option that takes it (a pid file, a port, an
// interface, the command itself). A line dropbear itself would refuse
// (a word that is no option, a letter it does not have, a value that is
// missing) cannot be read, and counts: what runs there is not known.
function own_command(argv) {
	let own = false, root = true;

	for (let i = 1; i < length(argv); i++) {
		let word = argv[i];

		if (type(word) != 'string' || length(word) < 2 || substr(word, 0, 1) != '-')
			return true;

		for (let j = 1; j < length(word); j++) {
			let o = substr(word, j, 1);

			if (index(DROPBEAR_VALUE, o) >= 0) {
				if (o == 'c')
					own = true;

				if (j == length(word) - 1 && ++i >= length(argv))
					return true;

				break;
			}

			if (index(DROPBEAR_FLAG, o) < 0)
				return true;

			if (o == 'w')
				root = false;
		}
	}

	return own && root;
}

// Whether a dropbear listener procd runs takes root and runs a command
// of its own (services: ubus service list, all of it). Dropbear runs
// that for every key that logs in there, a router's too, in place of
// the report its key line names, and every listener reads the same
// authorized_keys. Every running instance whose program is a dropbear
// (the last part of its path) is one, whatever its service is called.
// A running instance whose command cannot be read counts: what it runs
// is not known.
function forced_listener(services) {
	for (let name, s in ((type(services) == 'object') ? services : {}))
		for (let n, i in ((type(s) == 'object' && type(s.instances) == 'object') ? s.instances : {})) {
			if (type(i) != 'object' || i.running !== true)
				continue;

			let argv = i.command, prog = (type(argv) == 'array' && type(argv[0]) == 'string') ? split(argv[0], '/') : null;

			if (!prog || (prog[-1] == 'dropbear' && own_command(argv)))
				return true;
		}

	return false;
}

/* ------------------------------------------------- the paired list */

// /etc/vantage/aps.json -> [ { id, name, key, addr, port, mac } ], the valid
// entries only, at most MAX_APS, each id and key once. An entry may name
// the network it was paired on (net: net_of() its address then). One
// without is an entry all the same (made by an earlier version, or
// paired at an address of none of this router's networks); one whose
// net is no such name is no entry. whole: for the one who writes the
// list back. Then null unless the text is blank or a list of which
// every entry is taken: written back, a list that was edited by hand
// would lose whatever did not pass.
function aps(text, whole) {
	let list = null, out = [], ids = {}, keys = {}, all = true;

	try {
		list = (type(text) == 'string') ? json(text) : null;
	}
	catch (e) {
		list = null;
	}

	if (type(list) != 'array')
		return (whole && !(type(text) == 'string' && trim(text) == '')) ? null : out;

	for (let a in list) {
		let e = (type(a) == 'object' && length(out) < MAX_APS)
			? { id: id(a.id), name: name(a.name), key: key(a.key), addr: addr(a.addr), port: port(a.port), mac: mac(a.mac) } : null;
		let named = e != null && exists(a, 'net');

		if (named)
			e.net = net(a.net);

		if (!e || !e.id || !e.name || !e.key || !e.addr || !e.port || !e.mac || (named && !e.net) || ids[e.id] || keys[e.key]) {
			all = false;
			continue;
		}

		ids[e.id] = keys[e.key] = true;
		push(out, e);
	}

	return (whole && !all) ? null : out;
}

// The network an address is on, of this device's own (ifaces: the
// interfaces of ubus network.interface dump): { dev, nets }, the device
// of the one interface with a subnet that holds the address, and that
// interface's IPv4 subnets as [ address, mask ] pairs. null when no
// interface holds it (an access point behind another router).
// net_of(): that interface's name, which a pairing keeps;
// network_named(): the network of that name as it is now.
function v4(a) {
	let m = str(a) ? match(a, RE_IPV4) : null;

	return (m && +m[1] <= 255 && +m[2] <= 255 && +m[3] <= 255 && +m[4] <= 255) ? [ +m[1], +m[2], +m[3], +m[4] ] : null;
}

// whether the first bits bits of two addresses (lists of numbers, width
// bits each) are the same
function same_net(x, y, bits, width) {
	for (let i = 0; i < length(x) && bits > 0; i++, bits -= width) {
		let drop = (bits >= width) ? 0 : width - bits;

		if ((x[i] >> drop) != (y[i] >> drop))
			return false;
	}

	return true;
}

function subnets(list, parse, most) {
	let out = [];

	for (let e in ((type(list) == 'array') ? list : [])) {
		let a = (type(e) == 'object' && str(e.address)) ? parse(lc(e.address)) : null;

		if (a && type(e.mask) == 'int' && e.mask >= 1 && e.mask <= most)
			push(out, [ a, e.mask ]);
	}

	return out;
}

// an interface of the dump as a network to look on; null while it is
// down or names no device
function place(i) {
	return (type(i) == 'object' && i.up === true && netdev(i.l3_device))
		? { dev: i.l3_device, nets: subnets(i['ipv4-address'], v4, 32) } : null;
}

// the interface of the dump an address is on, null when none holds it
function iface_of(a, ifaces) {
	let want4 = v4(a), want6 = want4 ? null : (str(a) ? groups6(lc(a)) : null);

	if (!want4 && !want6)
		return null;

	let best = null, most = 0;

	// the interface whose subnet holds it most narrowly, as the kernel
	// routes: an uplink's wide subnet around the LAN's is not the LAN
	for (let i in ((type(ifaces) == 'array') ? ifaces : [])) {
		let p = place(i);

		if (!p)
			continue;

		let held = want4
			? filter(p.nets, (n) => same_net(want4, n[0], n[1], 8))
			: filter([ ...subnets(i['ipv6-address'], groups6, 128), ...subnets(i['ipv6-prefix-assignment'], groups6, 128) ],
				(n) => same_net(want6, n[0], n[1], 16));

		for (let n in held) {
			if (n[1] > most) {
				most = n[1];
				best = i;
			}
		}
	}

	return best;
}

function network_of(a, ifaces) {
	return place(iface_of(a, ifaces));
}

// The name of the network an address is on ("lan"), for its pairing to
// keep: by it the network is known again after its subnet was changed.
// null when the address is on none, or on one whose name is no net().
function net_of(a, ifaces) {
	return net(iface_of(a, ifaces)?.interface);
}

// The network a pairing names (n: its net), as it is now: { dev, nets }
// of the interface of that name, whatever subnets it has by now. null
// when no interface has the name any more, or the one that has is down:
// nowhere is looked then, not on another network in its place.
function network_named(n, ifaces) {
	n = net(n);

	for (let i in ((type(ifaces) == 'array') ? ifaces : []))
		if (n && type(i) == 'object' && i.interface === n)
			return place(i);

	return null;
}

// The IPv4 addresses a MAC has now on the network it was paired on (net:
// network_named() its pairing's net, or network_of() its pairing address
// for a pairing that names none), where to look for an access point
// whose address changed: first what dnsmasq leased it ("<expiry> <mac>
// <ip> ...", one lease a MAC), then the neighbour table's complete
// entries (/proc/net/arp) on that network's device, each inside one of
// the network's subnets, at most four. Any device gets a row under any
// MAC and address into the neighbour table of a network it is on, so
// rows of other networks are not followed: this router would open a
// connection to wherever they say. The pinned host key turns away any
// other device at an address that is tried. skip: addresses that are
// left out before the four are counted (those already tried), so that
// rows and leases a device of that network made up under this MAC
// cannot keep the real one out for good.
function find_addrs(m, arp, leases, net, skip) {
	let out = [];

	m = mac(m);

	if (!m || type(net) != 'object' || !netdev(net.dev))
		return out;

	let inside = (a) => ipv4(a) && !skip?.[a] && length(filter(net.nets, (n) => same_net(v4(a), n[0], n[1], 8))) > 0;

	for (let line in split(str(leases) ? leases : '', '\n')) {
		let f = split(trim(line), RE_SPACE);

		if (length(f) >= 3 && mac(f[1]) == m && inside(f[2]) && index(out, f[2]) < 0)
			push(out, f[2]);
	}

	for (let line in split(str(arp) ? arp : '', '\n')) {
		let f = split(trim(line), RE_SPACE);

		if (length(f) >= 6 && (+f[2] & 2) && mac(f[3]) == m && f[5] === net.dev && inside(f[0]) && index(out, f[0]) < 0)
			push(out, f[0]);
	}

	return slice(out, 0, 4);
}

// The first address its MAC has now that is neither where it is known
// (current) nor already tried; null when there is none
function next_addr(m, current, tried, arp, leases, net) {
	let skip = { ...((type(tried) == 'object') ? tried : {}) };

	if (str(current))
		skip[current] = true;

	return find_addrs(m, arp, leases, net, skip)[0] ?? null;
}

// A file another program wrote, to be read as text: only a plain file
// (st: its lstat; a link would be followed, a pipe would hold the reader
// until someone writes to it) of root's or of the account uid.
function own_file(st, uid) {
	return type(st) == 'object' && st.type == 'file' && (st.uid === 0 || (type(uid) == 'int' && st.uid === uid));
}

/* ---------------------------------------------------- a fetch's outcome */

// a host key dbclient does not take, in its own words: its reason after
// " exited:", or its line "<type> host key mismatch for <host> !" (after
// an empty reason). A whole reason and a line's start: what the other
// end sent is quoted inside dbclient's exit line, never at a line's start
const HOSTKEY_WHY = [ 'Not accepted automatically', "Didn't validate host key" ];
const RE_MISMATCH = /^[a-z0-9@.-]+ host key mismatch for /;
const RE_EXITED = /^[^ ]+: Connection to [^ ]+$/;
const RE_NO_REPORT = /^-?[a-z\/]*sh: [^ ]*vantage\/report: (not found|No such file or directory|Permission denied)$/;
const NO_AUTH = 'No auth methods could be used.';

// Why dbclient gave up, in its own words: the text after " exited:" in
// its line "<program>: Connection to <user>@<host>:<port> exited: <why>";
// null when it wrote no such line (the session ran to its end). The first
// " exited:" of the line is dbclient's: whatever the other end sent can
// only follow it (its version line is quoted there before any key is
// checked) and holds no line break.
function exited(err) {
	for (let line in split(err, '\n')) {
		let i = index(line, ' exited:');

		if (i > 0 && match(substr(line, 0, i), RE_EXITED))
			return trim(substr(line, i + 8));
	}

	return null;
}

// Why a fetch gave no report, from how dbclient ended (its exit code, the
// bytes it printed, its error text, whether it was killed for taking too
// long); null when what it printed is to be read as a report (at most
// max bytes). 'missing': the access point has no report command (the
// add-on is not installed there).
//
// Only an access point that showed its pinned host key may be 'denied',
// 'missing' or 'invalid': those end the search for it at other addresses,
// and any device answers at an address it has left. Before the key is
// checked that device already has a say in dbclient's error text and exit
// code, so 'denied' is dbclient's one reason that comes after the check,
// word for word; 'missing' is a line of the access point's own shell,
// which only a session brings; 'invalid' needs bytes on standard output,
// which only a session brings too. Everything else was not the access
// point's answer.
function fetch_error(code, out, err, timedout, max) {
	if (timedout)
		return 'timeout';

	out = (type(out) == 'string') ? out : '';

	if (code == 0 && length(out) > 0 && length(out) <= max)
		return null;

	err = (type(err) == 'string') ? err : '';

	let why = exited(err);

	if (why != null && index(HOSTKEY_WHY, why) >= 0)
		return 'hostkey';

	for (let line in split(err, '\n'))
		if (match(line, RE_MISMATCH))
			return 'hostkey';

	if (why != null)
		return (why == NO_AUTH) ? 'denied' : 'unreachable';

	for (let line in split(err, '\n'))
		if (match(line, RE_NO_REPORT))
			return 'missing';

	return length(out) ? 'invalid' : 'unreachable';
}

// An access point's state on the dashboard: 'ok' with a report to show,
// 'offline' when the last fetch could not reach it, 'error' when it was
// refused or made no sense, 'waiting' before any fetch has ended
function state(shown, error) {
	return shown ? 'ok' : (error == 'unreachable' || error == 'timeout') ? 'offline' : error ? 'error' : 'waiting';
}

// After a fetch failed with error at an address: whether to look for the
// access point elsewhere (it is gone from there, or another device is)
function moved(error) {
	return error == 'unreachable' || error == 'timeout' || error == 'hostkey';
}

/* ----------------------------------------------------------- reports */

// A report's text, before json() reads it: json() builds every value it
// names before normalize() can drop one, and an empty object costs about
// 1.5 kB (128 KiB of "{}," took 66 MB). So the text may open at most
// MAX_OPEN objects and arrays and hold at most MAX_COMMAS commas, counted
// as bytes wherever they stand, in a string too. The fullest report an
// access point can make has 949 and 6676 since each station carries its
// link (#155) and each port the switch's counters (#156), and its free
// text (16 SSIDs, its name and model) could add 639 to either; the
// counts leave room for a field more. 2048 objects take json() about as
// much memory as that fullest report does (some 2.5 MB).
const MAX_OPEN = 2048;
const MAX_COMMAS = 8192;
const RE_NOT_OPEN = /[^[{]+/g;
const RE_NOT_COMMA = /[^,]+/g;

function parseable(text) {
	return str(text) &&
		length(replace(text, RE_NOT_OPEN, '')) <= MAX_OPEN &&
		length(replace(text, RE_NOT_COMMA, '')) <= MAX_COMMAS;
}

function int_in(v, lo, hi) {
	return (type(v) == 'int' && v >= lo && v <= hi) ? v : null;
}

// a station's link (the report's phy()), checked field by field
function phy(r) {
	if (type(r) != 'object')
		return null;

	return {
		mhz: int_in(r.mhz, 1, 640), mcs: int_in(r.mcs, 0, 31), nss: int_in(r.nss, 1, 16),
		ht: r.ht === true, vht: r.vht === true, he: r.he === true, eht: r.eht === true, sgi: r.sgi === true
	};
}

// well-formed UTF-8 without control characters, at most max bytes; else ''
function text(v, max) {
	if (type(v) != 'string' || length(v) > max)
		return '';

	let n = length(v), i = 0;

	while (i < n) {
		let b = ord(v, i), need = 0, lo = 0x80, hi = 0xbf;

		if (b < 0x20 || b == 0x7f)
			return '';

		if (b >= 0x80) {
			if (b >= 0xc2 && b <= 0xdf) need = 1;
			else if (b >= 0xe0 && b <= 0xef) { need = 2; lo = (b == 0xe0) ? 0xa0 : 0x80; hi = (b == 0xed) ? 0x9f : 0xbf; }
			else if (b >= 0xf0 && b <= 0xf4) { need = 3; lo = (b == 0xf0) ? 0x90 : 0x80; hi = (b == 0xf4) ? 0x8f : 0xbf; }
			else return '';

			for (let j = 1; j <= need; j++) {
				let c = (i + j < n) ? ord(v, i + j) : -1;

				if (c < ((j == 1) ? lo : 0x80) || c > ((j == 1) ? hi : 0xbf))
					return '';
			}
		}

		i += need + 1;
	}

	return v;
}

function band(freq) {
	if (type(freq) != 'int')
		return null;

	if (freq >= 2400 && freq < 2500) return '2g';
	if (freq >= 4900 && freq < 5935) return '5g';
	if (freq >= 5935 && freq <= 7125) return '6g';
	if (freq >= 57000 && freq <= 71000) return '60g';

	return null;
}

// an access point's report (/usr/libexec/vantage/report), field by field:
// what does not fit is left out, the caps hold whatever it sends. null
// when it is no report at all
function normalize(r) {
	if (type(r) != 'object' || r.v !== 1)
		return null;

	let out = {
		name: text(r.name, 63), model: text(r.model, 64),
		uptime: int_in(r.uptime, 0, 0x7fffffff), mac: mac(r.mac), macs: [],
		ssids: [], stations: [], ports: {}, wired: []
	};
	let ifs = {}, stas = {}, seen = {}, owns = {}, nports = 0;

	// its own addresses (#167); a report from before them has none
	for (let m in ((type(r.macs) == 'array') ? r.macs : [])) {
		if (length(out.macs) >= MAX_OWN)
			break;

		m = mac(m);

		if (!m || owns[m])
			continue;

		owns[m] = true;
		push(out.macs, m);
	}

	for (let s in ((type(r.ssids) == 'array') ? r.ssids : [])) {
		if (length(out.ssids) >= MAX_SSIDS)
			break;

		let i = (type(s) == 'object') ? netdev(s.ifname) : null;

		if (!i || ifs[i])
			continue;

		ifs[i] = true;
		push(out.ssids, { ifname: i, bssid: mac(s.bssid), ssid: text(s.ssid, 32),
			freq: int_in(s.freq, 1, 100000), channel: int_in(s.channel, 1, 255) });
	}

	for (let s in ((type(r.stations) == 'array') ? r.stations : [])) {
		if (length(out.stations) >= MAX_STATIONS)
			break;

		let m = (type(s) == 'object') ? mac(s.mac) : null, i = m ? netdev(s.ifname) : null;

		if (!i || stas[m] || !ifs[i])
			continue;

		stas[m] = true;
		push(out.stations, {
			mac: m, ifname: i,
			signal: int_in(s.signal, -120, -1),
			rx_rate: int_in(s.rx_rate, 1, 100000000), tx_rate: int_in(s.tx_rate, 1, 100000000),
			rx_bytes: int_in(s.rx_bytes, 0, MAX_BYTES), tx_bytes: int_in(s.tx_bytes, 0, MAX_BYTES),
			connected: int_in(s.connected, 0, 0x7fffffff),
			rx_phy: phy(s.rx_phy), tx_phy: phy(s.tx_phy)
		});
	}

	for (let p, v in ((type(r.ports) == 'object') ? r.ports : {})) {
		if (nports >= MAX_PORTS)
			break;

		if (!netdev(p) || type(v) != 'object' || !int_in(v.hosts, 1, MAX_WIRED))
			continue;

		// the switch chip's own counters (#156), both or neither; a
		// report from before them has none
		let hr = int_in(v.hw_rx_bytes, 0, MAX_BYTES), ht = int_in(v.hw_tx_bytes, 0, MAX_BYTES);

		out.ports[p] = { speed: int_in(v.speed, 1, 1000000), rx_bytes: int_in(v.rx_bytes, 0, MAX_BYTES),
			tx_bytes: int_in(v.tx_bytes, 0, MAX_BYTES), hosts: v.hosts,
			...((hr != null && ht != null) ? { hw_rx_bytes: hr, hw_tx_bytes: ht } : {}) };
		nports++;
	}

	// a host is wired or a station, never both; its MAC once
	for (let w in ((type(r.wired) == 'array') ? r.wired : [])) {
		if (length(out.wired) >= MAX_WIRED)
			break;

		let m = (type(w) == 'object') ? mac(w.mac) : null, p = m ? netdev(w.port) : null;

		if (!p || seen[m] || stas[m] || m == out.mac || !out.ports[p])
			continue;

		seen[m] = true;
		push(out.wired, { mac: m, port: p });
	}

	return out;
}

// bit/s between two byte counts dt seconds apart; null across a reset
function rate(now_b, prev_b, dt) {
	if (!(dt > 0) || type(now_b) != 'int' || type(prev_b) != 'int' || now_b < prev_b)
		return null;

	// more than a terabyte between two reports is no rate (and its bits
	// would not fit the multiplication)
	let d = now_b - prev_b;

	return (d <= MAX_STEP) ? int(d * 8 / dt) : null;
}

// a port's [ rx, tx ] bit/s between two reports: from the switch chip's
// counters where both carry them, from the kernel's where neither does,
// and none where one does and the other does not (#156): two sources
// never make one rate
function port_rate(p, q, dt) {
	let hw = (p.hw_rx_bytes != null);

	if (q && (q.hw_rx_bytes != null) != hw)
		return [ null, null ];

	return hw ? [ rate(p.hw_rx_bytes, q?.hw_rx_bytes, dt), rate(p.hw_tx_bytes, q?.hw_tx_bytes, dt) ]
		: [ rate(p.rx_bytes, q?.rx_bytes, dt), rate(p.tx_bytes, q?.tx_bytes, dt) ];
}

// what the dashboard gets of a report (normalize's), with rates against
// the one before it dt seconds earlier (dt 0: none yet)
function view(r, prev, dt) {
	let pst = {}, pport = (type(prev?.ports) == 'object') ? prev.ports : {};

	for (let x in (prev?.stations ?? []))
		pst[x.mac] = x;

	return {
		name: r.name, model: r.model, uptime: r.uptime, mac: r.mac, macs: r.macs,
		ssids: map(r.ssids, (x) => ({ ifname: x.ifname, bssid: x.bssid, ssid: x.ssid, freq: x.freq, channel: x.channel, band: band(x.freq) })),
		stations: map(r.stations, (x) => ({
			mac: x.mac, ifname: x.ifname, signal: x.signal, rxRate: x.rx_rate, txRate: x.tx_rate,
			rx: rate(x.rx_bytes, pst[x.mac]?.rx_bytes, dt), tx: rate(x.tx_bytes, pst[x.mac]?.tx_bytes, dt),
			connected: x.connected, rxPhy: x.rx_phy, txPhy: x.tx_phy
		})),
		// a port's traffic is its host's only when the host has it alone
		wired: map(r.wired, (x) => {
			let p = r.ports[x.port], q = pport[x.port], one = (p.hosts == 1), b = one ? port_rate(p, q, dt) : [ null, null ];

			return { mac: x.mac, port: x.port, speed: p.speed, rx: b[0], tx: b[1] };
		})
	};
}

export { MAX_APS, MAX_ROUTERS, MAX_CODE, COMMENT, key, name, name_of, id, addr, mac, net, port, router_code, ap_code, parse_router, parse_ap, auth_line, parse_auth_line, forced_listener, aps, network_of, net_of, network_named, find_addrs, next_addr, own_file, fetch_error, state, moved, band, parseable, normalize, view };
