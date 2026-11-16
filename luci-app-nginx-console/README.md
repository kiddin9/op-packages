# luci-app-nginx-console

ImmortalWrt / OpenWrt 上 nginx 的 LuCI 控制台，标签页布局。

配置侧按"这段配置是干什么的"分开：服务器段、反向代理、转发、重定向。工具侧是五个只读或半只读的视图：日志、证书、备份、访问控制、体检。

## 功能

### 服务器（`/etc/config/nginx` 的 `config server` 段）

nginx-util 把这些段渲染进 `/etc/nginx/uci.conf`，所以 UCI 的 option 名就是 nginx 指令名。

- 只读详情 + 编辑：`listen`、`server_name`、`include`、`ssl_certificate`、`ssl_certificate_key`、`access_log`、`error_log`
- 证书可在 `/etc/ssl/acme`、`/etc/nginx/certs`、`/etc/luci-uploads` 里挑，也可直接上传 PEM 文本
- 安全与限流：四个响应头（HSTS / X-Frame-Options / X-Content-Type-Options / Referrer-Policy）各是一个**开关**，`server_tokens off` 也是一个开关，请求限速是**分段按钮**（不限速 / 5 / 20 / 100 请求每秒），并发连接数是**滑块**
- 新建 / 删除 server 段（`_lan` 有后端硬保护，删不掉）
- 两个内置段显示为「HTTPS 监听端口」「HTTP 监听端口」，真名仍在详情页右上和悬停提示里

### 反向代理 / 转发 / 重定向（`/etc/nginx/conf.d/*.locations`）

片段按**内容里的指令**分类，不看文件名：`proxy_pass` → 反向代理，`uwsgi_pass` 等 → 转发，`return 30x` → 重定向，其余进「其他」（该标签只在真有未归类片段时出现）。

- **反向代理**：填路径 + 后端地址即生成。WebSocket 是个**开关**，打开时自动补 `Upgrade` / `Connection` / `http_version 1.1` / `proxy_buffering off`；connect/send/read 三个超时各是一个**滑块**（5s / 15s / 30s / 60s / 2min / 5min，也能直接填自定义值），另有"额外指令"
- **转发**：路径 + 协议（uwsgi / fastcgi / scgi / grpc）+ 后端，自动带对应的 `include xxx_params;`（grpc 不带）
- **重定向**：
  - 全局的 HTTP → HTTPS 跳转用一个**开关**驱动（打开写 `if ($scheme = http) { return 301 https://$host$request_uri; }`，关闭则删掉该文件）
  - 路径级重定向用表单：路径 + 状态码（301/302/307/308）+ 目标地址
- **表单不会吃掉文件内容**：表单只建模它认识的指令，其余的（`proxy_set_header X-Real-IP …`、`client_max_body_size …`、注释……）收进"额外指令"，保存时原样写回。块外只有注释时才用表单，块外还有别的指令（多个 location、server 级指令）就自动退回文本编辑器

滑块与开关都遵守同一条规矩：**磁盘上的值优先**。滑块停在"不设置"时，旁边的输入框里是原值；原值不在档位里就照原样显示并注明"不在档位里"，用户动了滑块或输入框才写新值。

### 日志

`logread` 里的 nginx 日志（OpenWrt 上 nginx 走 syslog，没有日志文件），错误/访问切换。全局 `access_log off` 时访问日志为空，页面上说明了在服务器段填 `logd openwrt` 才会记录。

### 证书

扫描 `/etc/ssl/acme`、`/etc/nginx/certs`、`/etc/luci-uploads`，用 openssl 解析到期时间、剩余天数、SAN。

- 按证书身份合并：acme 把同一张证书写成 `.crt` / `.combined.crt` / `.fullchain.crt` 三份，只显示一条、下面列出全部路径
- 中间证书（`chain.crt`，CA:TRUE）不显示
- 剩余 <30 天转黄，<7 天转红
- 剩余天数用 openssl `-checkend` 二分求得（OpenWrt 没有能解析 `Sep 12 17:54:00 2027 GMT` 的 date）

上传的证书由后端落盘：文件名要过白名单（只允许字母数字与 `. - _`，后缀限 `crt/cer/pem/key/csr`），**私钥落盘是 0600**，证书是 0644。前端不再直接往 `/etc/luci-uploads` 写文件。

