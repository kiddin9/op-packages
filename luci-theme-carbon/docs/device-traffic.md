# Device traffic accounting / 每设备流量统计

## 中文

默认使用 `nlbwmon`，按其采集周期读取数据（通常 30 秒）。即使采集服务不可用，Carbon 也不会探测 nftables。要使用 nftables，请先按下例配置并验证计数器，再到 **系统 → Carbon 主题** 选择 **nftables**，保存后重新打开概览。恢复默认时，在同一位置选择 **nlbwmon**。

选择 nftables 后，Carbon 每 5 秒读取 `inet carbon_acct` 表中的命名计数器，以相邻两次读数的字节差计算平均网速。所选来源不可用时，设备列表仍可使用，Carbon 只重试该来源。主题不会创建规则或修改防火墙及流量卸载设置。

### 配置示例

需要提供 JSON 输出的 `nft` 命令（OpenWrt 通常由 `nftables-json` 包提供）。以下是 **nft 配置文件内容**，不是 shell 脚本。管理员应将示例 IP 和 MAC 替换为实际设备的信息，并使用固定租约，避免 IP 转移后归属错误。每个设备需要两个命名计数器：

- `carbon_up_001122334455`：设备上传字节数，匹配源 IP。
- `carbon_down_001122334455`：设备下载字节数，匹配目的 IP。

MAC 使用 12 位小写十六进制，不带冒号。计数器本身位于 `inet carbon_acct` 表，规则通过 `counter name` 引用。如果已有规则使用匿名 `counter`，请先在现有表中声明上述两个命名计数器，再将上下行规则中的 `counter` 分别替换为对应的 `counter name …`。仅将表命名为 `carbon_acct` 无法识别匿名计数器。请勿叠加重复规则；迁移后的首次采样会重新建立基线。

```nft
table inet carbon_acct {
    counter carbon_up_001122334455 { }
    counter carbon_down_001122334455 { }

    chain forward {
        type filter hook forward priority 10; policy accept;
        ip saddr 192.168.1.100 counter name carbon_up_001122334455
        ip daddr 192.168.1.100 counter name carbon_down_001122334455
        ip6 saddr fd00::100 counter name carbon_up_001122334455
        ip6 daddr fd00::100 counter name carbon_down_001122334455
    }
}
```

将完整表定义保存在例如 `/etc/carbon-acct.nft` 中，先检查语法，再加载：

```bash
nft -c -f /etc/carbon-acct.nft
```

```bash
nft -f /etc/carbon-acct.nft
```

验证主题读取的数据：

```bash
nft -j list counters table inet carbon_acct
```

以上加载只作用于当前内核运行状态。持久化需通过所用固件支持的防火墙启动/重载机制加载该独立表，并处理重复加载和计数重置；完整 `table inet` 定义不能直接放进通常位于 `table inet fw4` 内部的 `/etc/nftables.d/*.nft` include。升级主题后，若固定查询被 ACL 拒绝，重启 rpcd 并重新登录 LuCI。

### 统计边界

- 该示例统计经过 forward 链的流量，包括跨网段内网流量。只统计互联网时，应按实际 WAN 入/出接口约束规则；PPPoE 应使用实际的三层接口名称。
- 每个地址只应命中一次同方向计数。设备有多个 IPv4/IPv6 地址时，可以用互不重叠的规则引用同一个计数器；IPv6 隐私地址变化时需更新规则。
- 软件/硬件 flow offload 可能绕过 forward 链。需要完整逐包统计时，应在防火墙设置中关闭相关卸载，并评估吞吐和 CPU 影响。单纯换用 nftables 不能保证所有环境都完整统计。
- 同网桥二层流量、路由器本身的 input/output 流量和经过其他网关的流量不在此示例范围内。
- 已选用 nftables 时，不再混合 nlbwmon 数据。没有完整上下行计数器的设备显示 `—`；计数器不能创建新的设备列表项。首次采样、来源切换、可检测的计数器重建或计数下降均重新建立基线。两次读取之间重置后又超过旧值的计数无法仅凭累计值识别；管理规则后刷新页面可强制重建基线。
- 选用 nftables 后，没有对应计数器的设备不会单独回退到 nlbwmon。主题无法补回任一采集来源未记录的流量。

## English

Carbon uses `nlbwmon` by default and follows its configured collection interval (normally 30 seconds). It never probes nftables in this mode, even if `nlbwmon` is unavailable. To use nftables, configure and verify the counters as described below, then select **nftables** under **System → Carbon Theme Settings**, save the setting and reopen the overview. Select **nlbwmon** in the same place to switch back.

In nftables mode, Carbon reads named counters in `inet carbon_acct` every five seconds and calculates average speeds from the difference between successive byte counts. If the selected source is unavailable, the device list stays usable and Carbon retries only that source. Carbon only reads counters and leaves firewall and offload settings to the administrator.

The nft configuration above uses two named counters per device: `carbon_up_<mac>` and `carbon_down_<mac>`, where `<mac>` is twelve lowercase hex digits without separators. Replace both the MAC and example IPv4/IPv6 addresses with the actual device values. Upload rules match source addresses; download rules match destination addresses. IPv4 and IPv6 rules may share the same named counter. Use stable leases and keep rules current as addresses change. To migrate anonymous counters, declare the named pair in the existing table and replace each inline `counter` with the matching `counter name …` reference. The table name alone cannot identify anonymous counters. The first reading after migration establishes a new baseline.

Use a JSON-capable `nft` binary (typically OpenWrt's `nftables-json` package). Save the full table definition, for example to `/etc/carbon-acct.nft`, check it with `nft -c -f`, then load it with `nft -f`, as shown above. Adapt an existing table instead of adding overlapping rules. The fixed read command is `nft -j list counters table inet carbon_acct`. After a theme upgrade, restart rpcd and log in again if its ACL rejects this query.

Loading a file affects the running kernel only. Persistence requires the firmware's firewall startup/reload mechanism, with duplicate loads and counter resets handled explicitly. Do not put this full table definition into `/etc/nftables.d/*.nft`, which is normally included inside `table inet fw4`.

The example counts forwarded traffic, including routed LAN-to-LAN traffic. Restrict rules to the actual WAN interfaces if internet-only totals are desired. Avoid overlapping matches for the same direction. Software/hardware flow offload can bypass the forward chain: disable relevant offloading when complete accounting is required, and evaluate CPU/throughput impact. Same-bridge traffic, router input/output and traffic through other gateways are outside this example's scope.

Once nftables is selected, nlbwmon totals are not mixed into it, even for devices without corresponding counters. Devices without both directions show `—`; counters never add discovered devices. Initial samples, source switches, detectable counter recreation and decreasing totals establish a fresh baseline. A reset followed by enough traffic to exceed the previous value between reads cannot be detected from totals alone; reload the page after managing rules to establish a fresh baseline.
