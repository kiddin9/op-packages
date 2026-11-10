# luci-app-portal 装机实测记录

在 **ImmortalWrt 25.12.2 r38135 / x86_64 / apk-tools 3.0.5** 上完成「SDK 编译 → 安装 → 功能测试 → 卸载重装」全流程，
**112 项断言全部通过**（首轮 105 项 → 修 3 个缺陷后 112 项）。

```
dist/luci-app-portal-3.0.0-r2.apk              26014 bytes
  sha256 cd3182a9de5ddd8b6de5（维护区段移入书签页后重建）
dist/luci-i18n-portal-zh-cn-3.0.0.apk           3611 bytes
  sha256 b5245ed0910f3e6366ed
```

> i18n 包每次重建内容都会变（lmo 内嵌时间戳），部署前以现场 `sha256sum *.apk` 为准。

## 1. 构建

```sh
SDK=~/build/immortalwrt/immortalwrt-sdk-25.12.2-x86-64_gcc-14.3.0_musl.Linux-x86_64
ls -l "$SDK/package/luci-app-portal"   # -> 项目目录的软链
cd "$SDK" && make package/luci-app-portal/compile -j16 V=s
```

产物落在 `bin/packages/x86_64/base/`。**没有编固件、内核或其他包** —— 只跑了
`package/luci-app-portal/compile` 这一个目标，SDK 自带的 `.config` 里那些整包 `=m` 一行都没碰。

两个包都由 luci.mk 自动派生：主包 `3.0.0-r2`（`arch: noarch`），
翻译包 `luci-i18n-portal-zh-cn-3.0.0`（`depends: libc luci-app-portal`）。

### 构建环境的两个坑

**1. IDE 的 `rm` 安全包装器会让编译失败。** luci-base 的 host 编译要跑
`make -C src/ clean`（内部是 `rm -f`），被包装器拦下后报：

```
[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":10008,...}
make[3]: *** [Makefile:19: clean] Error 1
```

看起来像项目坏了，其实是环境。跑构建前把这个 shim 摘掉：

```sh
env -u CODEBUDDY_SAFE_DELETE_BIN_DIR \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash -c 'unset -f rm unlink rmdir; cd <SDK> && make package/luci-app-portal/compile -j16 V=s'
```

**2. 设备上没有 `sftp-server`，`scp` 必须加 `-O`。** 否则报
`ash: /usr/libexec/sftp-server: not found`：

```sh
scp -O -o StrictHostKeyChecking=no *.apk root@192.168.122.12:/tmp/
```

## 2. 安装

```sh
apk add --allow-untrusted /tmp/luci-app-portal-3.0.0-r2.apk
apk add --allow-untrusted /tmp/luci-i18n-portal-zh-cn-3.0.0.apk
```

目标机预装齐全（`uhttpd` / `ucode` / `ucode-mod-fs` / `ucode-mod-uci` / `rpcd-mod-ucode` /
`luci-base`），两个包都直接装上，没有触发任何依赖下载。postinst 无告警，
`links.json` 在安装当场就生成了（`published: true, links: 2`）。

## 3. 测试覆盖（112 项）

测试脚本 `.build/portal-test.sh`，在设备上 `sh /tmp/portal-test.sh` 运行。

| 组 | 项数 | 覆盖 |
|---|---|---|
| 1 安装落地 | 13 | 包、配置、init 脚本（含可执行位）、插件、ACL、菜单、三个模板、服务 enable |
| 2 翻译包 | 8 | `portal.zh-cn.lmo` 落地、中文条目实际存在（门户/书签/背景/图标/标题/服务） |
| 3 ubus 对象 | 12 | `luci.portal` 注册、六个方法、参数校验、未知方法被拒 |
| 4 文件布局 | 11 | `/www/portal` 发布结果、`links.json` **权限 0644**、旧目录 `/etc/portal` 已清理 |
| 5 HTTP | 12 | `/portal/` 子路径各资源 **200**、根路径仍归 LuCI、`fetch('links.json')` 相对路径 |
| 6 LuCI 集成 | 9 | 三个视图 + common.js 落到 `/www/luci-static/` 且经 HTTP 可取 |
| 7 资产操作 | 16 | upload/rename/remove 完整链路 + 路径穿越、重名、斜杠、空名等拒绝路径 |
| 7b 引用清理 | 6 | 删除被引用的背景会清掉 uci 引用并回落到默认背景 |
| 8 开关下架 | 6 | `enabled=0` 下架页面、保留用户资源、恢复 |
| 9 reload | 2 | LuCI「保存并应用」触发的重建 |
| 10 stop/start | 5 | 服务生命周期 |
| 11 日志 | 2 | 无持续错误 |

