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
- 批量节点探测并发上限 `probe.MAX_PARALLEL = 16`。节点数由订阅内容决定（可上千），
  每个探测占 1 个进程 + 1 个管道 fd；不限并发会打满路由器的 fd / 进程额度，
  之后 `io.popen` **静默失败** —— 症状是一大片节点探测不出来，而不是报错

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
- 落盘权限：`/etc/substore` 目录 `0700`，`subscriptions.json` 与 `nodes/*.json` `0600`。
  `io.open` 按 umask 创建（通常 0644），同机任何用户都能读到订阅 URL、下载 token
  与节点凭据，因此 `util.atomic_write` 在 `os.rename` **之后**显式 chmod ——
  先 chmod 再 rename 的话，临时文件名可猜，中间窗口里仍能读到。
  目录侧由 `core.ensure_dirs` 建目录时带 `-m 700`，并对旧版本升级上来、
  已存在的目录补一次 `chmod 700`（每进程一次，避免 `load()` 每次都 fork）
- 注入到页面 `<script>` 的 JSON 转义**全部** `<`（`<`）：只转 `</` 挡得住
  `</script>` 提前闭合，却挡不住 `<!--` —— 后者让 HTML 词法阶段进入
  script data escaped 状态，其后的 `</script>` 不再结束脚本块，整页被吞进脚本

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