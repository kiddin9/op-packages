# luci-app-ipsec-vpnd

LuCI 界面，给运行在 OpenWrt / ImmortalWrt 上的 strongSwan IPsec VPN 服务做配置管理。

IKEv1 + PSK + Xauth（账号密码），目标用户是家用 / 小公司路由器场景——LAN 后面的客户端用用户名密码拨号，拿到一个独立虚拟网段的 IP。

> **维护者说明**：本项目维护者本人既在自家路由器上跑，也把编译好的 .apk/.ipk 同步发到 community / 朋友分发渠道。下面“构建”与“安装”分别对应这两种使用方式。

---

## 功能

- **VPN 服务启停**（uhttpd → LuCI → procd 守护进程控制 strongSwan 的 `starter`）
- **账号 / 密码 / PSK 配置** 写在 `/etc/config/ipsec-vpnd`，运行时被 init 脚本翻译成 strongSwan 的 `ipsec.conf` + `ipsec.secrets`
- **首次安装自动初始化**：建 `network.VPN` 设备（绑 `ipsec0`）+ `firewall.ike/ipsec/ah/esp` 入站规则 + `firewall.VPN` zone + 端口转发；只跑一次，`/etc/config/ipsec-vpnd` 里的 `initialized` 标记防止升级时覆盖用户后续自定义
- **和系统自带的 `ipsec` 服务冲突处理**：每次启动前都 `stop && disable` 系统那个，防止 charon 抢 UDP/500、4500
- **菜单位置**：`VPN → IPSec VPN Server`（order 30）

## 界面与配置项

UCI 路径 `ipsec-vpnd.@ipsec[0]`，字段：

| 字段 | 默认 | 说明 |
|---|---|---|
| `enabled` | `0` | 总开关 |
| `clientip` | `10.9.8.10/24` | 客户端地址池（CIDR），用 strongSwan 的 `rightsourceip` 推给拨号端 |
| `clientdns` | `10.9.8.1` | 推给客户端的 DNS（即 VPN 网关 IP） |
| `account` | `vpnuser` | Xauth 用户名 |
| `password` | `changeme` | Xauth 密码 |
| `secret` | `changeme` | IKE PSK 预共享密钥 |

VPN 客户端拨号后会拿到 `clientip` 池里一个地址，`clientdns` 指向 VPN 网关（路由器上的 `ipsec0` IP，初始化脚本里按 LAN 前两段、第三段 +1 自动算出来）。

## 依赖

`Makefile` 里 `LUCI_DEPENDS` 列的运行时依赖：

```
+strongswan-minimal
+strongswan-mod-xauth-generic
+strongswan-mod-kernel-libipsec
+strongswan-mod-des
+kmod-tun
```

**这是 IPsec VPN 服务能起来的前提。**安装本包前请确认这些包在固件里都有，否则 LuCI 界面能开，但服务起不来。

### 关于 ImmortalWrt 25.12 系列（重要）

ImmortalWrt **25.12.0 / 25.12.1 的官方软件源在全架构上都没带 strongswan**（OpenWrt 上游 25.12 源有，ImmortalWrt 24.10 源也有，唯独 ImmortalWrt 25.12 系列缺）。如果你的固件就是 ImmortalWrt 25.12 系列且只挂着官方源，`opkg install luci-app-ipsec-vpnd` 会卡在依赖解析。

可行方案（任选）：

- **换 OpenWrt 上游源**：`/etc/opkg/distfeeds.conf` 里加 `src/gz openwrt_core https://downloads.openwrt.org/releases/25.12.1/targets/.../packages/`
- **换同版本但带 strongswan 的 ImmortalWrt fork 源**
- **用 szwjp/luci 这种社区源**，里头把 strongswan 也带上了

## 安装

### 普通用户（装现成的 .apk）

从本仓库的 `Actions → Build → 最新一次成功 run → Artifacts → ipsec-vpnd-packages` 下载 `luci-app-ipsec-vpnd_*.apk` 和 `luci-i18n-ipsec-vpnd-zh-cn_*.apk`（中文界面，可选），用 scp / WinSCP 推到路由器：

```sh
opkg install luci-app-ipsec-vpnd_*.apk
opkg install luci-i18n-ipsec-vpnd-zh-cn_*.apk   # 可选
```

第一次安装会跑 `uci-defaults/luci-ipsec-vpnd` 一次性初始化（建 network/firewall/zone + 删系统 ipsec 服务），然后 LuCI 刷新一下就能在 `VPN → IPSec VPN Server` 看到。

或者从 release 装（GitHub Actions 自动把每次 main 提交 publish 到 `IPSec VPND Latest Build` release）：

```sh
opkg install https://github.com/szwjp/luci-app-ipsec-vpnd/releases/download/luci-app-ipsec-vpnd/luci-app-ipsec-vpnd_27.906.25.12-r1_all.apk
```

### 自己构建（社区分发 / 自己做 firmware）