### 备份

列出 `/root/backup/nginx-console/`（UCI）和 `/root/backup/nginx-console-fragments/`（片段），各保留最近 10 份，可一键恢复。

时间从**文件名**里的时间戳读——备份用 `cp -p`，文件 mtime 是源配置被编辑的时间，不是备份时间。

恢复一份语法错误的备份时，会**先回滚再报错**：旧文件被放回去，nginx 不会被一份坏配置拖下水。

### 访问控制

`/etc/nginx/htpasswd` 的用户增删改。哈希用 `openssl passwd -apr1 -stdin` 生成，**密码经暂存文件传递而非 argv**，不会出现在 `ps` 里；暂存文件是 0600，`htpasswd` 本身也是 0600。原文件改动前留一份 `.bak`。

### 体检

查 `nginx -t` 查不出来的问题：`server_name` 重复、反代目标端口没有监听、证书即将到期、空的片段文件、`include` 指向不存在的东西。

## 权限：两个入口，一份 ACL

后端拆成两个物理文件，rpcd 的授权按**路径**分开：

| 入口 | 提供的命令 | ACL |
| --- | --- | --- |
| `/usr/libexec/nginx-console` | `status` `test` `logs` `certs` `backups list` `auth list` `audit` | `read` |
| `/usr/libexec/nginx-console-write` | `server-save` `server-add` `server-delete` `frag-save` `frag-delete` `backup-restore` `upload` `auth set/delete` | `write` |

ACL 是一个组 `luci-app-nginx-console`，组里分 `read` 与 `write` 两级。rpcd 检查的是**路径**上的 `exec` 权限：只读账号能跑只读入口，跑写入口直接 Permission denied；`ubus file exec` 这种不限路径的通道没有授权，所以只读账号也拿不到 root shell。

给一个账号只读权限：

```sh
uci set rpcd.ncsreader=login
uci set rpcd.ncsreader.username='ncsreader'
uci set rpcd.ncsreader.password='$p$……'
uci add_list rpcd.ncsreader.read='luci-app-nginx-console'
uci commit rpcd && /etc/init.d/rpcd restart
```

页面上会自动认出来：只读账号看不到"编辑 / 删除 / 新建"，顶部有一条只读提示。

## 写操作的统一约定

前端只读 + 写暂存文件（每次调用一个 `/tmp/nginx-console.pending.<随机>`，模式 0600，命令结束即删），落盘由 `/usr/libexec/nginx-console-write` 完成。后端把命令最后那个参数当作暂存文件路径，并只接受匹配 `nginx-console.pending.<id>` 的路径——两个标签页同时保存时不会互相覆盖，路径也不能指向暂存区以外。每个写操作固定走同一条路：

```
备份 → 写入 → （server 段还要 commit + 重新渲染 uci.conf）→ nginx -t
   ├─ 失败 → 还原 → 返回带行号的 nginx 报错
   └─ 通过 → reload，并等到新 worker 真正接管才返回
```

几条刻意的设计：

- **选项值不经 shell**：读当前值时用 `ubus call uci get` + `jsonfilter` 取结构化列表，不再 `eval` `uci get` 的文本输出——后者会把配置里的 `$(...)` 当命令执行
- **字段白名单**：`server-save` 只碰 `listen`、`server_name`、`include`、两个证书字段、两个日志字段、`add_header`、`server_tokens`、`limit_req`、`limit_conn`，其余（`uci_manage_ssl`、会话缓存等）原样不动
- **只碰暂存到的字段**：暂存文件里没带的字段一律不碰（空值和"没这个字段"是两回事）；要清空一个列表字段，表单会明确写一行空值过去
- **值没变的字段连位置都不会动**
- **保存前校验**：`_lan` 必须存在且有 443 监听；任何监听 443/ssl 的段必须有完整证书与私钥
- **uci 返回码检查**：写入循环用 here-doc 而非管道，任一 `uci set` 失败就整体中止（管道会让循环跑在子 shell 里，错误传不出来）

## 后端命令

