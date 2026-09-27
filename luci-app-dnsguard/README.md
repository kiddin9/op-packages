# luci-app-dnsguard —— DNS 防绕过（LuCI 应用）

把局域网内「绕过 AdGuard Home 的 DNS」拉回本机解析：**53 明文用透明重定向**（客户端无感），
**853 DoT 用阻断**（逼其回落 53），**DoH 专用 IP** 可选阻断。全部可在 WebUI 开关。

- 入口：**LuCI → 服务 → DNS 防绕过**（`admin/services/dnsguard`）
- 配置：`/etc/config/dnsguard`
- 渲染产物：`/etc/nftables.d/20-dns-guard.nft`（由 fw4 在 `inet/fw4` 表上下文内 include）
- 回滚点：`/mnt/data/backup-dnsguard/<时间戳>/`（含 `20-dns-guard.nft` + `dnsguard.uci`）

## 为什么需要它

OpenWrt 自带的「DNS 重定向」开关重定向到的是 **dnsmasq 自己的端口**。本机架构里 dnsmasq 已退居
5353、53 由 AdGuard Home 接管，所以打开那个开关会让**全屋绕过 AGH、广告过滤失效**；
而且它只匹配 `udp dport 53`，TCP 不覆盖。本应用是它的正确替代实现：

| 项 | OpenWrt 自带开关 | 本应用 |
|---|---|---|
| 重定向目标 | dnsmasq 的 `port`（本机 = 5353）❌ | AdGuard Home 的 `:53` ✅ |
| 协议覆盖 | 仅 UDP | TCP + UDP |
| 目标过滤 | 无（跨子网也劫持） | 排除内网/保留段 + 可配设备例外 |
| 前置校验 | 无 | `nft -c` + `fw4 check` + 应用后核对链 |
| 回滚 | 无 | 回滚点 + 延迟自动回滚 |

## 文件清单

| 路径（设备） | 作用 |
|---|---|
| `/etc/config/dnsguard` | UCI 配置（`main` / `limits` 两个节） |
| `/usr/bin/dnsguard-apply` | **唯一写防火墙的地方**：UCI → 渲染 → 校验 → 落盘 → `fw4 reload` |
| `/usr/bin/dnsguard-selftest` | 健康自检（AGH 进程 / :53 监听 / 解析 / 链与计数 / 回滚倒计时） |
| `/usr/bin/dnsguard-rollback` | 回滚点管理 + 延迟自动回滚 |
| `/etc/init.d/dnsguard` | `reload` / `stop`（boot 为空实现，开机不需要它做事） |
| `controller/dnsguard.lua`、`view/dnsguard/main.htm`、`acl.d/luci-app-dnsguard.json` | 界面 |

## 关键技术点

### 1. 规则写在哪、优先级怎么排

`/etc/nftables.d/*.nft` 的文件是**被 include 进 `table inet fw4` 内部**的（见设备上 `/etc/nftables.d/README`），
所以文件里只写 `set` / `chain`，**不要写 `table` 包裹**。

fw4 自己的 DNAT 链是 `dstnat`（`priority dstnat` = **-100**）。我们的重定向链用 `priority -105`，
在它**之前**执行：

```nft
chain dns_guard_redirect {
	type nat hook prerouting priority -105; policy accept;
	iifname "br-lan" meta l4proto { tcp, udp } th dport 53 ip  daddr != @dns_never_hijack4 counter redirect to :53
	iifname "br-lan" meta l4proto { tcp, udp } th dport 53 ip6 daddr != @dns_never_hijack6 counter redirect to :53
}
```

`redirect to :53`（只给端口）= 改道到本机 :53。目标写死 AGH 的端口，**不是** dnsmasq 的 5353。

### 2. 「永不劫持」集合里不要放 192.168.0.0/16

默认排除 `192.168.1.0/24`、`172.16.0.0/12`、`127.0.0.0/8`、`169.254.0.0/16`、`224.0.0.0/4`。

> ⚠️ 仓库里带的默认配置用的是 `192.168.1.0/24` 这个**占位网段**。`install.sh` 在首次安装时会自动读
> `br-lan` 的 IPv4 地址、算出真实网段并替换它（不影响已有配置）。如果你不是用 `install.sh` 装的，
> 请到界面把「永不劫持（IPv4）」改成你自己的 LAN 网段。
**故意不排除整个 `192.168.0.0/16`**：红米 K80 的静态 DNS 指向旧网段 `192.168.5.1`（该网段已不存在），
若把 192.168/16 全排除，它会继续"DNS 打空"；现在被重定向后反而恢复正常解析。

