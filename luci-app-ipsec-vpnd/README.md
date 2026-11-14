# luci-app-ipsec-vpnd

LuCI 界面，给运行在 OpenWrt / ImmortalWrt 上的 strongSwan IPsec VPN 服务做配置管理。

IKEv1 + PSK + Xauth（账号密码），目标用户是家用 / 小公司路由器场景——LAN 后面的客户端用用户名密码拨号，拿到一个独立虚拟网段的 IP。

> **维护者说明**：本项目维护者本人既在自家路由器上跑，也把编译好的 .apk/.ipk 同步发到 community / 朋友分发渠道。下面“构建”与“安装”分别对应这两种使用方式。

---

## 功能

- **VPN 服务启停**（uhttpd → LuCI → 控制 strongSwan 原生的 `ipsec` 服务，即 `procd` 托管的 `starter` + `charon`）；「启用」是总开关，关掉时服务会停、conn 会从 `ipsec.conf` 里移除、凭据文件也会清掉
- **账号 / 密码 / PSK 配置** 写在 `/etc/config/ipsec-vpnd`，由 `luci-ipsec-vpnd-render` 翻译成 strongSwan 的 `ipsec.conf` + `ipsec.secrets`
- **首次安装自动初始化**：建 `network.VPN` 设备（绑 `ipsec0`）+ `firewall.ike/ipsec/ah/esp` 入站规则 + `firewall.VPN` zone + 端口转发；只跑一次，`/etc/config/ipsec-vpnd` 里的 `initialized` 标记防止升级时覆盖用户后续自定义
- **不再自建服务实例**：本包不提供自己的 `ipsec-vpnd` 服务，charon 统一交给 strongSwan 自带的 `ipsec` 服务托管（`strongswan-ipsec` 包提供），从根本上避免两个服务抢 UDP/500、4500——抢端口时后启动的那个会**静默退出**，LuCI 上只显示「未运行」却查不到原因
- **菜单位置**：`VPN → IPSec VPN Server`（order 30）
- **依赖自检与诊断**：服务启动前检查 strongSwan 运行时是否完整，缺失时拒绝启动并写明确日志；LuCI 页面顶部直接列出缺哪一项、给出对应安装命令

## 界面与配置项

UCI 路径 `ipsec-vpnd.@ipsec[0]`，字段：

| 字段 | 默认 | 说明 |
|---|---|---|
| `enabled` | `0` | 总开关。关掉 = 服务停 + 不加载 conn + 清除 `ipsec.secrets` |
| `clientip` | `10.9.8.10/24` | 客户端地址池（CIDR），用 strongSwan 的 `rightsourceip` 推给拨号端 |
| `clientdns` | `10.9.8.1` | 推给客户端的 DNS（即 VPN 网关 IP） |
| `account` | `vpnuser` | Xauth 用户名 |
| `password` | `changeme` | Xauth 密码 |
| `secret` | `changeme` | IKE PSK 预共享密钥 |

VPN 客户端拨号后会拿到 `clientip` 池里一个地址，`clientdns` 指向 VPN 网关（路由器上的 `ipsec0` IP，固定为 `10.9.8.1`）。

> `clientip` 直接传给 strongSwan 的 `rightsourceip`，格式是 `<起始地址>/<掩码>`，表示一个**地址池**。
> 默认的 `10.9.8.10/24` 即 `10.9.8.10`–`10.9.8.254`（245 个地址，起点避开网关 `10.9.8.1`），
> 多个客户端可以同时在线，各自拿到池里的一个地址（实测两个客户端分别拿到 `10.9.8.10` / `10.9.8.11`）。
> 注意 `account` 目前只支持**一个** XAuth 账号，不同用户名无法登录。

## 客户端配置示例（已实测通过）

Linux 客户端（strongSwan 5.9/6.x）：

```conf
# /etc/ipsec.conf
config setup
    uniqueids=never

conn client
    keyexchange=ikev1
    ike=aes128-sha1-modp2048,aes128-sha1-modp1024,3des-sha1-modp1024,3des-sha1-modp1536
    esp=aes128-sha1,3des-sha1
    right=192.168.1.139          # 服务端地址
    rightauth=psk
    left=%defaultroute
    leftid=testuser             # IKE ID，同时作为 XAuth 用户名
    leftauth=psk
    leftauth2=xauth             # IKEv1 第二轮 XAuth 认证
    leftsourceip=%config        # 向服务端申请虚拟地址
    auto=start
```

