# Security — luci-app-substore

## SSRF 防护
- `http.lua` 下载前解析主机名，拒绝 localhost/内网/链路本地/保留地址
- DNS 解析后二次校验，处理重定向
- 仅允许 http/https 协议

## 资源限制
- 订阅响应体最大 10MB，可配置
- 连接/总超时 20s
- 并发限制由系统调度

## 输入校验
- 订阅名/文件名白名单校验，禁止 `..`、`/`
- 解析时限制结构/大小/嵌套深度，防 YAML/JSON 资源耗尽
- URL 参数解码后二次校验

## 凭据保护
- 订阅 URL 中的 token 不写入普通日志
- 输出/下载接口使用**每订阅随机 16 位十六进制 token** 鉴权（`core.ensure_token`），不可猜测；`/substore/download` 无登录态
- 日志使用 `logger -t luci-app-substore`，不记录敏感信息

## 安全测试
- 已验证 SSRF 私网拒绝
- Base64/JSON 解析异常处理
- 超大响应体截断测试

参见 docs/ARCHITECTURE.md 第 5 节安全设计。

Key requirements (from CLAUDE.md):

- Prevent SSRF (reject localhost / private / link-local / reserved addresses)
- DNS rebinding protection
- Limit subscription response body size and set request timeouts
- Prevent path traversal and command injection
- Never log subscription credentials / tokens
- Output interface requires access control or a random token
- Validate imported data; prevent malicious YAML/JSON resource exhaustion