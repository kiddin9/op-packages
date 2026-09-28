# Tailscale 与 mwan3 策略路由兼容设计

**状态：已实现，待杭州办公室 OpenWrt 部署验证**

## 背景

Tailscale 在 OpenWrt 上维护 IPv4 路由表 `52`，并通常安装优先级为
`5270` 的 `lookup 52` 规则。启用了 mwan3 的路由器会在更低的优先级安装
带 fwmark 的策略规则，例如 `2001`、`2002`。LAN 转发流量先被 mwan3 标记后，
会命中这些规则并被发往 WAN，无法到达后续的 Tailscale 路由表。

本功能为存在该冲突的路由器提供一个显式、可选的修复：在 mwan3 的 fwmark
规则之前安装 `priority 1000 lookup 52`。当目标不在表 `52` 中时，该 lookup
不产生路由结果，内核会继续评估后续 mwan3 规则；它不接管普通公网流量。

## 目标

1. 检测 mwan3 的早期 fwmark 规则与 Tailscale 表 `52` 的优先级冲突。
2. 通过独立 UCI 开关维护应用拥有的 `network` 规则：
   `network.ts_mwan3_table52`、IPv4、优先级 `1000`、`lookup 52`。
3. 在接口 `ifup` / `ifupdate` 后只做幂等的运行态自愈，不重启任何服务。
4. 在 LuCI 中呈现启用状态、阻断原因和真实 LAN 客户端的验证要求。
5. 当表 `52` 存在默认路由（例如使用 Tailscale exit node）时拒绝启用，
   防止把普通公网流量绕过 mwan3。

## 非目标与边界

- 不修改 `/etc/config/firewall`，不重载 firewall4，不操作 nftables。
- 不管理、重启或重载 mwan3。
- 不管理 OpenClash 服务或其配置；OpenClash bypass 仍是独立流程。
- 不直接修改或替换 tailscaled 所有的 `5270 lookup 52` 运行态规则。
  该规则由 tailscaled 管理，重启或路由同步时会重新生成。
- 不将本功能用于发布 Tailscale 子网路由，也不替代 Headscale 的路由审批。

## 三条独立流程

| 流程 | 所有者 | 可修改的资源 |
| --- | --- | --- |
| WAN 直连 | Tailscale LuCI WAN 设置 | firewall UCI / firewall4 |
| OpenClash 绕过 | OpenClash 自定义防火墙 hook | package-owned helper 的 nft 规则 |
| mwan3 优先级兼容 | `tailscale_policy_routing` helper | `network` UCI 与运行态 `ip rule` |

三条流程不能互相 reload 或管理对方服务。

## 配置与所有权

- 独立配置包：`/etc/config/tailscale_policy_routing`。
- 开关：`tailscale_policy_routing.settings.enabled`，默认关闭。
- 应用管理的网络规则固定命名为 `network.ts_mwan3_table52`，并使用固定的
  名称、family、priority 与 lookup 值证明所有权。
- 如果同名 UCI section 或运行态优先级 `1000` 被其他配置占用，helper 失败
  并记录日志，不接管、不删除第三方规则；冲突后仍保留应用的 UCI 所有权声明，
  以便第三方规则撤销后安全恢复。
- 比较 mwan3 的 `mmx_mask` 与运行态 `ip rule` 时统一使用小写十六进制，避免 UCI
  与 `iproute2` 输出的大小写差异绕过优先级保护。
- 关闭开关时，helper 仅删除经所有权确认的 UCI rule 及其对应的精确运行态
  `1000: from all lookup 52` 规则。带 `from`、`to` 或 `fwmark` 条件的表 52
  规则均视为手工规则并保持不变。

## 生命周期

1. 保存 LuCI 配置后，策略路由 init service 调用 helper 的 `sync`。
2. Tailscale 正常启动或重新应用配置完成后，调用 helper 的 `sync`，以便在
   exit-node 状态变化时重新评估默认路由保护。
3. 接口 `ifup` / `ifupdate` 调用 helper 的 `ensure`；它不写 UCI，
   只在配置已被确认拥有且规则缺失时恢复运行态规则。若表 `52` 此时有默认路由，
   它只删除应用拥有的运行态优先级规则，保留 UCI 声明以便退出节点撤销后恢复。
4. 若已有 mwan3 fwmark 规则的优先级数值小于 `1000`，helper 不安装规则；若原有
   运行态规则已存在则只移除运行态规则、保留 UCI 声明，并在 LuCI 显示阻断原因。
5. 策略服务启动后以 15 秒间隔静默执行 `ensure`，覆盖 `tailscaled` respawn 与通过
   CLI 改变退出节点/路由的场景；它不写 UCI、不重启任何网络或防火墙服务。
6. 软件包卸载时先以严格模式调用 `cleanup`；若 UCI 所有权已丢失但仍有精确的
   `1000: from all lookup 52` 运行态规则，清理失败并中止卸载，防止卸载后遗留未知
   路由行为。普通服务 stop 不删除持久化配置。

## 运行状态

- `active`：持久化和运行态规则均由本应用管理。
- `waiting`：开关已启用，等待后续接口/Tailscale 生命周期同步。
- `blocked_default_route`：表 `52` 有默认路由，禁止提升优先级。
- `blocked_mwan3_priority`：已有 mwan3 fwmark 策略规则优先级数值小于 `1000`，本
  功能无法保证 table `52` 优先。
- `blocked_priority_conflict`：优先级 `1000` 已被其他规则占用。
- `blocked_ownership`：同名 UCI section 或同优先级运行态规则不属于本应用。
- `disabled`：功能关闭，且不存在本应用残留。

## 验证

不能只使用 OpenWrt 本机的无 fwmark `ip route get`。验收须从真实 LAN 客户端
发起，或使用与 mwan3 相同 fwmark 的路由模拟，验证 Tailnet 地址和远端子网
地址命中表 `52`，普通公网目标仍由 mwan3 处理。
