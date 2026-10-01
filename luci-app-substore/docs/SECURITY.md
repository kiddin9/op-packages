# Security — luci-app-substore

## SSRF 防护
- `http.lua` 下载前解析主机名，拒绝 localhost/内网/链路本地/保留地址
- DNS 解析后二次校验，处理重定向
- 仅允许 http/https 协议；端口限定 1–65535
- **解析失败即拒绝（fail-closed）**：主机名解析不出 IP 时不放行。
  检查的强度不能低于被检查者 —— `127.0.0.1.nip.io` 这类「公网可解析到内网」的域名，
  若在本机解析失败的那一刻被放行，curl 自己仍会把它解析到 127.0.0.1 并连上去。
  代价为零：本包依赖 `luci-lua-runtime`，后者硬依赖 `luci-lib-nixio`，
  所以解析失败只意味着「真的解析不了」，此时下载本来也会失败

## 资源限制
- 订阅响应体最大 10MB，可配置
- 连接/总超时 20s
- 并发限制由系统调度
- 下载临时文件（`.tmp` / `.tmp.hdr` / `.tmp.err`）在**每一条**退出路径上清理。
  OpenWrt 的 `/tmp` 是 tmpfs，占的是内存；失败路径不清理会让 cron 定时重试
  一轮轮往内存里堆文件，其中 `.tmp` 可能是最大到 `max-size` 的部分响应体

## 输入校验
- 订阅名/文件名白名单校验，禁止 `..`、`/`
- 解析时限制结构/大小/嵌套深度，防 YAML/JSON 资源耗尽
- URL 参数解码后二次校验
- 探测目标主机名拒绝以 `-` 开头：`probe.lua` 的命令形如 `ping -c 1 -W 2 <host>`，
  而 `--help` / `-c` 会被 busybox 的 getopt 当成**选项**。`util.shq` 的单引号由
  shell 剥掉，getopt 看到的仍是 `-x`，引号挡不住这一层，必须在取值时就拒绝

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