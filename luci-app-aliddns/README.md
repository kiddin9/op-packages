# luci-app-aliddns (v2.1.0)
# Native OpenWrt LuCI 25.12 Alibaba Cloud Dynamic DNS Client

**`luci-app-aliddns` v2.1.0** 是面向 **OpenWrt 25.12+** 全新重写的阿里云云解析（AliDNS）动态域名客户端与 LuCI 管理应用。项目彻底移除了传统的 Lua CBI、`luci-compat`、内置 `po2lmo` C 源码与 `crontabs` 轮询脚本，全面采用 **原生 `ucode`（`uloop` 事件循环 + `ubus` 总线监听 + `rpcd` 插件）+ 客户端 JavaScript (`L.view` / `form.Map`)** 架构，并深度强化了家庭实验室（NAS/服务器 IPv6 直通）与运维交互体验。

## 核心功能与用户体验亮点

### 1. OpenWrt / LuCI 25.12 原生架构
- **零 Lua 纯 JS + `ucode` 架构**：兼容 OpenWrt 25.12 默认 `apk` 与传统 `opkg` 构建体系，适配 Bootstrap、Argon、Material 与 Footstrap 亮/暗双色主题。
- **`procd` + `uloop` 事件驱动常驻守护**：支持 **1–1440 分钟** 精确巡检，直接订阅 `netifd` `network.interface` 总线事件并配合 **5 秒合并防抖定时器** + **失败阶梯快速重试（30s / 60s / 120s）**，彻底解决开机拨号初期或双栈重拨时的同步竞态与静默漏更。
- **零依赖内存级 HMAC-SHA1 与防泄露通信**：内置纯 `ucode` 64 位整型 SHA-1 / HMAC-SHA1 签名（若系统安装了 `ucode-mod-digest` 自动切换 C 加速），省去 600KB+ `openssl-util` 依赖；全程 `https://alidns.aliyuncs.com/` 加密通信并通过 `0600` 临时文件调用 `curl -K`，杜绝在 `/proc/<pid>/cmdline`（`ps ww`）暴露密钥。

### 2. 深度场景功能拓展
- **在线凭证连通性校验与托管域名自动拉取**：填写 AccessKey 后无需先保存即可一键实测阿里云连通性与延迟，自动拉取当前账号下托管的全部主域名填入下拉候选列表，并将 `SignatureDoesNotMatch`、`Forbidden.RAM`、`InvalidTimeStamp.Expired`、免费版 TTL 超限等错误码翻译为直观中文排障建议。
- **内网 NAS / 服务器 IPv6 动态前缀直通**：除路由器接口公网 IPv6 与公网 API 探测外，新增两种内网主机直通模式（无需额外安装大体积第三方二进制）：
  - **动态前缀 + 固定后缀拼接（`suffix`）**：自动提取运营商动态下发的 `/64` 公网前缀并与固定主机后缀（如 `::8888`）按位合成 128 位公网地址。
  - **按内网设备 MAC 自动发现（`mac`）**：自动检索内核 `ip -6 neigh` 邻居表获取指定 MAC 设备的活跃 `2000::/3` 公网单播地址，并支持设备休眠时自动启用 **SLAAC EUI-64 回退计算**。
- **变更与异常 Webhook 通知推送**：内置适配 **Bark、Server 酱、钉钉机器人、飞书机器人、企业微信机器人** 及自定义 GET/POST JSON Webhook，支持一键发送测试通知与异常 30 分钟防刷屏冷却。

### 3. 交互细节打磨
- **实时接口 IP 预览**：在 IPv4 / IPv6 接口下拉框中直接展示各网络接口当前获取到的实时 IPv4、公网 IPv6 或 PD 前缀（如 `wan (223.5.x.x)`、`wan6 (240e:...::1)`），选错接口一目了然。
- **单域名独立同步与一键复制**：状态监控面板支持全量同步与**单条域名独立即时同步**，点击任意域名或 IP 即可一键复制到剪贴板（兼容局域网纯 HTTP 会话），并内置系统 NTP 时间未同步预警。
- **结构化交互式日志查看器**：支持错误/警告/更新成功语义着色、按级别过滤、按域名/IP 关键字实时检索、暂停刷新与一键导出 `.log` 文件。