```
# 只读入口 /usr/libexec/nginx-console
status                          运行状态、版本、段数、片段数、worker 数
test                            nginx -t 的原始输出
logs <error|access> [n]         读 logread
certs                           证书清单
backups list                    备份清单
auth list                       htpasswd 用户清单
audit                           自检

# 写入口 /usr/libexec/nginx-console-write
server-save <段>                从 pending 读 "字段<TAB>值" 行
server-add <段>                 同上，新建
server-delete <段>              删除
frag-save <文件>                整份替换
frag-delete <文件>              删除
backup-restore <path>           回滚
upload <文件名>                 把 pending 里的内容装进 /etc/luci-uploads
auth set|delete [user]          htpasswd 管理（密码从 pending 读）
```

每个命令都只输出一个 JSON 对象并 `exit 0`，调用方不用解释退出码。`upload` 的文件名要过白名单，私钥落盘是 0600。

`include` 与 `access_log` / `error_log` 的值在后端还有一层校验（`nginx -t` 本身不拦这两类路径）：`include` 只允许配置目录内的相对路径，日志只允许 `logd` / `syslog` / `off` / `/var/log/nginx/` 下的文件。不合规的提交返回 `invalid_value`。

## 目录

```
Makefile                                                    in-tree / feed 构建用
.github/build-pkg.sh                                        CI 打包（apk mkpkg）
.github/workflows/build.yml                                 CI：编译 apk-tools → 打包 → 发 Release
scripts/build-local.sh                                      在路由器上直接打包（不用 SDK / CI）
htdocs/…/view/nginx-console/main.js                         页面
root/usr/libexec/nginx-console                              只读后端
root/usr/libexec/nginx-console-write                        写后端
root/usr/libexec/nginx-console-lib.sh                       两个入口共用的实现
root/usr/share/luci/menu.d/…                                菜单：服务 → Nginx 控制台
root/usr/share/rpcd/acl.d/…                                 ACL（read / write 分级）
root/etc/nginx/conf.d/nginx-console-limits.conf             限流 zone 定义（conffile）
```

## 打包与升级

```sh
# 改完代码，把 Makefile 里的 PKG_VERSION 或 PKG_RELEASE 加一
bash scripts/build-local.sh

scp dist/luci-app-nginx-console-<版本>.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'apk add --allow-untrusted /tmp/luci-app-nginx-console-<版本>.apk'
```

也可以从 Releases 直接取包（包未签名，需要 `--allow-untrusted`）：

```sh
apk add --allow-untrusted https://github.com/szwjp/luci-app-nginx-console/releases/download/v<版本>/luci-app-nginx-console-<版本>.apk
```

第一次运行 `build-local.sh` 会从 Alpine 镜像取一个静态 `apk.static` 放在路由器 `/tmp` 并复用——OpenWrt 自带的 apk 没有 `mkpkg` 子命令，打不了包。包未签名，所以要 `--allow-untrusted`。

限流速率所在的 `nginx-console-limits.conf` 是 conffile：升级时保留本地那份，新版放旁边。

CI 那条路也可用：`.github/workflows/build.yml` 是手动触发（workflow_dispatch），从 Makefile 读版本，构建 apk 并发布到对应的 Release tag。

卸载：`apk del luci-app-nginx-console`（`/etc/config/nginx` 和 `conf.d` 下的片段不属于本包，不会被删）。

## 依赖

`luci-base`、`rpcd`、`rpcd-mod-file`，以及虚拟包 `nginx`——`nginx-full` / `nginx-ssl` 等任何变体都能满足。

## 前端的执行通道

`callHelper` 用 rpcd 的 `file.exec`（`fs.exec`），参数按 argv 传，不拼 shell 字符串。命令属于哪一类决定用哪个入口：只读命令走 `nginx-console`，写命令走 `nginx-console-write`。

不用 cgi-io：那台路由器上会话拿不到 `cgi-io: exec`，而且 cgi-io 的授权粒度比 path 级 `file.exec` 粗。

## 边界

- 只读 `/etc/config/nginx` 与 `/etc/nginx/conf.d`，**从不**直接改 `/etc/nginx/uci.conf`（它是 nginx-util 的生成物），也不碰证书文件本身
- 不认识 `config server` 以外的 UCI 字段，也不会主动删除它们
- 限流的 rate 写死在 `nginx-console-limits.conf` 里，控制台只引用 zone 名
- 没有做也不会做：`stream`（TCP/UDP 转发）——这台路由器上纯端口转发已有 DNAT 和 Lucky 两套，stream 只会更慢并丢掉源 IP