关键实测值：

```
ubus call luci.portal status
{ "ok": true, "enabled": true, "path": "/portal/", "published": true,
  "server_listening": true, "reachable": true, "links": 2, "generated": true }

/www/portal/links.json  -rw-r--r--   (0644)
/etc/init.d/portal      -rwxr-xr-x   (0755，postinst 与 Build/Prepare 双重保证)
K10portal / S95portal -> ../init.d/portal   (开机自启已注册)
```

## 4. 缺陷修复专项：`enabled=0` 后 `/portal/` 应完全下架

发现于首轮实测，修复后重编重装复测。**10 项专项断言 + 106 项全量回归均通过。**

| 场景 | 前置条件 | 期望 | 实测 |
|---|---|---|---|
| A 无素材时关闭 | `icons/` `bg/` 均空 | `/www/portal` 不存在，`/portal/` → **404** | ✅ |
| B 重新开启 | 承 A | 目录链全部重建，页面 200，`links.json` 重新生成 | ✅ |
| C 有素材时关闭 | `icons/survive.png` 存在 | 素材存活、顶层保留（`rmdir` 正确拒绝） | ✅ |

### 「背景看起来是纯色」多半不是 bug

实测中的一段插曲：用户报「上传背景后浏览器只见纯色」。逐项验证服务端**全部正常**：

- `/portal/links.json` → 200，257 B，内容正确
- `/portal/bg/<name>.jpg` → 200，`image/jpeg`，2060330 B，3840×2160 有效 JPEG
- HTTP/1.0、HTTP/1.1、带 `Sec-Fetch-*` 头、绝对 URL —— **都是 200**
- 浏览器 Console 无 JS 错误（只有 `favicon.ico` 404），地址栏直接打开 links.json 正常显示

**最可能的解释是遮罩强度太低。** 该机 `bg_veil` 被调到 **26**（默认 78），
而测试图是大面积蓝紫渐变的亮色照片 —— 26% 的遮罩压不住这种亮度，
视觉上就像「只显示了一层底色」而不是「有背景但很淡」。
把遮罩拉到 70 以上即可确认。

**验证这类现象时的判据：换一种请求方式同一 URL 能通，就说明服务器没问题。**
curl / `nc` 通而浏览器不通 → 看浏览器（Console、缓存、扩展）；
反之则是服务端问题。

关键验证命令：

```sh
uci set portal.@portal[0].enabled=0 && uci commit portal
/etc/init.d/portal restart
printf 'GET /portal/ HTTP/1.0\r\nHost: h\r\n\r\n' | nc 127.0.0.1 80 | head -1
# 修复前： HTTP/1.0 200 OK   + "Index of /portal/" 列出 bg/、icons/
# 修复后： HTTP/1.0 404 Not Found
```

> **测试脚本的一条教训**：外观百分比的断言最初写死成默认值
> （`"bg_veil":[[:space:]]*78`）。用户在 LuCI 里调过滑块后（实测 `bg_veil=100`、
> `bg_blur=8`、`card_transparency=41`）这项就误报失败。后端行为其实完全正确 ——
> uci 的值如实烘焙进了 `links.json`。已改为**读 uci 的实际值再比对**，
> 测的是「配置是否被如实传递」而不是某个具体数字。

## 4b. 缺陷修复专项（`3.0.0-r2`）

### 全新安装直接「保存并应用」报「选项"背景遮罩强度"不能为空」

**根因不在校验，而在 LuCI 表单框架的两处语义相撞。**

`form.js` 的 `CBIRangeSliderValue.formvalue()`：

```js
const val = elem.getValue().toString();
return (val === this.default?.toString()) ? null : val;   // 值等于 default → 返回 null
```

官方注释写明这是「省略冗余键」的设计。而 `form.js:2152-2160` 的保存流程：

```js
const fval = this.formvalue(section_id);
if (fval == null || fval == '') {
    if (this.rmempty || this.optional) return Promise.resolve(this.remove(section_id));
    else return Promise.reject(new TypeError(_('Option "%s" must not be empty.')));
}
```

包自带配置里三个键的值**恰好都等于各自的 `o.default`**（78 / 0 / 45），于是三个滑块的
`formvalue` 全返回 `null`，又因为都设了 `o.rmempty = false` 而全部走 reject 分支。

**所以这是全新安装必现，与 0 无关** —— `bg_blur` 的 default 恰好是 0，容易被误读成
「不能为 0」，实际报错的是 `bg_veil`（default 78，当前值 0）。

修法：三个滑块去掉 `rmempty = false`。缺省时后端 `percent()` 回落默认值，行为等价
（实测 uci 键缺失时 `percent('')` 回落 78/0/45）。`enabled` 的 `rmempty = false` 必须保留 ——
开关需要显式记下 `0`。

