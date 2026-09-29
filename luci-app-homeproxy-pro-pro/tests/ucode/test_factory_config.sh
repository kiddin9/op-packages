#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The factory configuration must be readable by the Loader.
#
# root/etc/config/homeproxy ships as the package conffile and is what every
# fresh install starts from, but nothing ever read it: the form tests render
# against their own fixtures, the generator tests stage a fixture, and the two
# factory-ish UCI files were only ever checked by eye. A typo in a section name
# or an option the Loader looks for under a different name would ship to every
# new install and only show up as a form full of defaults.
#
# tests/json-assets.js validates the file's grammar; this drives it through the
# real Loader, which is what actually consumes it.
#
# Usage: sh tests/ucode/test_factory_config.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-factory-config}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK/scripts" "$WORK/cfg"

cp -R "$ROOT/root/etc/homeproxy/scripts/." "$WORK/scripts/"
# The factory config is the UCI file itself; the Loader reads <dir>/homeproxy.
cp "$ROOT/root/etc/config/homeproxy" "$WORK/cfg/homeproxy"

FAILED=0
if ucode -L "$WORK/scripts" -L "$WORK" -e '
	import { Loader } from "'"$WORK"'/scripts/config/loader.uc";

	const dm = Loader.load("'"$WORK"'/cfg");
	const g = dm.general || {};

	let checks = 0, failures = 0;
	function expect(name, got, want) {
		checks++;
		if (sprintf("%J", got) === sprintf("%J", want)) return;
		failures++;
		printf("FAIL %s: expected %J, got %J\n", name, want, got);
	}

	/* Values that are actually written in root/etc/config/homeproxy. If one of
	 * them changes, this test changes with it - the point is that the Loader
	 * reads the shipped file at all, not that these particular defaults are
	 * permanent. */
	expect("main.routing_mode", g.routing_mode, "bypass_mainland_china");
	expect("main.proxy_mode", g.proxy_mode, "redirect_tproxy");
	expect("main.main_node", g.main_node, "nil");
	expect("main.main_udp_node", g.main_udp_node, "same");
	expect("main.log_level", g.log_level, "warn");

	/* Values that come from OTHER sections of the same file.  Asserting only
	 * that `dm.routing` exists is vacuous - the Loader always builds the
	 * object, from defaults when the section is missing - so a renamed section
	 * slipped straight through the first version of this test.  Reading an
	 * actual value through each section is what makes the rename visible. */
	expect("routing.settings.default_outbound",
		dm.routing.settings.default_outbound, "direct-out");
	expect("routing.settings.default_outbound_dns",
		dm.routing.settings.default_outbound_dns, "default-dns");
	expect("routing.settings.find_neighbor",
		dm.routing.settings.find_neighbor, "0");
	expect("dns.settings.default_strategy",
		dm.dns.settings.default_strategy, "prefer_ipv4");
	expect("dns.settings.default_server",
		dm.dns.settings.default_server, "default-dns");
	expect("access_control.control.lan_proxy_mode",
		dm.access_control.control.lan_proxy_mode, "disabled");
	expect("access_control.wan_proxy_ipv4_ips is non-empty",
		length(dm.access_control.wan_proxy_ipv4_ips) > 0, true);

	/* The shipped default must not already point at a node. */
	expect("main.main_node is nil", dm.general.main_node, "nil");

	printf("factory config: %d checks, %d failures\n", checks, failures);
	exit(failures ? 1 : 0);
'; then
	echo "PASS: the factory configuration loads through the Loader"
else
	echo "FAIL: the factory configuration does not load through the Loader"
	FAILED=1
fi

rm -rf "$WORK"
exit $FAILED
