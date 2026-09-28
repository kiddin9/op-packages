# OpenClash 绕过开关中文说明设计

## 背景与根因

办公室 OpenWrt 热部署了包含 OpenClash 绕过页面的新版 JavaScript，但仍安装旧版 `luci-i18n-tailscale-zh-cn`。设备上的 `tailscale.zh-cn.lmo` 不包含新增 msgid，因此 LuCI 将开关、说明和状态回退为英文。

这不是浏览器缓存问题。修复必须同时更新源码中的 msgid、简体/繁体翻译和设备上的编译语言目录，不能只改 JavaScript。

## 用户意图

页面必须直接解释关闭开关的网络影响，而不只描述内部实现。用户应能在保存前明确知道：关闭会让 Tailscale 流量重新进入 OpenClash，并使节点在线、点对点直连、Tailnet DNS 和跨子网访问失去绕过保护。

## 页面设计

`OpenClash` 作为产品名称保留英文。

开关名称：

> 保护 Tailscale 流量（绕过 OpenClash）

简体中文说明：

> 开启后，Tailscale 控制连接、直连通信、Tailnet DNS 和跨子网流量不会被 OpenClash 接管。关闭后，这些流量将重新经过 OpenClash，节点在线、点对点直连、跨子网访问和 Tailnet DNS 解析不再受本功能保护；如果 OpenClash 规则接管或重定向这些流量，可能导致节点掉线、直连退化为 DERP、跨子网访问或 Tailnet DNS 中断。使用 OpenClash 时必须保持开启。

繁体中文说明使用相同语义。

状态文案：

- `active`：已开启，4 条绕过规则已生效
- `waiting`：已开启，正在等待 OpenClash 创建 nftables 链
- `disabled`：已关闭，Tailscale 流量将由 OpenClash 处理
- `absent`：未安装 OpenClash，无需绕过
- `unsupported`：当前系统不支持，仅支持 firewall4/nftables
- `error`：配置错误

## 行为边界

页面文案只解释既有行为，不改变 helper 的所有权和生命周期：

- 开启时继续维护 4 条包拥有的 nftables `return` 规则和一个托管 hook。
- 关闭时继续删除这 4 条规则和托管 hook。
- 不停止 Tailscale。
- 不修改 WAN UDP 端口放行。
- 不修改子网 SNAT。
- 不 reload firewall4，不启停或重启 OpenClash。

## 测试设计

先扩展现有测试并确认 RED：

- `tests/package_release_test.sh` 精确验证简体和繁体中文翻译。
- `tests/setting_openclash_bypass_test.js` 验证页面使用新的 msgid 和各状态文案。
- 测试拒绝旧的 `Enable OpenClash Bypass` 及只描述实现、不描述关闭影响的说明。

实现后运行完整 shell、JavaScript、语法、JSON 和翻译检查。GitHub Actions 继续负责 Linux/OpenWrt SDK 的 `ipk`、`apk` 构建。

## 办公室验证与回滚

源码与 CI 通过后，只写办公室 OpenWrt，不修改杭州机房 OpenWrt。

部署前备份当前 `setting.js`、`tailscale.zh-cn.lmo` 和相关 LuCI 缓存状态。部署匹配版本的 JavaScript 与编译语言目录后清理 LuCI 缓存，并验证：

- 开关、说明和状态均显示中文。
- OpenClash 绕过状态仍为 active，规则数仍为 4。
- Tailscale、OpenClash、Tailnet DNS、公共 DNS 和跨子网访问正常。
- 日志没有新增相关错误。

任何页面加载错误、语言目录错误或网络回归都会触发回滚：恢复备份的 JavaScript 和 LMO，重新清理 LuCI 缓存并执行同等级别验证。