```conf
# /etc/ipsec.secrets（客户端侧也要写 XAuth 密码）
: PSK "testpsk"
testuser : XAUTH "testpass"
```

**关键点**：客户端必须用 `leftsourceip=%config`（或与服务端 `clientip` 完全一致的 TS）。
写死 `leftsubnet=10.9.8.0/24` 或 `leftsourceip=<自己的地址>` 会与服务端下发的
`10.9.8.10/32` 冲突，服务端日志出现
`no matching CHILD_SA config found for 10.9.8.0/24 === <服务端IP>/32`，
最终报 `INVALID_ID_INFORMATION`，IKE 起来了但 CHILD SA 装不上。

## 依赖

本包是纯 LuCI 前端 + 脚本，运行时依赖 strongSwan。**安装本包时会自动拉取下面这些依赖**（apk / ipk 的 `depends` 已声明）：

| 包 | 作用 |
|---|---|
| `strongswan-minimal` | strongSwan 最小集，含 charon、starter（`/usr/lib/ipsec/starter`）、stroke 插件 |
| `strongswan-mod-xauth-generic` | XAuth 账号认证插件，缺它 XAuth 账号无法登录 |
| `strongswan-mod-kernel-libipsec` | 内核态 IPsec |
| `strongswan-mod-des` | 3DES 加密插件，缺它本包声明的 3DES 提案不可用（老版本 iOS/Android 客户端需要） |
| `kmod-tun` | TUN/TAP 设备 |

> `strongswan-mod-stroke` 会连带装上 `strongswan-ipsec`（提供 `/usr/sbin/ipsec` 命令与系统自带的 `ipsec` 服务）。
> 本包正是复用这个服务来托管 charon：LuCI 服务列表里跑起来的是 `ipsec`，本包不再有独立的 `ipsec-vpnd` 服务实例。

### 如果提示找不到依赖

先更新索引再装：

```sh
apk update
apk add luci-app-ipsec-vpnd-*.apk
```

索引缓存损坏时 `apk search` 会返回空，看起来像"源里没有 strongswan"，`apk update` 即可恢复。

### 关于 ImmortalWrt 25.12 系列

实测 **ImmortalWrt 25.12.2 官方源已经带 strongswan**（`apk search strongswan*` 有 100+ 个包），直接装本包即可，不需要混用 OpenWrt 源。

25.12.0 / 25.12.1 是否同样带 strongswan **未验证**（这些源的镜像不提供历史索引，无法回溯确认）。如果你手上的版本确实报"找不到依赖"，可以自行确认：

```sh
apk update && apk search strongswan\*
```

若确实没有，可用**同版本**的 OpenWrt 源（注意内核与 libc 版本必须一致，否则会出现不可预期的依赖错配），或在固件里预装 strongswan 后再装本包。

## 安装

### 普通用户（装现成的 .apk）

从本仓库的 `Actions → Build → 最新一次成功 run → Artifacts → ipsec-vpnd-packages` 下载 `luci-app-ipsec-vpnd-*.apk` 和 `luci-i18n-ipsec-vpnd-zh-cn-*.apk`（中文界面，可选），用 scp / WinSCP 推到路由器：

```sh
apk update
apk add --allow-untrusted luci-app-ipsec-vpnd-*.apk
apk add --allow-untrusted luci-i18n-ipsec-vpnd-zh-cn-*.apk   # 可选
```

> 25.12 用 `apk`，更老的版本用 `opkg install`。
> `--allow-untrusted` 是因为 CI 产出的包没有签名；正式分发建议自行签名。

第一次安装会跑 `uci-defaults/luci-ipsec-vpnd` 一次性初始化（建 network/firewall/zone + 启用系统 `ipsec` 服务 + 渲染初始 strongSwan 配置 + 拉起 VPN 网关接口），然后 LuCI 刷新一下就能在 `VPN → IPSec VPN Server` 看到。

