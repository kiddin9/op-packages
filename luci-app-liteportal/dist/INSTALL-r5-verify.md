# luci-app-portal 3.0.0-r5 装机实测记录（#23 扫描交互改造）

在 **ImmortalWrt 25.12.2 / x86_64 / apk-tools 3** 设备（192.168.122.12）上完成
「SDK 编译 → 安装 → 设备侧验证」。本轮主题：**「扫描本地服务并添加」先确认再写入 +
只追加新行（不整页刷新）**。

```
SDK bin/packages/x86_64/base/luci-app-portal-3.0.0-r5.apk      26634 bytes
  sha256 83e442e06fd1d6fed7374b42a4eedf0dd51cc713b28feaf4ce6dadb621b51c10
SDK bin/packages/x86_64/base/luci-i18n-portal-zh-cn-3.0.0.apk    3572 bytes
  sha256 7abc385333f9dd0ef2250bd1703ea0fc79c7acf8ce4fcc0fefbfa7f36ad86042
```

> i18n 包每次重建内容都会变（lmo 内嵌时间戳），部署前以现场 `sha256sum *.apk` 为准。
> SDK 路径：`/home/aliha/build/immortalwrt/immortalwrt-sdk-25.12.2-x86-64_gcc-14.3.0_musl.Linux-x86_64/`。
> dist/ 下的正式副本随发版提交时一并更新。

## 1. 构建（含一个关键修复）

前四次构建「退出但无 r5 产物」的根因：**SDK `.config` 里
`# CONFIG_PACKAGE_luci-app-portal is not set`**。`include/package-pack.mk` 规定只有
该符号非空时 `compile` 目标才依赖 apk 文件本身，否则只跑 prepare/configure/compile
链、**静默不打包**（无警告、退出码 0）。

```sh
SDK=/home/aliha/build/immortalwrt/immortalwrt-sdk-25.12.2-x86-64_gcc-14.3.0_musl.Linux-x86_64
sed -i 's/^# CONFIG_PACKAGE_luci-app-portal is not set$/CONFIG_PACKAGE_luci-app-portal=y/' "$SDK/.config"
echo 'CONFIG_PACKAGE_luci-i18n-portal-zh-cn=y' >> "$SDK/.config"
# 然后用 touchshim 包装器跑（utimensat 被沙箱拒，见下）：
/home/aliha/.workbuddy/binaries/touchshim/build-with-touchshim.sh package/luci-app-portal/compile 16
```

依赖已 built 的 SDK 上这轮只需分钟级。产物核对：

- `apk adbdump`：version `3.0.0-r5`、arch `noarch`、7 项依赖
- 暂存区（`build_dir/target-x86_64_musl/luci-app-portal/ipkg-all/`）：
  `scan_candidates`/`stage_bookmarks`/`confirm_scan` 在位，旧代码 0 处
- i18n 的 `portal.zh-cn.lmo` 含 5 条新译句（发现本地服务 / 添加所选 /
  未添加任何书签 / 尚未加入书签 / 端口类型未识别）

## 2. 安装

```sh
scp -O ... <两个 apk> root@192.168.122.12:/tmp/
ssh root@192.168.122.12 'apk add --allow-untrusted /tmp/luci-app-portal-3.0.0-r5.apk /tmp/luci-i18n-portal-zh-cn-3.0.0.apk'
# → Upgrading luci-app-portal (3.0.0-r4 -> 3.0.0-r5) / Replacing luci-i18n-portal-zh-cn
```

sha256 两端一致；设备 7 项依赖（libc / luci-base / rpcd-mod-ucode / ucode /
ucode-mod-fs / ucode-mod-uci / uhttpd）安装前已全部就位。
`/etc/config/portal` 有本地修改，新默认存为 `portal.apk-new`——r4→r5 无 uci 默认
变更，差异即用户书签，保留待用户处置。

## 3. 设备侧验证结果（`sh /tmp/verify-r5-scan.sh`）

**PASS=19 FAIL=0**，含版本项 `luci-app-portal = 3.0.0-r5（apk 安装）`。
五项分组：版本 / 新代码在位 / 旧代码消失 / 新译句进 lmo / 后端 scan 无损。

补充功能检查：

| 检查 | 结果 |
|---|---|
| `ubus call luci.portal scan` 前后 `uci show portal` md5 | 一致（**扫描零写入** ✓） |
| `links.json` 重新生成 | 07:54，166 B |
| `GET /portal/`（主 uhttpd 子路径） | HTTP 200 |
| `GET /luci-static/resources/portal/common.js` | HTTP 200（新代码在线） |
| `ubus call luci.portal status` | `ok:true, enabled:true, published:true` |

## 4. 环境陷阱（复测时避开）

1. **apk 里的 JS 是压缩版的**：luci.mk 的 `CONFIG_LUCI_JSMIN` 默认 y，构建时对
   htdocs 下所有 `.js` 跑 jsmin——注释剥掉、空格清掉，与仓库源文件语义相同、
   字节不同（r4 备份同样是压缩版，是一贯发布形态）。设备侧 grep 模式必须空格
   宽容；`node --check` 验证压缩产物语法（本轮两个文件均通过）。
2. **后台任务系统的 failed 判定会误报**：构建实际成功（日志末尾 `EXIT=0`），
   任务通知仍标 failed——以日志退出码和产物为准，别被通知带偏。
3. **设备 `/tmp` 会被清**：验证脚本传上去后可能不翼而飞，复测前重新 scp。
4. **设备无 curl**：用 `printf 'GET /path HTTP/1.0\r\nHost: h\r\n\r\n' | nc 127.0.0.1 80`。
5. **沙箱对 SDK 深层路径间歇性 ENOENT**：同一命令重试即可。
6. **设备 root 密码为空，LuCI 一律 403 拒登**：浏览器侧点击验收需先
   `passwd` 设密码（会改变设备认证状态，未擅自操作）。

## 5. 未完成项（需用户）

浏览器 6 项点击验收（ROADMAP #23 验收标准 1–4 的交互部分）：弹窗勾选默认态 /
不确认零写入 / 末尾追加不整页刷新 / 通知可读完 / 占位行移除 / 新行可存可删。
前置：设备设 root 密码后登录 `http://192.168.122.12/cgi-bin/luci/` →
Services → Portal → Bookmarks（**先 Ctrl+Shift+R 硬刷新**，避免旧缓存误判）。
