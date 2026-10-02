# Security — luci-app-substore

## SSRF 防护
- `http.lua` 下载前解析主机名，拒绝 localhost/内网/链路本地/保留地址
- DNS 解析后二次校验，处理重定向
- 仅允许 http/https 协议；端口限定 1–65535
- **解析失败即拒绝（fail-closed）**：**有解析手段**却解析不出 IP 时不放行。
  检查的强度不能低于被检查者 —— `127.0.0.1.nip.io` 这类「公网可解析到内网」的域名，
  若在本机解析失败的那一刻被放行，curl 自己仍会把它解析到 127.0.0.1 并连上去。
- **解析手段多级回退**：`nixio.getaddrinfo` → busybox `nslookup`。
  `[2.6.8-r1]` 曾假设「本包依赖 luci-lua-runtime，后者硬依赖 luci-lib-nixio，
  所以解析失败只意味着真的解析不了」——**该假设在部分设备上不成立**，
  导致所有域名订阅报「无法解析目标主机名」（`[2.6.12-r1]` 修复）。
  现在把「本机没有解析手段」与「这个域名解析不出来」严格区分：
  前者放行并标记 `unverified`，后者仍 fail-closed。
- **连接时对端校验**：`fetch_curl` 用 `-w` 取 `%{remote_ip}`，在**连接建立后**
  复核真正连上的 IP；重定向的每一跳（含第一跳）都复核。
  这既兜住上面 `unverified` 的放行路径，也消除了「预检解析」与
  「下载时解析」之间的 TOCTOU 窗口（DNS rebinding）。
  走代理时跳过 —— `%{remote_ip}` 那时是代理地址。
  `unverified` 且拿不到对端 IP 时拒绝：「无法校验」不等于「放行」。
- **wget 后端在 `unverified` 时直接拒绝**（`[2.6.16-r1]`）。此前该后端只有预检：
  busybox wget 拿不到对端 IP，`-S` 日志里的重定向链也只能事后看 —— 于是
  「本机无解析手段」的设备上，预检放行之后**不存在任何一处校验**，等于完全没有
  SSRF 防护，且这条路径是静默的。现按与 `verify_peer_ip` 相同的原则收敛：
  校验不了就拒绝，错误信息提示安装 curl。字面 IP 目标不受影响
  （`check_public` 对 IP 提前返回，不产生 `unverified`）。
- **重定向链逐跳复检**：`validate_redirect_chain` 从 wget `-S` 日志按顺序取出每一跳
  的 `Location`，逐跳 `check_public`，任一跳不安全即整体拒绝并丢弃响应体。
  限制：这是**事后**校验（busybox wget 无 `--max-redirect`），请求已经发出；
  curl 路径用 `--max-redirs 0` 自行逐跳跟随，每跳都在**发出前**校验。

## 访问控制
- **ACL 组**（`[2.6.16-r1]`）：`root/usr/share/rpcd/acl.d/luci-app-substore.json`
  定义 `luci-app-substore` 组（读写 `uci: substore`），`menu.d` 两个条目均声明
  `depends.acl` 引用它 → 未获授权的 LuCI 用户看不到本应用入口。
  在此之前本应用**没有任何 ACL**，任意已登录 LuCI 用户都能读写全部订阅（含凭据 URL）。
- **授权方式**：把用户加入该 ACL 组，例如在 `/etc/config/rpcd` 中为该用户的
  `read` / `write` 列表加上 `luci-app-substore`（与其它 LuCI 应用一致）；
  仅 root 可见时无需任何配置。
- **改完必须刷新 LuCI 索引缓存**：菜单树与 ACL 都被缓存在 `/tmp/luci-indexcache*`
  （缓存文件名含 menu.d 文件列表的哈希）。新增/修改 menu.d 或 acl.d 后若不刷新，
  改动**不会生效**且不报错。包的 `postinst` 已自动执行
  `rm -f /tmp/luci-indexcache && /etc/init.d/luci reload`；
  手工拷贝文件时需自己执行这两条。
