# luci-app-liteportal 4.0.0-r1 装机验证记录（运行时标识全量更名，ROADMAP #32）

日期：2026-10-17
设备：192.168.122.12（ImmortalWrt，apk v3）
结论：**73 项断言全过（PASS=73 FAIL=0）**，另有 HTTP 层补充证据。

## 构建与产物

- 目标：`make package/luci-app-liteportal/clean` → `make package/luci-app-liteportal/compile -j16`，
  经 `~/.workbuddy/binaries/touchshim/build-with-touchshim.sh` 包装（`utimensat` 策略限制），
  日志 `/tmp/build-400-v2.log`，`EXIT=0`
- 产物（`$SDK/bin/packages/x86_64/base/`）：

| 包 | 大小 | sha256 |
|---|---|---|
| `luci-app-liteportal-4.0.0-r1.apk` | 29,895 B | `431c1d1a4ccf33f558a99ff3aab38efc3c50365abe7f90f2c822b83c9fc21e4c` |
| `luci-i18n-liteportal-zh-cn-4.0.0.apk` | 3,715 B | `a34a2154ae46799671046ce35b8e6a6b3b1b24a096fc529d433b8baa19a092d0` |

> 第一次构建（08:40，29,735 B / `6996651b…`）之后 Makefile 里的 postinst 注释又被改写
> （把"旧 prerm 会 `rm -rf /www/portal`"这句被实测推翻的推断换成实测结论），但未重编 ——
> 于是产物的 `postinst-pkg` 仍是旧文案。已 `clean` 后重编。**教训：改 Makefile 的 postinst
> 注释也算改产物，必须重编，否则装机脚本与仓库不一致。** 上表为最终产物。

## 安装路径（全新安装，无迁移）

```sh
apk del luci-app-portal luci-i18n-portal-zh-cn   # 若装有 3.x
# 无主残留按需手工清（见下）
apk add --allow-untrusted /tmp/luci-app-liteportal-4.0.0-r1.apk \
                          /tmp/luci-i18n-liteportal-zh-cn-4.0.0.apk
```

4.0.0 **不携带任何升级迁移代码**。若设备曾跑过 3.0.2，`/etc/config/portal`、`/www/portal`
等旧路径不会被新包接管，也不被自动删除，需手工清理后开始干净状态：

```sh
rm -rf /etc/config/portal /www/portal \
       /www/luci-static/resources/view/portal /www/luci-static/resources/portal
```

本轮实测正是这么做的：3.0.2-r1 → 4.0.0-r1 原地覆盖升级后，上述四项原封不动留在盘上
（apk-tools 只跑**新版本**的 `post-upgrade`，不跑**旧版本**的 `pre-deinstall`）。

## 设备验证结果（`/tmp/verify-400.sh`，PASS=73 FAIL=0）

| 节 | 覆盖 | 结果 |
|---|---|---|
| 1 | 版本 `luci-app-liteportal=4.0.0-r1`、`luci-i18n-liteportal-zh-cn=4.0.0` | 2/2 |
| 2 | 旧标识彻底消失：`/etc/config/portal`、`/etc/init.d/portal`、`/www/portal`、`/usr/share/portal`、`view/portal/`、`resources/portal/`、`ucode/portal.uc`、旧 menu/acl json、旧 lmo、ubus `luci.portal`、`links.json` 无 `/portal/` 前缀 | 12/12 |
| 3 | 新标识全部就位：配置、服务、ucode、menu、acl、三个视图、`resources/liteportal/common.js`、静态树四文件、`config liteportal` 段、`uci` 可读、ubus `luci.liteportal` | 16/16 |
| 4 | 安装脚本不含历史路径兼容代码（`postinst` 可执行部分不引用四个旧路径；含 `mkdir -p /www/liteportal` 与 `ubus call luci.liteportal generate`） | 6/6 |
| 5 | 部署后 `menu.d` 的 `path` ↔ `view/*.js` 存在性（本次踩过的坑）+ 菜单路径 `admin/services/liteportal` | 4/4 |
| 6 | HTTP：`/liteportal/`、`/liteportal/liteportal.js`、`/liteportal/liteportal.css`、`/liteportal/links.json` 均 200；`/portal/` 不再 200（404） | 5/5 |
| 7 | ubus 六个方法（`generate/scan/status/upload/remove/rename`）在位；`status` 的 `ok/path=/liteportal//published/reachable`；`scan` 返回 `ports`；未知方法被拒 | 12/12 |
| 8 | `links.json` 反映 uci（`search.template` 为 Bing、`title` 取自 uci）；`reload` 触发重新烘焙（mtime 前进） | 3/3 |
| 9 | ACL 组名 `luci-app-liteportal`、授权 `luci.liteportal`、含新路径、无旧路径；`init` 0755、`links.json` 0644 | 7/7 |
| 10 | `liteportal.zh-cn.lmo` 落地且含中文条目 | 3/3 |
| 11 | 服务已 enable、`reload trigger` 为 `liteportal`、init 内 `uci get` 用 `liteportal.@liteportal` | 3/3 |