### 3. 安全闸门与三层校验

- **闸门**：`redirect53=1` 而 `AdGuardHome` 进程不存在 → **直接拒绝应用**（exit 3，不落盘）
- **校验 1**：渲染片段包进临时表名做 `nft -c`，不通过绝不落盘
- **校验 2**：落盘后 `fw4 check`（fw4 自带的全量校验器），不通过立即还原旧文件
- **校验 3**：`fw4 reload` 后核对 `dns_guard_redirect` 链真的存在，不存在则还原 + 重载

### 4. 延迟自动回滚

DNS 是全家网的命门：改错了人可能连这台路由器都**访问不到**（域名解析不了）。
所以「53 重定向」从**关改到开**时，控制器会：

1. 先把**当前 UCI + 当前规则文件**拍成回滚点（必须在写 UCI **之前**拍，否则快照里就是新配置）
2. 起一个 `setsid` 倒计时进程（默认 10 分钟）
3. 到点未点「确认保留」→ 自动还原 UCI + 规则文件 + `fw4 reload`

`/tmp/.dnsguard-rollback` 是唯一真相：`--disarm` 删掉它，倒计时进程醒来发现记录没了就什么都不做（僵尸进程无害）。

### 5. 幂等

文件头有「生成时间」，所以比较时**先剔除该行**再 `cmp`——否则每次都比出差异、白白重载一次防火墙。
验收：连跑两次 `dnsguard-apply`，第二次必须报 `file:"unchanged"`。

## 命令行速查

```sh
# 渲染并应用（输出一行 JSON）
/usr/bin/dnsguard-apply

# 只渲染，不碰防火墙（界面「预览将要生成的规则」用的就是它）
/usr/bin/dnsguard-apply --render-only --out /tmp/x.nft

# 健康自检
/usr/bin/dnsguard-selftest

# 回滚
/usr/bin/dnsguard-rollback                # 列出回滚点
/usr/bin/dnsguard-rollback latest         # 还原到最近一个
/usr/bin/dnsguard-rollback 20260926-182913
/usr/bin/dnsguard-rollback --arm 10       # 挂 10 分钟自动回滚
/usr/bin/dnsguard-rollback --disarm       # 确认保留

# 服务
/etc/init.d/dnsguard reload
/etc/init.d/dnsguard stop                 # 临时摘链（配置不动，fw4 reload 后恢复）
```

## 部署 / 回滚

```sh
export PATH="/c/Users/27970/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:$PATH"
sh deploy.sh --check     # 静态检查（shell / JSON / Lua 控制器 / 模板内嵌 Lua）
sh deploy.sh --install   # 打包上传安装（会先备份旧文件）
```

**安装阶段不碰防火墙**——规则文件只会在界面点「保存并应用」时生成。

回滚（install.sh 也会打印）：

```sh
cp -r /mnt/data/backup-dnsguard/<安装时间戳>/* / \
  && rm -f /usr/lib/lua/luci/controller/dnsguard.lua \
  && rm -rf /usr/lib/lua/luci/view/dnsguard /usr/share/rpcd/acl.d/luci-app-dnsguard.json /etc/init.d/dnsguard \
  && rm -f /tmp/luci-indexcache*
# 再删掉重定向链：
nft delete chain inet fw4 dns_guard_redirect 2>/dev/null; fw4 reload
```

## 开发时的三个坑（都真踩过）

1. **`while read` 丢末行**：`printf '%s' "$list" | ... | while read e` 会把**最后一个元素**丢掉，
   必须 `printf '%s\n'`。症状是 `224.0.0.0/4`、`140.207.198.6` 之类的**最后一个元素**神秘消失。
2. **Lua 白名单漏 `/`**：控制器里清洗地址用的 `gsub("[^%w%.%:%-%s%,]", "")` 会把 CIDR 洗成
   `192.168.1.024`（打桩测试抓到的）。白名单必须含 `/`。
3. **shell 里给变量赋值 PATH 在部分环境下有坑**：`PATH=/x:$PATH cmd` 在某些封装 shell 里会被改写成
   带 `$( )` 的形式而语法报错；测试时改用 `/usr/bin/env PATH=... cmd` 更稳。