## 目录结构

```text
luci-app-aliddns/
├── LICENSE
├── Makefile
├── README.md
├── htdocs/
│   └── luci-static/
│       └── resources/
│           ├── aliddns/
│           │   └── aliddns.css         # 自适应亮暗主题样式表
│           └── view/
│               └── aliddns/
│                   ├── config.js       # 实时监控面板、全局设置、通知与多域名管理视图
│                   └── log.js          # 语义着色、过滤检索与导出日志视图
├── po/
│   ├── templates/
│   │   └── aliddns.pot
│   └── zh_Hans/
│       └── aliddns.po                  # 简体中文语言包（编译产出 luci-i18n-aliddns-zh-cn）
└── root/
    ├── etc/
    │   ├── config/
    │   │   └── aliddns                 # 默认 UCI 配置文件 (0600)
    │   ├── hotplug.d/
    │   │   └── iface/
    │   │       └── 80-aliddns          # 静态接口事件通知脚本
    │   ├── init.d/
    │   │   └── aliddns                 # procd 服务脚本（带 ucode 周期 GC）
    │   └── uci-defaults/
    │       └── 40_luci-aliddns         # 旧版配置无缝迁移与 ucitrack 注册
    └── usr/
        ├── sbin/
        │   └── aliddns                 # 纯 ucode 守护进程与 CLI 同步引擎
        └── share/
            ├── luci/
            │   └── menu.d/
            │       └── luci-app-aliddns.json
            └── rpcd/
                ├── acl.d/
                │   └── luci-app-aliddns.json
                └── ucode/
                    └── luci.aliddns    # 原生 rpcd ucode 插件
```

## 编译与命令行用法

```bash
# 编译（兼容 OpenWrt 25.12 apk 与传统 opkg）
git clone https://github.com/honwen/luci-app-aliddns.git package/luci-app-aliddns
make package/luci-app-aliddns/compile V=s

# 命令行操作
/usr/sbin/aliddns --once                 # 增量检查全部启用域名
/usr/sbin/aliddns --force                # 强制核对并同步全部启用域名
/usr/sbin/aliddns --force --record main  # 仅强制同步指定记录段
/usr/sbin/aliddns --verify               # 验证已配置的阿里云 AccessKey 并列出托管域名
/usr/sbin/aliddns --test-notify          # 发送测试通知消息
/usr/sbin/aliddns --status               # 输出当前服务与解析状态 JSON
```

## 相比原版（v0.4.2）已修复的全部缺陷清单

