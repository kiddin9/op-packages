# luci-app-tailscale

Tailscale is a zero config VPN for building secure networks.

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/asvow/luci-app-tailscale?style=flat-square)](https://github.com/asvow/luci-app-tailscale/releases)
[![GitHub stars](https://img.shields.io/github/stars/asvow/luci-app-tailscale?style=flat-square)](https://github.com/asvow/luci-app-tailscale/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/asvow/luci-app-tailscale?style=flat-square)](https://github.com/asvow/luci-app-tailscale/network/members)
[![License](https://img.shields.io/github/license/asvow/luci-app-tailscale?style=flat-square)](LICENSE)
[![GitHub All Releases](https://img.shields.io/github/downloads/asvow/luci-app-tailscale/total?style=flat-square)](https://github.com/asvow/luci-app-tailscale/releases)

## How to build

- Only compatible with luci2 version

- Enter in your openwrt dir

  *1. replace the default startup script and configuration of Tailscale.*
  ```shell
  sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
  ```

  *2. get luci-app-tailscale source & building*
  ```shell
  git clone https://github.com/asvow/luci-app-tailscale package/luci-app-tailscale
  make menuconfig # choose LUCI -> Applications -> luci-app-tailscale
  make package/luci-app-tailscale/compile V=s # luci-app-tailscale
  ```

--------------

## How to install prebuilt packages

- Upload the prebuilt ipk or apk package to the /tmp directory of OpenWrt
- Login OpenWrt terminal (SSH)

Install the main package, then optionally install either the Simplified Chinese or Traditional Chinese language package.

### opkg package manager

```shell
opkg update
opkg install /tmp/luci-app-tailscale_*.ipk

# Optional Simplified Chinese translation
opkg install /tmp/luci-i18n-tailscale-zh-cn_*.ipk

# Or optional Traditional Chinese translation
opkg install /tmp/luci-i18n-tailscale-zh-tw_*.ipk
```

### apk package manager

```shell
apk update
apk add --allow-untrusted /tmp/luci-app-tailscale-*.apk

# Optional Simplified Chinese translation
apk add --allow-untrusted /tmp/luci-i18n-tailscale-zh-cn-*.apk

# Or optional Traditional Chinese translation
apk add --allow-untrusted /tmp/luci-i18n-tailscale-zh-tw-*.apk
```
--------------

## OpenClash Bypass

- Supports firewall4/nftables only.
- Enabled by default when the packaged setting is present; it is a no-op when OpenClash is absent.
- Manages one delimited block in `/etc/openclash/custom/openclash_custom_firewall_rules.sh`.
- The managed block invokes `/usr/sbin/tailscale_openclash_bypass apply` through OpenClash's official custom firewall hook.
- Manages exactly four comment-owned rules in OpenClash's nftables chains.
- Does not modify `/etc/config/firewall`, reload firewall4, or start/restart OpenClash.
- WAN direct remains a separate feature that manages only its own firewall UCI rules.
- Status states: `active`, `waiting`, `disabled`, `absent`, `unsupported`, and `error`.
- Cleanup removes only the managed hook block and the four `luci-app-tailscale:` rules.
- Package installation uses the standard LuCI/OpenWrt post-install lifecycle; the packaged init script performs one locked `sync`.

Rollback:

```sh
uci set tailscale_openclash.settings.enabled='0'
uci commit tailscale_openclash
/etc/init.d/tailscale-openclash-bypass reload
/usr/sbin/tailscale_openclash_bypass status
```

--------------

## Auth Key Lifecycle

- An auth key is used only for first-time enrollment or when a new value is
  explicitly entered in LuCI to re-enroll the device.
- After the connection obtains a Tailscale address, the saved auth key is
  removed from every protected credential version. The persistent
  `tailscaled.state` identity is kept and is used for normal restarts.
- An auth key is retained when enrollment fails so the configuration can be
  corrected and retried.
- Auth keys migrated from an older package are ignored when an existing
  `tailscaled.state` identity is present, preventing a reboot from attempting
  an unintended registration.

--------------

## mwan3 Policy Routing Compatibility

- Disabled by default; enable it only when mwan3 fwmark rules take precedence
  over Tailscale table `52` and LAN clients cannot reach Tailnet routes.
- Creates an app-owned IPv4 `priority 1000 lookup 52` rule before mwan3's
  fwmark rules. Destinations absent from table `52` continue to mwan3.
- Refuses to activate if table `52` has a default route, such as while using a
  Tailscale exit node, so ordinary internet traffic is not diverted from mwan3.
- Uses only `network` UCI, `ip rule`, and an interface-event self-heal. It does
  not modify firewall UCI, reload firewall4, or manage mwan3/OpenClash.
- Validate from a real LAN client or with an equivalent mwan3 fwmark; an
  unmarked `ip route get` on the router is not a sufficient test.

Rollback:

```sh
uci set tailscale_policy_routing.settings.enabled='0'
uci commit tailscale_policy_routing
/etc/init.d/tailscale-policy-routing reload
/usr/sbin/tailscale_policy_routing status
```

--------------

## AdGuard DNS Auto Switch

- Disabled by default.
- Intended for OpenWrt setups where local AdGuard Home owns LAN DNS port 53.
- LAN DHCP should advertise the router LAN IP as DNS, for example `6,192.168.100.1`.
- DNS health is checked through Headscale/Tailscale DNS at `100.100.100.100`.
- Tailscale `accept_dns` is not required; the health check queries `100.100.100.100` directly.
- Healthy profile: default upstreams plus Tailnet conditional upstreams.
- Unhealthy profile: default upstreams only.
- Configuration is written through the AdGuard Home HTTP API, not by editing the YAML path.
- Leaving the password field blank keeps the existing value.

Rollback:

```shell
/usr/sbin/tailscale_adguard_dns_switch --apply-profile down
uci set tailscale.settings.adguard_dns_switch_enabled='0'
uci commit tailscale
/etc/init.d/tailscale reload
```

--------------

## Thanks
- [Carseason/openwrt-tailscale](https://github.com/Carseason/openwrt-tailscale)
- [immortalwrt/luci-app-zerotier](https://github.com/immortalwrt/luci/blob/master/applications/luci-app-zerotier)

--------------

## Screenshot
<img width="573" alt="Basic" src="https://github.com/user-attachments/assets/bfca389a-bcec-42de-b5dd-b9588fd5db23" />
<img width="577" alt="Advanced" src="https://github.com/user-attachments/assets/d60ce19e-b3f3-43a7-98fc-7df6e2231898" />
<img width="575" alt="Extra" src="https://github.com/user-attachments/assets/6de5eaa7-6c18-48b8-a44a-0eaa311b0b79" />