或者从 release 装（GitHub Actions 自动把每次 main 提交 publish 到 `IPSec VPND Latest Build` release，注意该 release 每次推送会重建，文件名里的版本号会变）：

```sh
apk add --allow-untrusted https://github.com/szwjp/luci-app-ipsec-vpnd/releases/download/luci-app-ipsec-vpnd/luci-app-ipsec-vpnd-27.906.25.12-r12.apk
```

### 自己构建（社区分发 / 自己做 firmware）

走仓库的 GitHub Actions **Build** workflow：push 到 `main` 触发（或手动 dispatch），会在 GitHub Actions 里产 `luci-app-ipsec-vpnd-*.apk` + `luci-i18n-ipsec-vpnd-zh-cn-*.apk` 两个 apk 和对应的 ipk，并通过 `softprops/action-gh-release` publish 到 latest release。本地要复现的话：

```sh
# Ubuntu 20.04+，装上 apk-tools / meson / ninja / fakeroot
sudo apt-get install -y build-essential meson ninja-build fakeroot

# 用仓库自带的 .github/build-pkg.sh
fakeroot bash .github/build-pkg.sh apk 1     # 出 luci-app-ipsec-vpnd-*.apk + luci-i18n-ipsec-vpnd-zh-cn-*.apk
fakeroot bash .github/build-pkg.sh ipk 1     # 出同名 .ipk
ls -l *.apk *.ipk
```

> `fakeroot` 不能省：apk v3 的 `mkpkg` 直接按文件属主写包，没有 fakeroot 就会把构建者的 uid 打进包里，装出来的文件属主不是 root。
> macOS 上脚本本身能跑（已把 `mktemp -p` / `find -printf` / `sha256sum` 换成可移植写法），但产物属主仍是本地用户，仅适合调试，正式发布请走 CI。
>
> **`po2lmo` 必须是真的那个**（CI 里从 luci 源码编译）。LuCI 的 `.lmo` 不是 GNU MO 格式，
> 用 `msgfmt` 转出来的 MO 文件能被 `msgunfmt` 读，但 LuCI 的加载器读不了 —— 装上去的表现是
> **页面所有文案退回英文**。本地要构建的话：
>
> ```sh
> git clone --depth 1 --filter=blob:none --sparse https://github.com/openwrt/luci.git
> cd luci/modules/luci-base/src && make po2lmo   # 产物在当前目录
> export PATH="$PWD:$PATH"
> ```

`build-pkg.sh` 用了仓库里那个**专为本包定制的最小工具链**（apk-tools 自编译 + po2lmo 自编译 + ipkg-build），不依赖完整 OpenWrt SDK 编译环境；这就是为什么 `build.yml` 跑得很快（~40s）。所有 actions 都用 Node 24 版（`actions/checkout@v5` / `actions/upload-artifact@v6` / `softprops/action-gh-release@v3`）。

## 测试

```sh
sh tests/run-all.sh
```

三组离线测试，不依赖路由器：

- `render-test.sh` —— UCI → `ipsec.conf`/`ipsec.secrets` 的映射、secrets 权限 0600、
  停用时不留 conn、依赖缺失时不生成配置
- `sessions-parse-test.sh` —— 客户端列表解析：控制字符清洗、旧版脏行丢弃、
  在线但无地址时打 `vip_pending`、历史上限 200 条
- `sanitize-test.sh` —— 控制字符清洗工具

脚本用的是 POSIX sh + awk，**在 OpenWrt 的 busybox 上也能跑**（CI 里跑的是
GNU 环境，所以改完记得也在设备上跑一遍：busybox 的 `tr` 不认 `[:cntrl:]`
字符类，会把字面字符删掉——这个坑就是这么漏出去的）。

## CI

`.github/workflows/` 下两个 workflow：

- **`build.yml`**（生产 workflow）：push 到 main / PR / 手动 dispatch 触发。9 步全绿、零 annotation，~40s 出包并 publish 到 release。是这个项目的命脉。
- **`cleanup-old-workflow.yml`**（工具 workflow）：手动 dispatch，按你给的天数阈值删 `actions/runs` 里的 completed run，防止 Actions 列表太长。文件名带 `.yml` 后缀（之前没有后缀，GitHub Actions 静默忽略——这种坑踩过一次记到 memory 里了）。

