# SafeShield (luci-app-safeshield)

![OpenWrt](https://img.shields.io/badge/OpenWrt-Compatible-blue)
![License](https://img.shields.io/github/license/Junatum/safeshield?label=License)

A lightweight DNS-based ad blocker for OpenWrt, designed with a powerful, easy-to-use Web UI. Blocks ads and phishing sites, fully compatible with dnsmasq.

## Build from source

`luci-app-safeshield` is a LuCI web interface package for SafeShield.
It depends on the main `safeshield` package, so both repositories should be available in the OpenWrt buildroot or SDK when building from source.

### Build with OpenWrt buildroot

Clone OpenWrt and prepare the build environment:

```sh
cd /opt/build

git clone -b production https://github.com/Junatum/openwrt.git
cd openwrt

./scripts/feeds update -a
./scripts/feeds install -a
```

Clone SafeShield and the LuCI application into the OpenWrt package tree:

```sh
git clone https://github.com/Junatum/safeshield package/safeshield
git clone https://github.com/Junatum/luci-app-safeshield package/luci-app-safeshield
```

Select the target device and enable the packages:

```sh
make menuconfig
```

For example, for a MediaTek Filogic based device such as `ipTIME AX3000SM`, select:

```text
Target System  ---> MediaTek Ralink ARM
Subtarget      ---> Filogic 8x0
```

Then enable the packages as modules:

```text
Network  ---> safeshield <M>
LuCI     ---> Applications ---> luci-app-safeshield <M>
```

Alternatively, append the package selections directly to `.config`:

```sh
cat >> .config <<'EOF'
CONFIG_PACKAGE_safeshield=m
CONFIG_PACKAGE_luci-app-safeshield=m
EOF

make defconfig
```

Build the packages:

```sh
make package/safeshield/clean V=s
make package/luci-app-safeshield/clean V=s

make package/safeshield/compile V=s
make package/luci-app-safeshield/compile V=s
```

Find the generated packages:

```sh
find bin -type f \( \
  -name 'safeshield*.apk' \
  -o -name 'luci-app-safeshield*.apk' \
\) -print
```

Depending on the OpenWrt version and package manager, the output may be located under one of these directories:

```text
bin/targets/<target>/<subtarget>/packages/
bin/packages/<architecture>/<feed-name>/
```

For example, on a MediaTek Filogic target, packages may appear under:

```text
bin/targets/mediatek/filogic/packages/
bin/packages/aarch64_cortex-a53/base/
bin/packages/aarch64_cortex-a53/luci/
```

OpenWrt 25.12 and newer snapshot builds usually generate `.apk` packages.

### Build with OpenWrt SDK

If you only need to build packages and do not need to build a full firmware image, use the OpenWrt SDK for your target.

Extract the SDK and enter the SDK directory:

```sh
tar xf openwrt-sdk-*.tar.zst
cd openwrt-sdk-*
```

Update and install feeds:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
```

Clone the required packages:

```sh
git clone https://github.com/Junatum/safeshield package/safeshield
git clone https://github.com/Junatum/luci-app-safeshield package/luci-app-safeshield
```

Enable the packages:

```sh
cat >> .config <<'EOF'
CONFIG_PACKAGE_safeshield=m
CONFIG_PACKAGE_luci-app-safeshield=m
EOF

make defconfig
```

Build:

```sh
make package/safeshield/compile V=s
make package/luci-app-safeshield/compile V=s
```

### Install the built packages on OpenWrt

Copy the generated packages to the device:

```sh
scp -O safeshield-*.apk luci-app-safeshield-*.apk root@192.168.1.1:/tmp/
```

Install on an `apk` based OpenWrt system:

```sh
ssh root@192.168.1.1

apk add --allow-untrusted /tmp/safeshield-*.apk
apk add --allow-untrusted /tmp/luci-app-safeshield-*.apk

/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/safeshield restart
```

### Verify installation

Check that the packages are installed:

```sh
apk info | grep safeshield
```

Check that the LuCI application files exist:

```sh
ls -la /www/luci-static/resources/view/safeshield/
ls -la /usr/share/luci/menu.d/ | grep safeshield
ls -la /usr/share/rpcd/acl.d/ | grep safeshield
```

Check that the SafeShield RPC endpoint is available:

```sh
ubus list | grep safeshield
ubus call safeshield status
```

If the LuCI page does not update after installing a new build, clear the LuCI cache and restart services:

```sh
rm -rf /tmp/luci-*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

Then open LuCI:

```text
http://192.168.1.1/cgi-bin/luci/admin/services/safeshield
```

## Management API architecture

Starting with `luci-app-safeshield` 0.2.0, the LuCI application does not write
SafeShield UCI state or `/etc/safeshield` rule files directly. The `safeshield`
package owns configuration validation, lifecycle, license storage, local rule
files, refresh scheduling, dnsmasq integration and DNS verification.

LuCI consumes the public API exposed by SafeShield:

```text
safeshield.status
safeshield.config
safeshield.config_update
safeshield.set_enabled
safeshield.refresh
safeshield.rules_list
safeshield.rule_add
safeshield.rule_delete
safeshield.license_update
```

The Local Rules page uses SafeShield's fast local apply path. A normal rule edit
reuses the cached normalized Hub artifact and only rebuilds local allow/block
inputs, merges the active blocklist, restarts dnsmasq and verifies DNS. A full
Hub refresh is used only when the cached artifact is unavailable.

After installation, verify the API contract with:

```sh
ubus -v list safeshield
```

The LuCI ACL should not need direct UCI access to the `safeshield` package.

## Contributors

<a href="https://github.com/Junatum/luci-app-safeshield/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=Junatum/luci-app-safeshield" alt="Contributors">
</a>

## License

SafeShield (luci-app-safeshield) is under the [GNU Public License version 3](https://www.gnu.org/licenses/gpl-3.0.html)
