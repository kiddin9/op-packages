# RMM LuCI dashboard

`luci-app-rmm-dashboard` adds **Status в†’ RMM**. It reads router
identity, uptime, load, memory, WAN interface state, and the local RMM agent
service through read-only ubus calls. The page refreshes every 30 seconds.
The WAN value is link state, not an Internet reachability test.

The package works with either the RMM or the default LuCI theme and has no hard dependency on the RMM agent. It does not change OpenWrt configuration.

After installing, open **Status в†’ RMM**. If values show
**Unavailable**, check the LuCI session's read permissions and the router's
ubus services. Agent configuration remains under **Services в†’ RMM agent**.


Version 0.8.0 improvements: local dashboard block order/visibility and compact mode,
1/5/15-minute in-page history, DHCP-only clients with explicitly unconfirmed
connection evidence, health detail actions, compact secondary network branches,
and native LuCI DOM regression tests. See the repository README for usage,
limits and the GitHub Actions responsive matrix. Passive FDB/ARP/NDP collection
uses the read-only `rmm.dashboard.clients` RPC and `ucode-mod-rtnl`; it does not
probe clients or write router configuration. See the repository README for
port/state semantics, dependency installation and read-only verification.