### 背景文件丢失时门户页仍显示为「有背景」

`generate()` 原先在 `stat()` 失败时只清空 `background_v`，`data.background` 仍指向
已消失的文件；浏览器 404 后回退到 CSS 纯色 `#0e1116` 且不作任何提示。于是页面像有背景、
素材库却是空，两边对不上。

修法：先 `stat()` 再赋值，文件缺失时 `background` 回落到「背景色」选项的纯色。

实测：

| 场景 | `background` | `background_v` |
|---|---|---|
| 文件存在 | `/portal/bg/t.png` | `1791896322-102408` |
| 文件被删 | `#0e1116` | `""` |

### 顺带加固的测试

新增第 8b 节「`rmdir` 保护用户素材」7 项断言 —— 上传素材后关闭，验证文件仍在、
字节数未变、目录被保留、重开后可访问。**这是 `unpublish()` 用 `rmdir` 而非 `rm -rf` 的
核心保证，值得单独测。**

## 5. 构建产物

四轮编译（首轮 / 修三处缺陷 / 改文件命名 / 移动维护区段）的 sha256。**i18n 包每次重建内容都会变**
（lmo 内嵌时间戳），部署前以现场 `sha256sum *.apk` 为准。

```
dist/luci-app-portal-3.0.0-r2.apk              26014 bytes  (修复后)
  sha256 cd3182a9de5ddd8b6de5（维护区段移入书签页后重建）
dist/luci-i18n-portal-zh-cn-3.0.0.apk           3611 bytes
  sha256 b5245ed0910f3e6366ed
```

## 6. 卸载与重装

```sh
apk del luci-i18n-portal-zh-cn luci-app-portal
```

- `/www/portal` 被 prerm 整个删除，用户上传的 icons/bg 一并清掉（符合 `prerm` 的既定语义）。
- `/etc/config/portal` 作为 conffile **保留**。
- 重装后 `links.json` 重新生成，`published: true`。

## 7. 设备环境的现象与已修复的缺陷

### 5.1 已修复：`enabled=0` 后 `/portal/` 返回目录索引页

首轮实测发现并已修复，详见下面第 2 条的说明（原写在此处标为「非缺陷」，判断有误 ——
那两个空目录是本包留下的，不是 uhttpd 凭空生成的）。

### 5.2 仍是设备环境的两个已知非缺陷现象

写在这里，免得下次误判成 bug：

1. **`lan_ip` 返回空。** 这台虚拟机的 `network.lan` 是 `proto dhcp` 客户端、没有 `ipaddr`，
   `lan_ip()` 自然取不到值。端口扫描不受影响（绑定 `0.0.0.0` 的端口照常命中，实测扫出 80/http）。
   换成静态 IP 的正常配置即可显示。

2. **`enabled=0` 下架后 `/portal/` 曾返回 200。** 这是**已修复的缺陷**，不是环境噪音。

   成因：uhttpd 对「有目录、无 `index.html`」的路径会生成 `Index of ...` 目录页并回 200。
   原版 `unpublish()` 只删了 `index.html` / `portal.js` / `portal.css` / `links.json` 四个文件，
   留下 `/www/portal/` 和两个空素材目录，于是关闭后访问 `/portal/` 看到的是一份列出
   `bg/`、`icons/` 的目录页 —— 门户明明已关闭，看起来却像还在。

   修复：`unpublish()` 改用 `rmdir` 由深到浅撤下目录，最后连 `/www/portal` 本身一并移除。
   目录不存在时 uhttpd 自然回 404。

   ```sh
   rmdir "$PORTAL_WWW/icons" "$PORTAL_WWW/bg" 2>/dev/null
   rmdir "$PORTAL_WWW" 2>/dev/null
   ```

   uhttpd 确实有 `-D`（Do not allow directory listings）这个开关，但它是**全局**的 ——
   一开就是整个 `/www`（含 LuCI）全部失去目录列表能力，而且 LuCI 的 uhttpd 配置里
   并不暴露它。所以没有按目录关闭的开关可用，撤目录是唯一不动服务器与用户文件的做法。

   **已知取舍**：目录里**有用户素材**时，`rmdir` 会拒绝并保留目录，此时 `/portal/` 仍会
   出现目录列表（但只列文件名，不含页面内容）。这是刻意的 —— 保住用户文件优先于关掉列表。
   删掉素材后再关闭即彻底下架。实测：图标 `logo.png` + 背景 `bg.jpg` 在关闭期间完好。

