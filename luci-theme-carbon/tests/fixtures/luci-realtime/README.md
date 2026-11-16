# LuCI realtime graph fixtures

Files copied from OpenWrt LuCI's `openwrt-24.10` branch at
[`aa4865e8e6472d6ba68e541688065fc2235bbd83`](https://github.com/openwrt/luci/tree/aa4865e8e6472d6ba68e541688065fc2235bbd83/modules/luci-mod-status/htdocs/luci-static/resources):

- `view/status/{load,bandwidth,connections}.js`
- `svg/{load,bandwidth,connections}.svg`

Only trailing whitespace has been removed; the upstream code is otherwise unchanged.

The browser regression executes the original `updateGraph()` and `pollData()`
methods with simulated RPC replies. Only the unrelated connection table update
is stubbed. This retains the fixed-width drawing behavior behind issue #8,
including subsequent polls overwriting the SVG points. These fixtures are test
inputs only and are never installed on the router.
