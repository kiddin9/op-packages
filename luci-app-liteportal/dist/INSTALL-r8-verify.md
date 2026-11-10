# 3.0.0-r8 装机实测记录（删除/保存无成功弹窗 + 缩略图 404 修复）

- **日期：** 2026-10-15
- **目标包：** `luci-app-portal-3.0.0-r8` + `luci-i18n-portal-zh-cn-3.0.0`
- **设备：** 192.168.122.12（r7 → r8 升级）
- **触发：** 用户 2026-10-15 反馈 —— (1) 删除成功提示也不要；(2) 点击「保存」的
  「已保存该书签。」去掉；(3) #25 未修复，缩略图仍不显示，「可以用素材库显示图片的
  能力，拿过来用」。

## 实现内容

| # | 项 | 改动 |
|---|----|------|
| A | 删除/保存无成功弹窗 | `bookmarks.js`：行内 `save_row` 的 `run_rpc()` 成功消息 `_('Bookmark saved.')` → `null`；批量删除的成功消息函数 `_('Deleted %d bookmark(s).')` → `null`。`assets.js`：素材删除 `_('Deleted %s.')` → `null`。译句从 pot/po 移除 |
| B | 缩略图 404 修复（#25） | 根因：`icon_url_of()` 的「素材库图片」分支拿 `ICON_DIR`（`/www/portal/icons`，比 rpcd 的 `WWW` 深一层）切路径，产出 URL 丢掉 `icons/` 段 → `/portal/<文件名>` → 404。修复：新增 `WWW = '/www/portal'` 常量，切在 `WWW` 上（与 rpcd `asset_path()` 完全对齐） |

**根因说明**：r7 的代码断言只查「函数在不在」，没有真实调用过转换，所以漏放了 bug。
r8 起验证脚本内置 6 组输入的真实调用测试防再回归。

## 构建与装机

```
EXIT=0（.build/build-r8.log）
bin/packages/x86_64/base/luci-app-portal-3.0.0-r8.apk    26974 B
bin/packages/x86_64/base/luci-i18n-portal-zh-cn-3.0.0.apk  3468 B
```

装机前核对（暂存区 grep + `node --check`）：`slice(WWW.length+1)` 在位、旧
`slice(ICON_DIR.length` 0 处；三条旧译句（`Bookmark saved` / `Deleted %d bookmark` /
`Deleted %s`）+ r7 的 `Uploaded %s` 均 0 处；`portal-bm-thumb` 在位；5 个 JS 压缩
产物语法有效。

```
apk add --allow-untrusted ... → (1/2) Upgrading luci-app-portal (3.0.0-r7 -> 3.0.0-r8)
  Installing file to etc/config/portal.apk-new
OK: 33.7 MiB in 257 packages
```

`portal.apk-new` 为包内默认配置与设备上用户配置的差异文件，按 apk 语义留存不生效；
用户 uci 数据（含首条书签预设的 `icon=/www/portal/icons/1791889817.png`）原样保留。

## 验证

`sh /tmp/verify-r8.sh` → **PASS=17 FAIL=0**：

| 节 | 内容 | 结果 |
|---|---|---|
| 1 | 版本 `3.0.0-r8（apk 安装）` | ok |
| 2 | `icon_url_of` 真实调用测试 | skip（设备 busybox 无 node，本地补跑 6/6） |
| 3 | WWW 切段 + `WWW` 常量 + `portal-bm-thumb` + onchange 绑定 | 4 ok |
| 4 | 行内保存 / 批量删除 / 素材删除 / 上传（r7 回归）四处 `run_rpc` 成功消息为 null | 4 ok |
| 5 | 三条旧译句在 bookmarks.js / assets.js / lmo 中均消失；按钮文字 `Saved` 保留 | 7 ok |
| 6 | `common.js` `scan_candidates` 在位（3 处） | ok |

本地补跑：对**设备安装的压缩版** `bookmarks.js` 提取 `icon_url_of` 真实调用，
6/6 通过（`/www/portal/icons/1791889817.png` → `/portal/icons/1791889817.png`、
裸文件名、`bg/` 路径、空值、null）。提取用花括号配对而非 `\n}`——压缩产物单行无
换行。

附加功能冒烟：`/portal/`、`/portal/portal.js`、`/portal/icons/1791889817.png`、
`/portal/links.json` 经 HTTP 均 200（wget exit=0）；`links.json` 内容合法，
`icon` 字段为 `/portal/icons/1791889817.png`。

**portal 服务状态说明**：`/etc/init.d/portal status` 显示 `active with no instances`
是设计使然——该服务刻意不开 procd 实例，页面由主 uhttpd 以 `/www/portal` 子路径
提供；`restart` 已重新 publish 模板文件并再生成 links.json。

## 验证脚本自身的四个误报（已修，均非代码回归）

1. **版本解析**：设备 `apk info` 输出为 `luci-app-portal-3.0.0-r8 description:...`，
   原 sed+tr 把描述拼进了版本串。改为先 `awk '{print $1}'` 取第一列再剥前缀。
2. **设备无 node**：第 2 节 node 测试改为 `command -v node` 守卫，无则 skip，
   由本地对同一文件补跑（本次已补，6/6）。
3. **等号数**：jsmin 压缩后 `indexOf(WWW+'/')===0` 是三个等号，脚本写的 `==0`
   匹配不上。模式放宽为 `===\{0,1\}0`。
4. **批量删除误匹配函数定义**：`drop_sections(sids)` 的函数定义排在调用点之前，
   `head -1` 取到的是定义体。改为锚定调用点 `drop_sections(sids).then(...` 并查
   尾部 `},null)`。

## 待用户确认

浏览器点击验收（`verify-r8.sh` 末尾清单 A/B 共 7 项）：

1. 上传一张图：不弹「已上传」通知（r7 已确认，回归）
2. 给某行「图标」下拉选一张素材库图片：保存按钮左侧立即出现缩略图（**#25 本轮
   修复重点；设备首条书签已预设素材图标，打开书签页即应可见**）
3. 改下拉框换一张：缩略图即时更换，无需保存
4. 下拉选回空：缩略图消失
5. 点行内「保存」：不弹「已保存该书签。」，按钮文字变「已保存」
6. 「删除禁用的书签」/「清空所有书签」：确认对话框照旧，删除后不弹
   「已删除 N 个书签。」
7. 素材库页删除一张图：确认对话框照旧，删除后不弹「已删除 xxx。」

以及 ROADMAP #23 的扫描验收 7 项（r6 起挂起，需 Ctrl+Shift+R 硬刷新后实测）。