### HTTP 层补充证据（针对「设置页整页空白」根因）

`menu.d` 的 `path` 与视图文件不匹配时 LuCI **不会报错，只是内容区空白**，所以单独验了一层：

| 请求 | 结果 |
|---|---|
| `/luci-static/resources/view/liteportal/general.js` 等三个视图模块 | 200 |
| `/luci-static/resources/liteportal/common.js` | 200 |
| `/luci-static/resources/view/portal/general.js`、`/luci-static/resources/portal/common.js`（旧路径） | 404 |
| `/tmp/luci-indexcache.*.json` 中的 `portal` 词形 | 仅 `liteportal` / `liteportal/{general,bookmarks,assets}`，无旧标识 |
| 部署后静态树 | `/www/liteportal/{index.html,liteportal.js,liteportal.css,links.json}` + `bg/` `icons/`；`view/liteportal/{general,bookmarks,assets}.js`、`resources/liteportal/common.js` |

`ubus call luci.liteportal status` 实测返回：

```json
{ "ok": true, "enabled": true, "path": "/liteportal/", "published": true,
  "server_listening": true, "reachable": true, "links": 2, "generated": true,
  "generated_at": 1792199091 }
```

## 已知非缺陷现象

- 清残留后 `ubus list | grep -i portal` 仍可能列出 `luci.liteportal` —— rpcd 的注册缓存未刷新，
  执行 `/etc/init.d/rpcd reload` 即消失。
- 卸载时 `ubus call service delete { "name": "liteportal" } (Not found)` 是 `rc.common` 的
  `procd_kill` 对未注册 procd 实例的固定噪音（本包不起 procd 实例），非缺陷。
- `/tmp/luci-indexcache.*.json` 在安装后再次访问 LuCI 时会重建，属预期；postinst 已清一次，
  重建内容只含新标识。

## 未执行项（浏览器交互，需人工）

本轮把「资源能否加载」机器化了（上表），但**真实浏览器中的视觉与交互**未自动验证：

1. 左侧「服务 → Portal」进得去，三个子页（常规 / 书签 / 素材库）**不空白**
2. 地址栏为 `.../admin/services/liteportal/general`
3. 常规页状态面板显示「可访问」、链接指向 `/liteportal/`；「保存并应用」不报错
4. 书签页上传图片后缩略图即时显示（不 404）；改「图标」下拉缩略图即时更换
5. 三个页面字段名与按钮均为中文

其中 1、2 的路径类风险已被第 5 节与 HTTP 表覆盖；3–5 属 UI 交互逻辑，本次改动只换路径、
未动逻辑，风险低。

## 复测方法

```sh
scp -O -F /dev/null .build/verify-400.sh root@192.168.122.12:/tmp/
ssh root@192.168.122.12 'cd /tmp && sh verify-400.sh'
```
