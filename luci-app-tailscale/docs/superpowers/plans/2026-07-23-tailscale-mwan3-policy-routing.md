# Tailscale 与 mwan3 策略路由兼容实施计划

1. 已为 helper 和 hotplug 增加独立的 shell 行为测试，覆盖创建、幂等、
   自愈、关闭、冲突、默认路由保护和所有权保护。
2. 已实现独立配置、init service、hotplug 与 `tailscale_policy_routing` helper；
   禁止 helper 操作 firewall、OpenClash 或 mwan3 服务。
3. 已接入软件包升级快照/恢复和 Tailscale 生命周期同步，确保应用升级、重启和
   接口事件后配置不丢失。
4. 已通过 rpcd 暴露只读状态，在 LuCI 高级设置中增加可选开关、中文状态和
   从真实 LAN 客户端验证的说明；冲突场景保留所有权、route-only `ifupdate` 会
   重新评估 exit node 与 mwan3 优先级保护。
5. 已补充简体/繁体中文翻译、包结构检查、rpcd 与 LuCI 视图测试。
6. 已运行可由当前本地终端完整执行的 shell/JavaScript 测试和 `git diff --check`。
   OpenClash 信号注入测试会终止当前终端代理，保留给 Linux CI 执行。仅在用户另行
   明确确认后，才部署到杭州办公室 OpenWrt 验证；不写入 hzsls-openwrt。
7. 已在独立评审后补强：统一规范化 mwan3 标记掩码的十六进制大小写；软件包卸载
   不会遗留无 UCI 所有权的精确 `priority 1000 lookup 52` 规则；策略服务以 15 秒
   间隔静默校验已拥有的运行态规则，覆盖 tailscaled 单独重启和路由状态变更。