| 编号 | 缺陷类别 | 原版问题根因 | v2.1.0 修复方案 |
| :--- | :--- | :--- | :--- |
| 1 | LuCI 25.12 兼容崩溃 | 依赖已移除的 `/usr/lib/lua/luci/controller` 与 Lua CBI | 全面迁移至客户端 JS (`view/aliddns/*.js`) + `menu.d` + `acl.d` + 原生 `rpcd` `ucode` 插件 |
| 2 | 构建失败 (`po2lmo`) | 内置 2016 年旧版 C 源码且未声明 `luci-base/host`，在 24.10/25.12 编译报错 | 接入官方 `luci.mk` 构建体系，原生支持 OpenWrt 25.12 `apk` 与 `opkg` |
| 3 | API 签名重放报错 | 单次运行多次请求复用同一个 `SignatureNonce=$timestamp`，触发 `SignatureNonceUsed` | 每次请求独立读取 `/dev/urandom` 生成 128 位随机 `SignatureNonce` 与实时 UTC 时间戳 |
| 4 | 签名参数字典序违规 | 手工拼接查询串，新增 `TTL`/`Line` 或特殊字符时触发 `SignatureDoesNotMatch` | 严格按 ASCII 字节序排序参数并执行标准 RFC 3986 编码（保留 `~`，空格编码为 `%20`） |
| 5 | 通配符与特殊字符漏洞 | `urlencode` 中未加引号遍历 `$(echo -n $1 ...)`，遇到 `*` 子域名会展开当前目录全部文件名，遇到空格直接丢失 | 纯 `ucode` 字节级 `ord()` 编码，彻底消除 Shell 分词与通配符展开 |
| 6 | 根域名 `@` 解析异常 | `sub_domain` 为空时生成 `.example.com` 且 `RR` 为空导致 API 拒绝 | 自动归一化根记录为 `RR=@`、`SubDomain=@.example.com`，并自动剥离误填的重复主域名后缀 |
| 7 | 未设双栈开关时脚本崩溃 | 默认配置未定义 `ipv4`/`ipv6`，`[ $ipv4 -eq 1 ]` 因空变量触发语法错误退出，且关闭某协议栈仍照常请求外网测速接口 | 严格的布尔解析，仅对已启用的协议栈发起本地/公网地址获取 |
| 8 | 静默吞错谎报成功 | `update_record $rrid >/dev/null 2>&1` 丢弃响应，密钥错误或记录被删仍打印 `# UPDATED` | 完整解析阿里云 JSON 响应与 `Code`/`Message` 错误码并映射为中文排障提示 |
| 9 | 先删后增导致断网与多记录 | `clean=1` 先删除全部同名记录再新建，中途网络抖动即造成域名 NXDOMAIN 解析中断，且误删其他运营商线路记录 | 按同类型+同线路精确匹配，原地无感更新首条主记录后再清理多余重复记录 |
| 10 | 并发无锁竞争 | `init` 启动后台任务、`hotplug` 与 `cron` 同时运行产生多条重复记录 | 原子目录锁 `/var/run/aliddns/sync.lock`（带僵死 PID 自愈）+ `uloop` 单例队列调度 |
| 11 | `cron` 静默失效与间隔失真 | 系统启动时若 `crontabs` 为空则 `crond` 不启动，`init.d` 检查失败不重载；`*/45` 跨整点变成 45m/15m 不均匀触发 | 改用 `procd` 托管的 `ucode` `uloop.interval` 常驻守护进程，精确支持 1–1440 分钟周期与失败阶梯重试 |
| 12 | `hotplug` 语法错误与闪存磨损 | 每次启动往 `/etc/hotplug.d/iface` 写入带错误 `#!/bin/sh /etc/rc.common` 头的脚本且硬编码仅监听 `wan` | 静态合规 `hotplug` 脚本 + `ubus` `network.interface` 监听 + 5 秒防抖合并，原生适配 `wan6`/`wan_6`/多拨 |
| 13 | IPv6 内网地址误上报与 `wan_6` 缺失 | 正则误匹配 `fe80::` 链路本地与 `fd00::` ULA 地址，且无法读取 PPPoE 动态 `wan_6` 与 PD `local-address` | 基于 `iptoarr`/`arrtoip` 严格限定 `2000::/3` 公网单播地址并支持前缀+后缀合成与内网 MAC 自动发现 |
| 14 | 代理分流与无超时卡死 | `curl` 未加 `--max-time` 与 `--noproxy`，挂死进程或将代理节点海外 IP 误同步至阿里云 | 强制 `-4`/`-6`、`--noproxy '*'`、`--max-time`、公网单播合法性过滤（拦截 HTML 报错页/私网 IP），支持绑定物理出口网卡 |
| 15 | 密钥明文泄露风险 | 明文 `http://` 请求 API、`openssl -hmac` 与 URL 在 `ps ww` 暴露密钥、LuCI 输入框明文显示 Secret | 全程 HTTPS TLS 校验、纯内存 HMAC-SHA1、`0600` 临时文件 `curl -K` 隐藏参数、前端 `password = true` 掩码保护 |
| 16 | 日志满 240 行全量清空 | 达到 240 行直接 `rm -f` 删空全部历史日志，丢失故障现场 | 环形截断保留最近 300 条日志并原子重命名落盘 |
| 17 | 保存应用竞态与僵尸句柄 | CBI 渲染阶段通过 `io.popen("/etc/init.d/aliddns restart")` 未关闭句柄且早于 UCI 落盘执行 | 通过标准 `procd_add_reload_trigger` 与 `ucitrack` 在配置提交后有序重载 |
| 18 | 卸载与实时安装生效缺陷 | `prerm` 未判断 `$IPKG_INSTROOT`；`postinst` 未重启 `rpcd` 导致新 `.uc` 插件不注册 | `postinst` / `prerm` 严格检查 `$IPKG_INSTROOT`，安装后自动重启 `rpcd` 立即注册 `luci.aliddns` |