## 目录结构

```
.
├── Makefile                 # OpenWrt 包定义：LUCI_TITLE / LUCI_DEPENDS / PKG_*
├── tests/                   # 离线回归测试（不依赖路由器，CI 里也会跑）
│   ├── run-all.sh           # 跑全部测试
│   ├── render-test.sh       # UCI → ipsec.conf / ipsec.secrets 渲染
│   ├── sessions-parse-test.sh # 客户端列表解析（控制字符、脏行、历史上限）
│   └── sanitize-test.sh     # 控制字符清洗
├── htdocs/luci-static/resources/view/ipsec-vpnd.js
│                            # LuCI web UI（配置表单 + 在线客户端表 + 依赖诊断）
├── po/
│   ├── templates/ipsec-vpnd.pot   # gettext 模板
│   └── zh_Hans/ipsec-vpnd.po      # 简体中文翻译
├── root/
│   ├── etc/config/ipsec-vpnd      # UCI 默认配置（服务默认 enabled=0）
│   ├── usr/lib/ipsec/luci-ipsec-vpnd-render  # UCI → ipsec.conf/ipsec.secrets 渲染器（含依赖自检）
│   ├── etc/uci-defaults/luci-ipsec-vpnd
│   │                              # 首次安装一次性：建 network.VPN + firewall
│   ├── usr/lib/ipsec/luci-ipsec-vpnd-deps
│   │                              # 依赖自检：init 启动拦截 + LuCI 诊断面板共用
│   ├── usr/lib/ipsec/luci-ipsec-vpnd-updown
│   │                              # strongSwan updown 钩子：记录客户端上下线
│   ├── usr/lib/ipsec/luci-ipsec-vpnd-sanitize
│   │                              # 剥掉用户名里的控制字符（busybox 的 tr 不认字符类）
│   ├── usr/libexec/rpcd/ipsec-vpnd # rpcd 后端：sessions / clear_history / deps / apply
│   ├── usr/share/luci/menu.d/luci-app-ipsec-vpnd.json
│   │                              # LuCI 菜单注册（VPN → IPSec VPN Server）
│   └── usr/share/rpcd/acl.d/luci-app-ipsec-vpnd.json
│                                   # rpcd ACL：放行 luci-app-ipsec-vpnd 读写 /etc/config/ipsec-vpnd
├── .github/
│   ├── build-pkg.sh              # 绕过 SDK 的 apk / ipk 直接打包脚本
│   └── workflows/
│       ├── build.yml
│       └── cleanup-old-workflow.yml
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
| 装完服务起不来，日志说 "starter: no such file" | strongSwan 运行时没装上。先 `apk update`（索引缓存坏了会搜不到包），再 `apk add strongswan-minimal strongswan-mod-xauth-generic strongswan-mod-kernel-libipsec strongswan-mod-des` |
| LuCI 页面顶部出现红色「缺少依赖」 | 页面会直接列出缺哪一项以及对应的安装命令，照着执行即可 |
| 客户端拨不上，日志说 "no IKE config" | 看 `/etc/config/ipsec-vpnd` 的 `enabled` 是不是 `1`；看 init 日志（`logread \| grep ipsec`） |
| 客户端拨不上，日志说 "no acceptable proposal" | 多半缺 3DES 插件：装 `strongswan-mod-des` |
| 服务显示「未运行」但 charon 明明在跑 | 说明有第二个服务实例抢占了 UDP/500、4500。本包不再自建服务，正常情况下只有系统 `ipsec` 一个实例；`ls /etc/rc.d/*ipsec*` 检查是否残留旧版 `ipsec-vpnd` 链接 |
| 装完 `ipsec0` 上没有 VPN 网关地址 | 执行 `ifup VPN`；本包在安装与服务启动时都会自动执行一次 |
| GitHub Actions 出包失败 | 看 `Build` workflow 的 step 日志；常见是 host 工具链 apt 装失败、或 apk-tools/po2lmo 编译报错 |

## 许可证

Apache-2.0。详见 `LICENSE`。
