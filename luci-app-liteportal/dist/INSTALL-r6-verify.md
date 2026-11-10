# 3.0.0-r6 装机实测记录（ROADMAP #23 修复轮）

- **日期：** 2026-10-15
- **目标包：** `luci-app-portal-3.0.0-r6` + `luci-i18n-portal-zh-cn-3.0.0`
- **设备：** 192.168.122.12（r5 → r6 升级）
- **触发：** 用户在 r5 装机后实测反馈两条 —— 扫描添加的书签行「名称」「URL」为空；
  点「添加所选」后又弹出「已在列表末尾添加 N 个书签…」通知。

## 修复内容

| # | 问题 | 根因 | 修法 |
|---|------|------|------|
| A | 新行「名称」「URL」为空 | `form.TableSection` 的每个 option widget 各有一份配置值缓存（`option.data[sid]`），仅页面加载时由 `CBIAbstractSection.load()` 填入。扫描走的是加载后发生的 `uci.add()`：新 section 对 `uci.get()` 可见（`uci.js` 的 `get()` 先查 `state.creates`，保存链路一直通），却不在任何 option 缓存里，`cfgvalue()` 返回 `undefined` | `append_sections()` 渲染前逐 option `opt.load(sid)` + 两参数 `cfgvalue(sid, value)` 写回缓存。不复用 `loadChildren()`：它跳过 `disable` 的 option，返回值与 `children` 索引对不上 |
| B | 添加后多余通知 | `confirm_scan()` 在 `on_add(sids)` 完成后 `notify()`「Added %d bookmark(s)…」——说的就是列表已显示的事，且浮在新增行上方 | `on_add` 完成后直接结束，不再通知；译句从 pot/po 移除 |

## 构建

```
EXIT=0（.build/build-r6.log）
bin/packages/x86_64/base/luci-app-portal-3.0.0-r6.apk    26634 B
bin/packages/x86_64/base/luci-i18n-portal-zh-cn-3.0.0.apk 3526 B
```

装机前核对（`apk adbdump` + 暂存区 grep + `node --check`）：

- `version: 3.0.0-r6`、`arch: noarch`、依赖同 r5
- 暂存 bookmarks.js 含 `opt.load(sid)` ×1、`cfgvalue(sid,` ×1，偏移 3499 < 3610（补缓存早于渲染）
- 暂存 common.js 无 `Added %d bookmark`
- `node --check` 压缩产物语法有效（JsMin 默认开启，见 r5 记录）

## 装机与验证

```
apk add --allow-untrusted /tmp/luci-app-portal-3.0.0-r6.apk /tmp/luci-i18n-portal-zh-cn-3.0.0.apk
(1/2) Upgrading luci-app-portal (3.0.0-r5 -> 3.0.0-r6)
(2/2) Replacing luci-i18n-portal-zh-cn (3.0.0 -> 3.0.0)
OK: 33.7 MiB in 257 packages
```

`sh /tmp/verify-r6-scan.sh` → **PASS=25 FAIL=0**：

| 节 | 内容 | 结果 |
|---|---|---|
| 1 | 版本 `3.0.0-r6（apk 安装）` | ok |
| 2 | r5 检查项全量回归（三个新函数、`maintenance_section` 收 `on_add`、旧代码 0 处、reload 仅限 `reload_soon`、5 条译句进 lmo） | 16 ok |
| 3 | 修复 A：`opt.load(sid)` / `cfgvalue(sid,` 在位，且补缓存偏移 3499 早于 `renderUCISection` 偏移 3610 | 3 ok |
| 4 | 修复 B：无 `Added %d bookmark`、lmo 无「已在列表末尾添加」、`stage_bookmarks(chosen)` 至「添加所选」之间无 notify | 3 ok |
| 5 | 后端 scan 返回 `ports` / `lan_ip` | 2 ok |

附加功能检查：`ubus call luci.portal scan` 前后 `uci show portal` md5 不变（**零写入**）；
`/portal/` 与新 bookmarks.js 经 HTTP 均 200 OK。

## 环境陷阱（本轮新增）

1. **busybox grep 没有 `-b`**（`unrecognized option: b`）——设备上做「顺序断言」不能靠
   `grep -bo` 拿字节偏移，改用 `awk '{ print index($0, "...") }'` 子串定位。
2. **压缩单行流让「行号顺序」断言失效**——jsmin 产物整份文件约十几行，两个目标同在
   一行，行号比较失去意义；必须比字符偏移。
3. **固定长度窗口会飘出函数体**——截 `stage_bookmarks(chosen)` 后 200 字符时，窗口
   越过了 click handler 的结尾，抓到下一个函数的 `notify` 定义，误报。窗口必须以
   区间终点（`_('Add selected')`）为锚，且先把文件 `tr -d '\n'` 拍平成单行流，
   让断言对压缩产物与工作区格式化工整版走同一条路径。

## 待用户确认

浏览器点击清单（`verify-r6-scan.sh` 末尾 7 项）仍需人工：重点为第 4 项（不再弹多余
通知）与第 5 项（新行名称/URL 有值）。
