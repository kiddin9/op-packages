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
- **弱网/漫游默认项**：IKEv1 连接默认开 DPD（死连接约 150s 内清理）；VPN zone 自动做 MSS clamp（ipsec0 MTU 1400，避免大包 PMTU 黑洞）；WAN 公网地址变化时自动重启 ipsec 清理旧 SA
- **可选 IKEv2 + MOBIKE**（`ikev2=1`）：额外生成一条 IKEv2 连接，给 iOS/Android 原生「IKEv2」客户端用，手机在 Wi-Fi/蜂窝网络之间切换时不必重新握手；默认关闭，因为它只用 PSK 认证（不再校验账号密码）

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
| `ikev2` | `0` | 是否额外提供 IKEv2（PSK + MOBIKE）连接。开启后 IKEv2 客户端只需 PSK，不需要账号密码 |

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

### iOS / Android 原生 IKEv2（可选，先在页面打开「启用 IKEv2」）

IKEv2 支持 MOBIKE：手机 Wi-Fi ↔ 蜂窝切换时在协议内更新地址，不用重新做完整握手。
服务端只用 PSK 认证（与 IKEv1 共用 `secret`），所以客户端**不需要填账号密码**；
请使用足够强的 PSK。原有 IKEv1 客户端不受影响，可同时使用。

- **iPhone / iPad**：设置 → 通用 → VPN 与设备管理 → VPN → 添加 VPN 配置 → 类型选 `IKEv2`；
  服务器填公网地址或 DDNS；远程 ID 留空（或填服务器地址）；本地 ID 留空；
  认证选「共享密钥」，填入页面上配置的 PSK。
- **Android 11+**：设置 → 网络 → VPN → 添加 VPN → 类型 `IKEv2/IPSec PSK`；
  服务器填公网地址；IPSec 预共享密钥填 PSK；用户名密码留空。

> Apple 的 IKEv2「用户名 + 密码」认证（EAP-MSCHAPv2）要求服务端出示证书，本包不会自动
> 生成/分发证书，所以继续用 IKEv1（Cisco IPSec）+ 账号密码，或接受 IKEv2 仅 PSK。
> 在路由上等价于：`uci set ipsec-vpnd.ipsec.ikev2=1 && uci commit ipsec-vpnd`，再在 LuCI 里保存一次（触发 apply）。

## IKEv1 是可选能力（strongSwan 6.1 起默认关闭）

本包渲染前会检查 `/etc/strongswan.d/charon/xauth-generic.conf`：

- **存在**：生成 `conn xauth_psk`（IKEv1 + PSK + XAuth）和可选的 `conn ikev2_psk`；
- **不存在**（例如 strongSwan 6.1 未用 `--enable-ikev1` 编译）：**只生成 IKEv2 conn**，不再因为缺 xauth 插件而整体失败；LuCI 依赖面板会用「可选/警告」提示，而不是红色错误；
- 如果既没有 IKEv1 也没启用 IKEv2，render 会拒绝生成配置并写日志，避免服务起来却谁都不能连。

> **对 iPhone 用户**：iOS 的「Cisco IPSec」配置走 IKEv1 + XAuth。如果系统 strongSwan 不带 IKEv1，这个配置会连不上；请改用「IKEv2 + 共享密钥」配置（本包 r19 起支持）。纯 IKEv2 环境不受影响。

### 安全提示

strongSwan 6.0.7 的后续版本（6.1.0 / 发行版 backport）修复了 11 个 CVE，其中包含 IKEv2 的认证绕过与 rekey use-after-free。装好系统后先确认包版本里带了补丁（例如 OpenWrt snapshot 的 `6.0.7-r13` 已包含，部分稳定版仍是 `-r1`）；长期停留在未打补丁的 `-r1` 不建议。

## 稳定性与漫游（服务端行为）

| 机制 | 值 | 作用 |
|---|---|---|
| DPD | `dpddelay=30s` / `dpdtimeout=150s` / `dpdaction=clear` | 客户端掉线/切网后约 2.5 分钟内清掉旧 SA，不再长期显示"幽灵在线" |
| MSS clamp | `firewall.VPN.mtu_fix=1` | ipsec0 MTU 1400，出方向 SYN 自动 clamp 到 1360，避免大包卡死 |
| WAN 重拨 | `/etc/hotplug.d/iface/90-ipsec-vpnd` | 公网地址变化时才重启 ipsec；普通 ifup/renew 不踢在线客户端 |
| 生命周期 | `lifetime=4h` / `ikelifetime=8h` | 减少弱网下每小时 rekey 的失败点 |
| 提案 | IKEv2 首选 AES-128-GCM/SHA-256；IKEv1 保留 AES-128-SHA1、3DES 回退 | 新客户端走更快/更强的套件，老客户端仍可连 |

> 这些是服务端自己的行为，不依赖 ImmortalWrt 的默认配置；安装到其它 OpenWrt/ImmortalWrt
> 设备时同样生效（MSS clamp 由本包的 uci-defaults / 升级脚本写入，DPD 等由渲染器生成）。

## 依赖

本包是纯 LuCI 前端 + 脚本，运行时依赖 strongSwan。**安装本包时会自动拉取下面这些依赖**（apk / ipk 的 `depends` 已声明）：

| 包 | 作用 |
|---|---|
| `strongswan-minimal` | strongSwan 最小集，含 charon、starter（`/usr/lib/ipsec/starter`）、stroke 插件 |
| `strongswan-default` | strongSwan 默认插件集（6.0.x 含 xauth-generic/des，保证 IKEv1 可用；6.1 的打包会按自身能力调整） |
| `strongswan-mod-xauth-generic` | **可选**（由 `strongswan-default` 间接引入）。6.1 起 strongSwan 默认关闭 IKEv1，该插件可能不存在，此时只提供 IKEv2 |
| `strongswan-mod-kernel-libipsec` | 内核态 IPsec（必需） |
| `strongswan-mod-des` | **可选**。3DES 加密插件，缺它只影响 3DES 回退，AES 不受影响 |
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
| 手机切网后显示"已连接"但打不开网页 | IKEv1 没有 MOBIKE，切网必然断；改用 IKEv2 配置（页面开启 `ikev2`），或等 DPD（约 150s）清掉旧 SA 后让客户端重连。`ipsec statusall` 能看到是否残留旧 SA |
| 网页能开，视频/大文件卡住 | 检查 MSS clamp 是否生效：`nft list ruleset \| grep ipsec0` 应有两条 maxseg；没有就 `uci set firewall.VPN.mtu_fix=1 && uci commit firewall && fw4 reload` |
| 依赖面板提示 IKEv1 不可用 | 系统 strongSwan 缺 `xauth-generic`（6.1 默认关闭 IKEv1）。IKEv2 不受影响；需要 IKEv1 就换回带 IKEv1 的 strongSwan 构建，或改用 IKEv2 客户端 |
| 升级后 IKEv2 开关没有/不生效 | `uci get ipsec-vpnd.ipsec.ikev2`（默认 `0`）；在 LuCI 勾选「启用 IKEv2」并保存应用，渲染器会加 `conn ikev2_psk` 并重启 ipsec |

## 许可证

Apache-2.0。详见 `LICENSE`。