走仓库的 GitHub Actions **Build** workflow：push 到 `main` 触发（或手动 dispatch），会在 GitHub Actions 里产 `luci-app-ipsec-vpnd-*.apk` + `luci-i18n-ipsec-vpnd-zh-cn-*.apk` 两个 apk 和对应的 ipk，并通过 `softprops/action-gh-release` publish 到 latest release。本地要复现的话：

```sh
# Ubuntu 20.04+，装上 apk-tools / meson / ninja / fakeroot
sudo apt-get install -y build-essential meson ninja-build fakeroot

# 用仓库自带的 .github/build-pkg.sh
fakeroot bash .github/build-pkg.sh apk 1     # 出 luci-app-ipsec-vpnd_*.apk + luci-i18n-ipsec-vpnd-zh-cn-*.apk
fakeroot bash .github/build-pkg.sh ipk 1     # 出同名 .ipk
ls -l *.apk *.ipk
```

`build-pkg.sh` 用了仓库里那个**专为本包定制的最小工具链**（apk-tools 自编译 + po2lmo 自编译 + ipkg-build），不依赖完整 OpenWrt SDK 编译环境；这就是为什么 `build.yml` 跑得很快（~40s）。所有 actions 都用 Node 24 版（`actions/checkout@v5` / `actions/upload-artifact@v6` / `softprops/action-gh-release@v3`）。

## CI

`.github/workflows/` 下两个 workflow：

- **`build.yml`**（生产 workflow）：push 到 main / PR / 手动 dispatch 触发。9 步全绿、零 annotation，~40s 出包并 publish 到 release。是这个项目的命脉。
- **`cleanup-old-workflow.yml`**（工具 workflow）：手动 dispatch，按你给的天数阈值删 `actions/runs` 里的 completed run，防止 Actions 列表太长。文件名带 `.yml` 后缀（之前没有后缀，GitHub Actions 静默忽略——这种坑踩过一次记到 memory 里了）。

## 目录结构

```
.
├── Makefile                 # OpenWrt 包定义：LUCI_TITLE / LUCI_DEPENDS / PKG_*
├── htdocs/luci-static/resources/view/ipsec-vpnd.js
│                            # LuCI web UI（cbid 表格 + 启停按钮）
├── po/
│   ├── templates/ipsec-vpnd.pot   # gettext 模板
│   └── zh_Hans/ipsec-vpnd.po      # 简体中文翻译
├── root/
│   ├── etc/config/ipsec-vpnd      # UCI 默认配置（服务默认 enabled=0）
│   ├── etc/init.d/ipsec-vpnd      # procd init：写 ipsec.conf/secrets、启 starter
│   ├── etc/uci-defaults/luci-ipsec-vpnd
│   │                              # 首次安装一次性：建 network.VPN + firewall
│   ├── usr/share/luci/menu.d/luci-app-ipsec-vpnd.json
│   │                              # LuCI 菜单注册（VPN → IPSec VPN Server）
│   └── usr/share/rpcd/acl.d/luci-app-ipsec-vpnd.json
│                                   # rpcd ACL：放行 luci-app-ipsec-vpnd 读写 /etc/config/ipsec-vpnd
├── .github/workflows/
│   ├── build.yml
│   └── cleanup-old-workflow.yml
├── LICENSE                       # Apache-2.0
└── README.md                     # 本文件
```

## 维护

- 上游：fork 自 ImmortalWrt LuCI `applications/luci-app-ipsec-vpnd`
- 当前 main：自维护分支，修了上游一些配置假设（详见 commit 历史）
- 同步：fix 在 main 上验证后通过 PR 回上游
- 不要把生成的 `.apk` / `.ipk` 提交到仓库（`.gitignore` 已过滤）

## 故障排查

| 现象 | 排查 |
|---|---|
| LuCI 菜单看不到 IPSec VPN Server | LuCI → 系统 → 软件包，确认 `luci-app-ipsec-vpnd` 已装；刷新 LuCI 缓存（`rm -f /tmp/luci-indexcache`） |
| 服务起不来，日志说 "starter: no such file" | `strongswan-minimal` 没装；装上 |
| 客户端拨不上，日志说 "no IKE config" | 看 `/etc/config/ipsec-vpnd` 的 `enabled` 是不是 `1`；看 init 日志（`logread \| grep ipsec`） |
| 系统自带 ipsec 又被启起来抢端口 | 升级 strongswan 包后可能要再跑一次 `uci-defaults/luci-ipsec-vpnd`——本包 init 脚本每次启动前都会重新 stop+disable 系统那个，但只在服务 enabled 时跑 |
| ImmortalWrt 25.12 装不上（缺依赖） | 见上面“关于 ImmortalWrt 25.12 系列” |
| GitHub Actions 出包失败 | 看 `Build` workflow 的 step 日志；常见坑在 `actions/cache` 没命中、host 工具链 apt 装失败这些 |

## 许可证

Apache-2.0。详见 `LICENSE`。
