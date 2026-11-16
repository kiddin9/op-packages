# luci-app-dae

dae 内核的 OpenWrt / ImmortalWrt 软件包与 LuCI 页面。面板（doona）的源码在
[szwjp/doona](https://github.com/szwjp/doona)，但**它的包在这里构建**：本仓库的发布从
doona 的发布归档重新打包，三个包（引擎、面板、LuCI 页面）同一条发布、同一组版本。

仓库产出五个包：

| 包 | 内容 |
|---|---|
| `dae` | 守护进程，来自 [szwjp/dae](https://github.com/szwjp/dae) 的发布二进制（带 native HTTP 控制面），加上 OpenWrt 侧的 init/UCI/配置模板与手动 Geo 数据更新脚本。 |
| `luci-app-dae` | LuCI 入口页与服务后端（rpcd）：状态、启停、API 密钥、打开面板、手动更新 Geo 数据。依赖 `dae` 与 `doona`。 |
| `luci-i18n-dae-zh-cn` / `luci-i18n-dae-zh-tw` | LuCI 页面的简体 / 繁体中文翻译。 |
| `doona` | 面板本体：把 szwjp/doona 发布的归档（摘要固定在 `doona/digests.txt`）装到 `/usr/share/doona`。字体归档不在本仓库打包。 |

面板由 dae 自己托管：dae 把 `/usr/share/doona` 挂在 `/ui/`，API 仍要 Token。

## 安装

### 系统要求

需要带 **apk v3** 的系统，例如 ImmortalWrt 25.12 及更新版本；仍用 opkg 的
OpenWrt 24.10 及更早版本装不上这些包。内核需要带 BTF（见「架构」一节）。

```sh
apk --version   # 需要 apk-tools 3.x
```

### 下载并安装

apk v3 的 `apk add` 只认本地文件，不接受 URL，所以先把包下载下来再装。
`luci-app-dae` 依赖 `doona`，**三个文件要在同一条命令里**交给 apk。三个包全部由本仓库
的发布产出——面板由本仓库从 szwjp/doona 的发布归档重新打包（版本与摘要固定在
`doona/digests.txt`），所以不需要再去另一个仓库挑版本：

```sh
cd /tmp
# 引擎：按设备架构选一个
wget -O dae.apk \
  https://github.com/szwjp/luci-app-dae/releases/latest/download/dae-2.1.1-r15-x86_64.apk
# 面板
wget -O doona.apk \
  https://github.com/szwjp/luci-app-dae/releases/latest/download/doona-0.1.0-r18.apk
# LuCI 页面
wget -O luci-app-dae.apk \
  https://github.com/szwjp/luci-app-dae/releases/latest/download/luci-app-dae-2026.11.14-r8.apk
apk add --allow-untrusted ./dae.apk ./doona.apk ./luci-app-dae.apk
```

从旧版本升级时，`doona` 包会被同样包名的本仓库构建替换；面板文件仍装在
`/usr/share/doona`，dae 的 `ui` 设置不用改。

守护进程按架构分发：

| 设备架构 | 包 |
|---|---|
| x86_64 | `dae-<ver>-x86_64.apk` |
| arm64 | `dae-<ver>-aarch64_generic.apk` |
| riscv64 | `dae-<ver>-riscv64_generic.apk` |

可选包：

```sh
# LuCI 中文翻译，界面语言随浏览器 Accept-Language 走
apk add --allow-untrusted ./luci-i18n-dae-zh-cn-<ver>.apk
```

面板不带字体归档（Noto Sans TC/SC），缺少时回退系统字体。需要自带字体时，仍可从
szwjp/doona 的发布里装 `doona-fonts-<ver>.apk`。

### 启用服务

服务**默认禁用**。先按设备改好配置再启用：`/etc/dae/config.dae` 是入口文件，
模块放在 `/etc/dae/config.d/`，LAN/WAN 接口在 `/etc/dae/config.d/global.dae` 里指定。

```sh
uci set dae.main.enabled=1
uci commit dae
/etc/init.d/dae start
```

也可以直接在 LuCI 页面上点「启动」，它会一并把 `enabled` 置为 1、设为开机自启并
启动服务。要关掉开机自启而不停服务，用 *系统 → 启动项* 里的开关（或
`/etc/init.d/dae disable`）。

API 监听地址与密钥放在 UCI 里，不写进配置文件。首次成功启动时服务会自动生成一个
密钥并写回：

```sh
uci get dae.main.api_secret
```

注意：**密钥只在服务真正启动时生成**。`enabled=0` 时启动会被拒绝，也就不会生成。

| UCI 选项 | 默认值 | 含义 |
|---|---|---|
| `enabled` | `0` | 是否启用服务 |
| `config_file` | `/etc/dae/config.dae` | 运行的配置文件 |
| `api_listen` | `0.0.0.0:9527` | native API 监听地址 |
| `api_secret` | 首次启动自动生成 | API 的 Bearer 令牌 |
| `api_write` | `1` | 允许面板写配置。默认打开，装完面板即可用；页面「服务」标签上有同名开关，改完会自动重启服务 |
| `lan_interface` | 空 | 覆盖 LAN 接口名，默认从 `config.d/global.dae` 读取 |

面板访问地址也可以直接在 LuCI 页面上改：页面的「面板访问地址」一行填好后点「确定」，会立即保存并重启服务；
新地址起不来时会自动恢复旧地址并重启，不会把面板留在不可达的状态。等价的 UCI 写法：

```sh
uci set dae.main.api_listen='192.168.1.1:9527'
uci set dae.main.api_write='1'
uci commit dae
/etc/init.d/dae restart
```

`api_listen` 必须是**数值地址加端口**（`0.0.0.0:9527`、`192.168.1.1:9527`）。
`localhost` 会被改写成 `127.0.0.1`，其它主机名不接受——dae 自己要求数值地址。

LuCI 页面显示和编辑的是**面板访问地址**（如 `http://192.168.1.1:9527/ui/`）；`api_listen` 是其背后的
bind 地址，普通使用不需要关心。面板由 dae 托管时，doona 的后端网址固定为当前页面地址，随它一起变化。

### 安全：API 监听与明文 HTTP

`api_listen` 默认是 `0.0.0.0:9527`，dae 的 native API 与面板都是**明文 HTTP**：
`api_secret` 和面板使用的 Bearer 令牌在局域网里明文传输，浏览器还会把它存下来。
默认保留 `0.0.0.0` 是为了装完就能从 LAN 打开面板，代价是：

* **密钥等同于 dae 的控制权。** `api_write=1`（默认）时，拿到密钥的人可以改分流配置。
  只想要只读面板就关掉「面板写入」：`uci set dae.main.api_write='0'`。
* OpenWrt 默认防火墙拒绝 WAN 入站，所以暴露面主要是 LAN。
* 只在本机用面板时，把监听改成回环（本机浏览器还需要 SSH 端口转发）：
  `uci set dae.main.api_listen='127.0.0.1:9527'`。
* 需要 LAN 内多台设备访问时，建议监听 LAN 地址并用 HTTPS 反代，不要把 9527 直接放到公网。

## 面板

* LuCI 入口：*服务 → dae*。页面有两个标签：
  - **服务**：运行状态、开机自启状态、启动/停止/重启、面板访问地址（可编辑并立即生效）、API 密钥（显示/复制）、打开面板；
  - **Geo 数据**：两个数据文件的文件名/大小/修改时间，手动更新与进度日志。
* 直接访问：`http://<路由器地址>:9527/ui/`。
* 面板首次打开时会要求填写密钥，之后由浏览器记住；后端地址固定为当前页面地址。密钥也可以
  `uci get dae.main.api_secret` 读取。
* 面板的「出站模式」（规则/直连/全局）写在含 `routing` 段的文件里，也就是
  `config.d/routing.dae`；入口文件 `config.dae` 只读，面板不会去改它。
* 面板能不能改配置取决于 `api_write`，**默认是开的**。关掉后 doona 会把整个配置、
  节点、组与规则显示为只读（「配置为只读」），只能在面板里看。开关就在页面的
  **面板写入** 一行：切换后服务会重启一次，面板需要刷新页面才能看到新的写入状态。来源是 UCI 的
  `dae.main.api_write`，由 init 脚本写进 `/etc/dae/api.dae`，所以别直接改那个文件
  ——每次启动都会被 UCI 的值覆盖。

菜单对任何已登录的 LuCI 用户可见，实际能做什么由 rpcd ACL 决定：只授
`luci-app-dae-read` 的账号只能看状态与 Geo 信息，`luci-app-dae-admin` 才能启停、
更新 Geo 数据、读取密钥。

LuCI 页面通过 rpcd 的 exec 后端读取状态。软件包安装后会自动 reload rpcd；
如果页面报"读取 dae 服务状态失败"，执行 `/etc/init.d/rpcd reload` 即可。

### 启动项页面

服务在 LuCI 的*系统 → 启动项*里以 `99 dae` 出现，页面上的启用/禁用按钮就是
开机自启开关（LuCI 页面本身不再放这个开关，避免两处状态源）。

「服务」标签上的「开机自启 / 不自启」徽标读的就是 `S99dae` 这个启动链接，
和上面的开关保持同一状态源；它不影响已经启动的服务。

rpcd 读取 init 脚本时只看开头若干行里的 `USE_PROCD`、`START`、`STOP`，
所以这三行必须留在脚本的前 11 行内。

## Geo 数据

规则里的 `geosite:` 与 `geoip:` 用到的数据文件是 `geoip.dat` 与 `geosite.dat`，
位于 `/usr/share/v2ray`（`v2ray-geoip` / `v2ray-geosite` 两个包提供）。dae 只在
启动时读取它们，所以更新后要重启 dae。

更新是**手动**的：LuCI 页面的「Geo 数据」标签点「立即更新」，或命令行：

```sh
/usr/bin/dae-geo-update
```

脚本先解析上游 `release` 分支到具体 commit，再按 commit 取两个文件和它们的
`.sha256sum`，保证两者来自同一快照：

```
https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@<commit>/geoip.dat
https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@<commit>/geosite.dat
```

行为要点：

* 下载带 Range 头（实测普通 GET 只有 16KB/s，显式 Range 是 MB/s 级）；中断后
  下一轮用 `curl -C -` 续传。
* 完整性靠上游同目录的 `<file>.sha256sum` 判定——CDN 的 `content-length` 和
  `content-range` 不可信。校验不过会丢掉重下，最多三轮；仍不过就放弃本次更新、
  保留旧文件。只有上游没提供 sha256 时，才在一次完整传输之后按大小和文件头放行。
* 换文件是先在目标目录写临时文件再改名，掉电不会留下半个文件。之后重启 dae；
  没起来就只把本次换过的文件放回去再重启一次。
* 上一版文件备份在 `/etc/dae/geo-backup/`。
* 日志在 `/var/log/dae-geo-update.log`，同时进 syslog（`logread | grep dae-geo-update`）。
  `/var` 是 tmpfs，重启后日志不保留。
* 进度写在 `/var/run/dae-geo-update.state`，LuCI 页面靠它显示「更新中/成功/失败」。
* 这两个文件归 apk 包所有，`apk upgrade v2ray-geoip v2ray-geosite` 会用 feed
  里的版本覆盖它们；下一次手动更新会装回更新的版本。

## ICMP 重定向

dae 拒绝挂到会发送 ICMP 重定向的接口上，重定向会和 dae 装的规则打架。启动
脚本会在 dae 运行期间把 `all` 与 LAN 接口的 `send_redirects` 置 0，停止时按启动
前的值恢复，所以不用手工改 sysctl。LAN 接口名取自 UCI 的 `lan_interface`，没有
设置时从 `config.d/global.dae` 里读。

## 架构

`dae` 包发布的是预编译二进制，所以每个架构一个包：x86_64、arm64、riscv64。
二进制来自 [szwjp/dae](https://github.com/szwjp/dae) 的发布产物，CI 取下来校验
摘要后重新打包，不重复编译。LuCI 包、翻译包与面板包都是纯静态构建，各架构通用。

riscv64 的二进制按 RISC-V 2023 profile（rva23u64）构建，若设备内核太老跑不起来，
需要换用上游的其它 profile 或自行编译。

eBPF 程序需要内核带 BTF。ImmortalWrt 与 OpenWrt 24.10+ 的内核自带
（`/sys/kernel/btf/vmlinux`）；更老的内核需要先装 `vmlinux-btf` 包。

### 接口配置

`/etc/dae/config.d/global.dae` 里的两个接口按设备形态填：

* `lan_interface`：客户端所在的网桥，OpenWrt 默认是 `br-lan`。
* `wan_interface`：出方向流量离开的网卡。默认写 `auto`，由 dae 按默认路由解析；
  **单网口设备**（唯一那个口就是 LAN 口，没有 WAN 口）要把它留空。

开机时 dae 会先等默认路由出现（最多 30 秒）再启动，避免 PPPoE 还没拨上时就挂住
LAN；`wan_interface` 留空的单网口设备不等待。

## 构建

软件包用 `apk-tools` 直接打包，不走 OpenWrt SDK：`.github/build-pkg.sh` 组装
staging 目录，`apk mkpkg` 写出容器格式。各包的 `Makefile` 只是这个脚本读取的
元数据，没有 `include luci.mk`，不能直接放进 OpenWrt 的 `package/` 目录参与官方构建。

守护进程二进制**不在本仓库里**，构建前从引擎发布取。`dae/digests.txt` 固定了三个
架构归档的 sha256，构建会拒绝不匹配的归档；升级引擎时该文件里的 `tag` 行和
`.github/workflows/build.yml` 的 `DAE_BINARY_TAG` 必须一起改：

```sh
DAE_TAG=v2026.11.14-nativeapi-r15   # 以 dae/digests.txt 的 tag 行为准
curl -fsSL -o dae.tar.xz \
  "https://github.com/szwjp/dae/releases/download/$DAE_TAG/dae-linux-x86_64.tar.xz"
tar -xJf dae.tar.xz
mkdir -p dae/assets/x86_64
install -m0755 usr/bin/dae dae/assets/x86_64/dae
```

然后打包（`PKG_ASSET_DIR` 指向取下来的那一份）：

```sh
PKG_ASSET_DIR=assets/x86_64 PKG_ARCH_OVERRIDE=x86_64 \
  fakeroot bash .github/build-pkg.sh dae
fakeroot bash .github/build-pkg.sh luci-app-dae
fakeroot bash .github/build-pkg.sh doona   # 先取面板归档到 doona/assets
```

需要 `apk` (apk-tools v3) 与 `po2lmo`（翻译包）；CI 里两者都编译好后使用。

面板从 [szwjp/doona](https://github.com/szwjp/doona) 的发布归档打包：`doona/digests.txt`
固定发布 tag 与该归档的 sha256，CI 校验后解到 `doona/assets/`，再由 `build-pkg.sh doona`
装到 `/usr/share/doona`。面板界面本身仍在上游仓库开发。

包里的文件归 root。在 macOS 上本地打包时没有 fakeroot，`chown` 会失败，包会带上
构建者的 uid（安装后显示为 nobody）；构建脚本会对此告警。正式出包走 CI（Linux +
fakeroot），或者手动在 Linux 上跑。

## 许可

* `dae`：AGPL-3.0-only。本仓库分发的二进制来自 `szwjp/dae` 的发布，对应源码就是
  该发布 tag 的源码树。
* `luci-app-dae`：GPL-3.0-only。
* `doona`：GPL-3.0-only，许可证与第三方声明随包安装在 `/usr/share/doc/doona/`。

AGPL 与 GPL 兼容。各包是独立的程序，通过 HTTP 通信。
