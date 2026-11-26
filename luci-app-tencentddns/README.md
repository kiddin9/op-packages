# 腾讯云 / DNSPod 动态域名解析插件 (`luci-app-tencentddns` v2.0)

专为 [OpenWrt 25.12](https://openwrt.org/releases/25.12/notes-25.12.0) 及其原生 `ucode` + 客户端 JavaScript（LuCI JSAPI）架构全新重写的腾讯云 [DNSPod](https://www.dnspod.cn/) 动态域名解析（DDNS）插件。

## 核心特性

1. **原生适配 OpenWrt / LuCI 25.12 新架构**
   - 彻底移除旧版 Lua Controller / CBI 与内置 `po2lmo` 历史遗留源码，无需安装 `luci-lua-runtime` 或 `luci-compat`。
   - 后端守护进程、CLI 工具与 [RPCD 接口](https://ucode-lang.org/ucode/)均采用纯 `ucode` 编写，直接对接 `libuci`、`libubus`、`libuloop` 与 `libmd`（`ucode-mod-digest`）。
   - 前端基于 LuCI 客户端 `view` / `form` / `rpc` / `poll` 组件构建，内置实时状态监控卡片、单规则一键同步、连通性与密钥鉴权诊断弹窗，以及支持级别过滤、搜索与导出的实时日志查看器。
   - 遵循 [LuCI `luci.mk` 构建规范](https://github.com/openwrt/luci/blob/master/luci.mk)，原生支持 OpenWrt 25.12 默认的 `apk` 包管理器及旧版 `opkg`，自动编译生成 `luci-i18n-tencentddns-zh-cn` 语言包。

2. **双协议与国内外双站支持**
   - **腾讯云 API 3.0（默认推荐）**：内置纯 `ucode` 实现的 [TC3-HMAC-SHA256 签名算法](https://cloud.tencent.com/document/product/1427/56189)，调用 `dnspod.tencentcloudapi.com`（中国内地站）或 `dnspod.intl.tencentcloudapi.com`（国际站）`2021-03-23` 版本接口（[DescribeRecordList](https://cloud.tencent.com/document/product/1427/56166)、[CreateRecord](https://www.tencentcloud.com/document/product/1157/49041)、[ModifyRecord](https://cloud.tencent.com/document/product/1427/56157)、[DeleteRecord](https://cloud.tencent.com/document/product/1427/56176)），支持腾讯云 CAM 子账号最小权限密钥。
   - **DNSPod 传统 Token（向下兼容）**：兼容 `dnsapi.cn` 与国际站 `api.dnspod.com` 的 `ID,Token` 鉴权方式，支持从 `v0.1.0` / `v0.2.0` 无缝平滑升级并自动迁移配置。

3. **多域名、IPv4/IPv6 双栈与内网 NAS 前缀合成**
   - 支持添加任意数量的域名与子域名规则，完整支持根域名（`@`）、泛解析（`*`）、多级主机头（如 `nas.home`）及分线路解析（默认、电信、联通、移动、教育网、境外或自定义线路）。
   - 单条规则支持 **仅 IPv4 (`A`)**、**仅 IPv6 (`AAAA`)** 或 **IPv4 + IPv6 双栈 (`A + AAAA`)** 同时维护，并允许单条规则覆盖独立的腾讯云账号密钥。
   - 针对运营商动态 IPv6 PD 前缀（`/56`、`/60`、`/64`）场景，除支持读取接口公网 GUA 地址外，还支持 **动态前缀 + 固定主机后缀合成（Prefix + Host Suffix）**，可直接为局域网下挂 NAS 或服务器绑定动态公网 IPv6 解析。

4. **事件驱动、零闪存磨损与安全加固**
   - 由 `procd` 托管 `uloop` 守护进程，通过 `ubus` 订阅 `network.interface.*` 网络变更事件（带 4 秒防抖），PPPoE 重拨或前缀刷新后即时触发同步，不再修改 `/etc/crontabs/root` 或动态生成脏 hotplug 脚本。
   - 运行态缓存（`/var/run/tencentddns/state.json`）存放于内存文件系统 `tmpfs`，避免旧版每次更新反复 `uci commit` 擦写路由器闪存。
   - 彻底移除旧版 `/etc/tencentddnsupload` 遥测上报脚本与命令拼接逻辑；所有 HTTPS 请求均通过 `0600` 权限临时配置文件调用 `curl`，杜绝 `/proc/<pid>/cmdline` 泄露密钥或命令注入风险，并通过细粒度 RPCD ACL 隔离读写权限。

## 目录结构

```text
tencentcloud-openwrt-plugin-ddns/
├── Makefile                                              # OpenWrt 25.12 luci.mk 标准构建脚本
├── LICENSE                                               # Apache-2.0 许可证
├── README.md                                             # 项目说明文档
├── htdocs/luci-static/resources/view/tencentddns/
│   ├── config.js                                         # 实时状态面板 + 全局配置 + 多域名规则视图
│   └── log.js                                            # 实时运行日志筛选、搜索与导出视图
├── po/
│   ├── templates/tencentddns.pot                         # 翻译模板
│   └── zh_Hans/tencentddns.po                            # 简体中文本地化翻译
└── root/
    ├── etc/
    │   ├── config/tencentddns                            # 默认 UCI 配置文件
    │   ├── init.d/tencentddns                            # procd 服务脚本
    │   └── uci-defaults/40-luci-tencentddns              # 旧版配置自动迁移与 ucitrack 注册脚本
    └── usr/
        ├── bin/tencentddns                               # ucode 守护进程与 CLI 命令行工具
        ├── sbin/tencentddns                              # 向下兼容软链接 -> ../bin/tencentddns
        └── share/
            ├── luci/menu.d/luci-app-tencentddns.json     # LuCI 菜单路由定义
            ├── rpcd/acl.d/luci-app-tencentddns.json      # RPCD 最小权限 ACL 定义
            ├── rpcd/ucode/luci.tencentddns.uc            # RPCD ucode 后端服务接口
            └── ucode/tencentddns/engine.uc               # DDNS 核心同步与 TC3 签名引擎
```

## 编译与安装

### 1. 源码编译（OpenWrt 25.12 SDK / Buildroot）

```bash
# 在 OpenWrt 源码根目录克隆至 package 目录
git clone https://github.com/Tencent-Cloud-Plugins/tencentcloud-openwrt-plugin-ddns.git package/luci-app-tencentddns

# 选择软件包：LuCI -> 3. Applications -> luci-app-tencentddns
make menuconfig

# 编译软件包（OpenWrt 25.12 默认生成 .apk 包）
make package/luci-app-tencentddns/compile V=s
```

### 2. 路由器安装

在 OpenWrt 25.12（`apk` 包管理器）环境下安装：

```bash
apk add --allow-untrusted luci-app-tencentddns*.apk luci-i18n-tencentddns-zh-cn*.apk
```

在旧版 `opkg` 环境下安装：

```bash
opkg install luci-app-tencentddns*.ipk luci-i18n-tencentddns-zh-cn*.ipk
```

## 腾讯云 CAM 最小权限配置建议

在 [腾讯云访问管理（CAM）API 密钥控制台](https://console.cloud.tencent.com/cam/capi) 使用子账号密钥时，仅需为该子账号关联预设策略 `QcloudDNSPodFullAccess`（或自定义仅针对指定域名的 `dnspod:DescribeRecordList`、`dnspod:CreateRecord`、`dnspod:ModifyRecord`、`dnspod:DeleteRecord` 权限），即可安全完成动态域名解析。

## 命令行（CLI）用法

插件提供 `/usr/bin/tencentddns` 命令行工具便于排障与脚本联动：

```bash
# 查看当前服务及所有规则状态（JSON 输出）
tencentddns status

# 立即同步所有已启用规则（带 --force 强制刷新远端记录）
tencentddns sync --force

# 仅针对指定 UCI 规则段测试本机 IP 获取与腾讯云 API 鉴权连通性
tencentddns test <section_id>

# 清空运行日志
tencentddns clear-log
```
