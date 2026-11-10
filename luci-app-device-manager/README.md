# luci-app-device-manager

轻量级 OpenWrt LuCI 局域网设备管理插件，可按 MAC 地址保存名称、备注、分组和设备类型。已有自定义数据在升级时保留。

A lightweight LAN device manager for OpenWrt LuCI. Combine host hints, DHCP
leases, Wi-Fi associations and kernel neighbors; save names, remarks, groups
and manual device types by MAC address, including saved offline devices.

## 功能 / Features

- 展示 IPv4、IPv6、接口和状态依据，区分在线、离线和未知状态。
- 按分组、状态和关键词筛选，支持排序、手动登记及地址隐藏。
- 支持 29 种显示类型和本地 SVG 图标；名称和少量有来源的厂商线索用于推测，用户可手动覆盖。
- 页面先显示界面，列表单独加载；使用当前标签页和登录会话内的 5 分钟缓存，后台读取实时数据。
- 状态未知且有已知 IP 的设备会在后台逐台 Ping，收到回应即判为在线；未回应仍保留未知。
- “扫描局域网”由用户主动触发，需要写权限；读取失败提示可手动关闭，并在 12 秒后自动收起。
- 只读账号可查看、刷新和单设备 Ping，不能修改记录或启动批量扫描。
- 使用 LuCI 原生语言设置和翻译包，不覆盖浏览器或 LuCI 的语言选择。

The application distinguishes confirmed online, offline and unknown states.
Filters and sortable columns support device groups, status and text searches.
Manual registration, details, one-device Ping and address masking are available.
The page renders before discovery finishes. A five-minute, per-tab and
per-session cache supports repeat visits while live data refreshes in the
background. Empty-state messages wait for discovery and online checks to finish.

Known devices with an unknown status and an IP address are checked one at a
time in the background, with at most 16 checks and a 12-second budget per pass.
A Ping reply confirms online status; a timeout or error leaves it unknown.
Replies for an older snapshot cannot change the current list. Each refresh
re-evaluates the evidence; successful Pings are not retained as permanent status.

Type recognition is a best-effort display hint with a manual override; see
[identification rules and provenance](docs/device-identification.md).

## 安装 / Installation

本项目尚未合并到官方源。先用本仓库的 GitHub Actions 或 OpenWrt SDK 构建，再安装与目标系统版本匹配的本地包。

The package requires `luci-base`, `rpcd-mod-iwinfo` and `jshn`.
Standard OpenWrt BusyBox provides the required `ip` and `flock` commands;
`luci-base` supplies the file RPC dependency. Custom firmware that disables
these BusyBox applets must enable them or install `ip-tiny` (or `ip-full`)
and `flock` separately.

OpenWrt with opkg, in the directory containing the build artifacts:

```sh
opkg install luci-app-device-manager_*.ipk
opkg install luci-i18n-device-manager-zh-cn_*.ipk
```

OpenWrt with apk, for locally built packages:

```sh
apk add --allow-untrusted ./luci-app-device-manager-*.apk
apk add --allow-untrusted ./luci-i18n-device-manager-zh-cn-*.apk
```

The Chinese language package is optional. Without an installed translation,
LuCI displays the English source messages. After installation, reload LuCI
and open **Network → Device Manager**.

源码面向现代 JavaScript LuCI，构建 workflow 默认验证 SNAPSHOT，并支持指定稳定版 SDK。
真实路由器安装、升级、主题和账户权限验收需按下方步骤执行，不能由本地单元测试代替。

## 扫描范围 / Scan scope

默认仅扫描 netifd 的逻辑接口 `lan`。从接口的 `l3_device` 和内核 IPv4 地址获取真实网段，
不会根据全局路由表选择 WAN，也不会假设网段为 `/24`。

To add a separate trusted LAN, list its logical netifd interface explicitly:

```uci
config settings 'settings'
    list scan_interface 'lan'
    list scan_interface 'guest'
```

An existing configuration without settings defaults to `lan`. An explicitly
empty `scan_interface` disables scanning. At most eight interfaces and 64
subnets are considered. Never add an uplink interface unless probing that
interface is intentionally required.

Each Ping is bound to the selected LAN device. Router, network and broadcast
addresses are excluded; known leases and neighbors are also checked against
the selected subnet. Prefixes with at most 4096 addresses can be enumerated.
Larger subnets probe known in-scope hosts only. IPv6 is discovered passively;
single-device Ping can use a known IPv6 address.

Batch scans share a lock, allow at most 16 concurrent children and 128 targets
per request, stop after about eight seconds and use a 30-second cooldown
measured after completion. Further eligible clicks resume the sweep.
An unanswered ICMP Ping does not by itself prove a device is offline.

## 构建和开发 / Build and development

GitHub Actions **Build OpenWrt Package** accepts `SNAPSHOT` or a release
version and a `target/subtarget` such as `x86/64` or `mediatek/filogic`.
It verifies the official SDK checksum and builds an exported in-tree LuCI
application plus the Chinese language package. Standalone artifacts receive
LuCI-style versions from the source repository commit, rather than the
untracked export directory. Pull requests and main-branch
pushes build SNAPSHOT. Tags publish the resulting artifacts in a release.

Independent-repository tools are not installed on the router or exported as
top-level files into the upstream LuCI repository:

```sh
node --test test/test_*.js
python3 -B -m unittest discover -s test -p 'test_*.py'
python3 -B tools/update-translations.py --check --luci-dir /path/to/luci
```

Regenerate the native POT and merge the PO with the official LuCI extractor:

```sh
python3 -B tools/update-translations.py --luci-dir /path/to/luci
```

Future upstream translations should follow LuCI's Weblate workflow.
`luci.mk` compiles `.lmo` language packages; compiled catalogues are not
committed. The standalone `tools/deploy.sh` is only for development:
it preserves existing device configuration and reuses one SSH authentication,
but requires installing the native language package separately.

For upstream export and a suggested commit/PR description, see
[submission preparation](docs/upstream-submission.md) in the independent
repository. No tool commits, pushes or rewrites existing contributor history.

## 真实设备验收 / Router acceptance

1. Install the package and optional Chinese translation on a matching system;
   verify English and Chinese language selection and a second LuCI language.
2. Save a device name, note, type and group; upgrade the package and reboot;
   verify that the records and an intentionally empty group list survive.
3. Use a read-only account: verify refresh and details, and ensure editing and
   batch scanning are denied by the RPC ACL even when called directly.
4. On isolated `/25` and `/23` LANs, inspect packet captures while scanning;
   verify interface binding, subnet boundaries, concurrency and cooldown.
5. Test standard BusyBox `ip` and optionally `ip-tiny`/`ip-full`, an unavailable LAN,
   IPv6-only details, Wi-Fi VLAN stations and incomplete discovery sources.
6. Check the stock Bootstrap/OpenWrt themes on desktop and mobile, including
   dark mode, keyboard controls and dialogs.

## 许可证 / Licensing

Project code: MIT, see [LICENSE](LICENSE). Material Design Icons: Apache-2.0,
with source revision, per-icon URLs and local changes recorded under
[device-icons](htdocs/luci-static/resources/device-manager/device-icons/NOTICE).
Both applicable licenses are declared in the package Makefile.