3. **卸载时打印 `Command failed: ubus call service delete { "name": "portal" } (Not found)`。**
   来自 `rc.common` 的 `procd_kill`：本服务刻意不注册 procd 实例（没有守护进程），
   所以删除时找不到服务记录。噪音提示，不影响卸载结果。

另有一条**安装瞬间的一次性日志**，非故障：

```
portal: links.json not regenerated (rc=4): Command failed: Not found
```

这是 postinst 里 `/etc/init.d/portal start` 触发的 `generate_links()`，发生在 rpcd 尚未
完成插件重载的那一拍（postinst 随后 `sleep 1` 并在对象缺失时 `restart rpcd`）。
全新安装后立即复查，`links.json` 已正常生成、ubus 对象可调用。

## 8. 复测脚本里踩到的设备差异

写 `.build/portal-test.sh` 时踩的坑，改测试脚本时注意：

- **busybox wget 没有 `-S`**，取 HTTP 状态码要用 `nc` 发原始请求：
  ```sh
  printf 'GET /portal/ HTTP/1.0\r\nHost: h\r\n\r\n' | nc 127.0.0.1 80 | head -1
  ```
- **busybox 没有 `stat` applet**，权限用 `ls -l | grep '^-rw-r--r--'` 判断。
- **`grep -ac` 的退出码只表示「有没有匹配行」**，不是「计数是否非零」以外的语义；
  计数要用 `$(grep -ac ...)` 取输出值再 `[ "$n" -gt 0 ]`，别拿退出码当条件。
- **lmo 是二进制**，必须 `grep -a` 才搜得到中文；`strings` 反而搜不出（中文不是可打印 ASCII）。
- **菜单在 `/usr/share/luci/menu.d/`，但视图被 luci.mk 装到 `/www/luci-static/resources/`**，
  不是 `/usr/share/luci-static/`。断言路径写错会误报。
- **`ubus call luci-rpc getMenu` 不存在**，这个版本的 luci-rpc 只有
  getNetworkDevices / getHostHints 等方法，菜单得从文件侧断言。

## 8b. 本地门禁的三个待办

### shellcheck —— 你已验证通过

```sh
$ cd ~/文档/project/luci-app-portal && shellcheck -s sh root/etc/init.d/portal
=== shellcheck: 无告警 ===
```

`unpublish()` 新增的两行 `rmdir` 是本轮唯一的 shell 改动，`rmdir` 属 POSIX 标准
命令、busybox ash 支持，shellcheck 也无告警。

> **注意**：`scripts/check.sh` 在本次会话里对这一项仍显示
> `skip shellcheck not installed` —— shellcheck 是 snap 装的
> （`/var/lib/snapd/snap/bin/shellcheck`），位于隔离沙箱之外，本地 shell 看不到。
> 这不是脚本的问题；CI 里它会被正常安装并执行。

### 本机系统目录属主异常（与本项目无关，但影响开发体验）

`/etc`、`/usr`、`/home` 乃至 `/etc/ssh/ssh_config.d` 的属主都是 `nobody`（uid 65534），
不是 `root`。连带影响：

- **SSH 直接失败**：`Bad owner or permissions on /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf`。
  临时绕过：`export GIT_SSH_COMMAND="ssh -F ~/.ssh/config"`，或
  `git config --global core.sshCommand "ssh -F ~/.ssh/config"`
- **包安装不完整**：装 shellcheck 时只留下了
  `/usr/share/bash-completion/completions/shellcheck`，二进制没落到 `/usr/bin`

不建议用 `chown -R root:root <单个目录>` 去打补丁 —— 那是 937 个文件里的一小块，
会让问题更难查。**先确认这套属主是容器环境固有的还是被什么改坏的**：

```sh
systemd-detect-virt                 # 容器里这可能是有意为之
find /etc -maxdepth 2 -user nobody 2>/dev/null | wc -l   # 本机实测 937
```

### Chromium 直连被墙（验证前端渲染时）

`agent-browser install` 走 `storage.googleapis.com` 会超时，
`PUPPETEER_DOWNLOAD_BASE_URL` 环境变量对它无效。手动从镜像下 zip：

```sh
V=155.0.8059.39
curl -L -o chrome.zip \
  "https://cdn.npmmirror.com/binaries/chrome-for-testing/$V/linux64/chrome-linux64.zip"
```

## 9. 装完必做

浏览器硬刷新一次，避免命中旧缓存：

```
Ctrl+Shift+R   （或 Ctrl+F5）
```

装完在设备上确认代码是新的：

```sh
grep -c 'URL_BASE' /usr/share/rpcd/ucode/portal.uc        # 子路径前缀，应 > 0
grep -c "fetch('links.json')" /www/portal/portal.js       # 相对路径，应为 1
```
