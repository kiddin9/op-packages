# Issue Triage 2026-07-04

本文件记录 2026-07-04 维护时对 open issue / PR 的处理边界，便于后续关闭 issue 时引用。

## 已在 2.0.7 覆盖

- OpenClaw 默认版本升级：`2026.6.11`，覆盖和当前稳定版、Node 最低版本相关的问题反馈。
- 微信插件安装：缺少 Python 时自动尝试安装 `python3-light`，失败后给出明确手动命令。
- 微信插件登录：收窄权限修复范围，增加 `openclaw` 用户写权限预检。
- 微信插件卸载：清理 legacy extension、npm projects 中的微信插件包、微信账号状态目录和配置中的 `openclaw-weixin/weixin` 残留。
- 自定义安装路径：备份 API 改用统一路径 helper，继续兼容 `/mnt/data` 和误填 `/mnt/data/openclaw`。

## 已在 2.0.8 覆盖

- ARM64 musl Node.js 默认版本和自托管资产对齐到 `22.23.0`。
- 长期 `node-bins` release 已补齐 `node-v22.23.0-linux-arm64-musl.tar.xz`，避免在线安装继续请求不存在的 `22.22.2` 资产。
- 手动 ARM64 musl Node.js 构建 workflow 同步到 `22.23.0`。

## 已由当前 main 既有实现覆盖

- 可配置安装根目录和路径规范化：PR #85 的核心路径 helper、`/mnt/data/openclaw` 误填兼容、危险路径拒绝已经在 main 存在。
- HOME 不全局污染：`profile.d/openclaw.sh` 仅在 wrapper 内注入 `HOME`。
- 控制台打开方式：Web 控制台使用新窗口 HTTP Gateway URL，避免 LuCI HTTPS / iframe / 旧 token 混用。
- 微信渠道名迁移：init 脚本会把旧 `weixin` 迁移到 `openclaw-weixin`，并清理 duplicate entries。

## 暂不关闭

以下类型 issue 不应仅凭 2.0.7 关闭，需要单独复现或确认：

- 模型/provider 具体行为差异或上游 OpenClaw 功能请求。
- 缺少完整日志、无法确认由本次 Node / 微信 / 权限修复覆盖的问题。
- 需要用户确认网络、DNS、代理、设备资源或第三方 API 状态的问题。