- **执行范围（已从上游源码核实）**：这是**入口级**门禁，不只是「菜单里看不见」。
  ucode dispatcher（23.05+，现代目标机实际运行的那套）的 `build_pagetree()` 把
  menu.d 与 Lua 控制器装进**同一棵树**，`dispatch()` 逐段 `ctx_append` 累积
  路径上每个节点的 `depends.acl`，随后 ACL 不足即 `http.status(403)` ——
  **直接访问 URL 会拿到 403**。又因 ACL 沿路径累积，挂在父节点
  `admin/services/substore` 上的 ACL 已覆盖其下**全部 18 个** `entry`
  （form / nodes / delete / save / update / probe …）。
  旧版 Lua dispatcher（≤ 22.03）行为不同：menu.d 的 `depends.acl` 只影响菜单渲染，
  入口级需另补 `entry.acl_depends` —— 但**本项目最低支持 23.05**，不在支持范围内，
  故无需处理（见 LEGACY_ISSUES 1.2）。
  **已在设备上实测通过**（2026-10-02，按 TESTING.md 第 9 项）：未授权用户看不到
  入口、加入组后入口出现、**直接访问 URL 返回 403 Forbidden**。
- **表单 token**：写操作要求 `token` 存在、非空，并在可取到时与
  `luci.dispatcher.context.authtoken` 比对（该值正是模板中 `token` 的来源），
  校验失败**回显原因**。所有 `entry` 均未声明 `post`，因此框架的
  `test_post_security` **不会**执行 —— 上述检查是本应用自己的那一层。

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
- **订阅客户端类型（User-Agent）**：`http.validate_user_agent` 拒绝控制字符与超过
  256 字符的值。UA 来自表单，最终以 `-A <ua>` / `-U <ua>` 进入 shell 命令 ——
  `util.shq` 的单引号挡得住注入，但挡不住 UA 里的**换行**：curl 会把它当成额外的
  请求头拼进去（header injection），日志里也会被换行截断、伪造出额外行。
  与代理同理，非法 UA **明确失败而非静默忽略**（§12）：静默忽略会让用户以为 UA
  已生效，实际拿到的仍是占位节点
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

均为自包含 Lua 5.1 测试，`lua5.1 tests/<file>.lua` 即可运行（无需设备）：

- `tests/dns_fallback_test.lua` —— SSRF 私网拒绝、解析手段回退、
  「有解析手段却解析不出 → 拒绝」、「无解析手段 → 标记 `unverified`」、
  curl 的 `%{remote_ip}` 连接后复核，以及 **wget 后端在 `unverified` 时拒绝**
  （用例 H，含对照组 H2：有解析器时 wget 正常下载）
- `tests/parser_mixed_format_test.lua` —— 混合格式导入的拒绝与单一格式的不误判
- `tests/acl_menu_test.lua` —— ACL 组定义、菜单 `depends.acl` 引用同一组名、
  Makefile 确实安装这两个文件（接线上任何一环写错都只会**静默失效**）
- `tests/controller_robustness_test.lua` —— 表单 token 校验（合法 / 空 / 不匹配 /
  取不到 authtoken 的回退）与删除部分失败时的 cron 重写
- `tests/data_integrity_test.lua` —— 注入 `atomic_write` 写失败，断言失败被上报
  而非静默吞掉
- Base64/JSON 解析异常处理、超大响应体截断测试见 `tests/` 下同名用例

**仍未在设备上验证的部分**（如实记录）：LuCI 模板渲染、cron 落盘行为均需在目标
设备上复核 —— 见 [TESTING.md](TESTING.md)。（ACL 的实际拦截效果已于 2026-10-02
在设备上实测通过，见上文「访问控制」。）

参见 docs/ARCHITECTURE.md 第 5 节安全设计。

Key requirements (from CLAUDE.md):

- Prevent SSRF (reject localhost / private / link-local / reserved addresses)
- DNS rebinding protection
- Limit subscription response body size and set request timeouts
- Prevent path traversal and command injection
- Never log subscription credentials / tokens
- Output interface requires access control or a random token
- Validate imported data; prevent malicious YAML/JSON resource exhaustion