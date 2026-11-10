# 3.0.0-r7 装机实测记录（上传无成功弹窗 + 书签行缩略图）

- **日期：** 2026-10-15
- **目标包：** `luci-app-portal-3.0.0-r7` + `luci-i18n-portal-zh-cn-3.0.0`
- **设备：** 192.168.122.12（r6 → r7 升级）
- **触发：** 用户 2026-10-15 反馈与计划 —— 上传素材的成功弹窗「已上传 xxx。」不需要；
  书签页书签设置素材库图片后，保存按钮左侧显示缩略图。

## 实现内容

| # | 项 | 改动 |
|---|----|------|
| A | 上传无成功弹窗 | `assets.js` 的 `upload()` 把 `run_rpc()` 成功消息从 `_('Uploaded %s.')` 改为 `null`。失败路径不受影响（`run_rpc` 的失败分支在 common.js，与 okMsg 无关）；`refresh_assets()` 重画列表不变。译句从 pot/po 移除 |
| B | 书签行缩略图 | `bookmarks.js` 新增 `icon_url_of()`（复刻 rpcd 插件 `asset_path()` 三分支：`/www/portal/` 前缀 → `/portal/<rest>`、裸文件名 → `/portal/icons/<name>`、其他绝对路径 → `/portal<value>`）、`make_thumb()`、`update_thumb()`；`renderRowActions()` 在 Save 按钮前插入 `<img class="portal-bm-thumb">`（初次渲染与扫描追加两条路径都经过该方法）；`icon` option 挂 `onchange` → `update_thumb()` 实时跟上下拉框 |

**设计取舍**：仅素材库图片（`icon` 字段）驱动缩略图 —— 「图标」列填 emoji 或外链 URL 时
不拉第三方图装饰设置页。缩略图 URL 与门户页走同一套转换，保证「缩略图显示的」与
「门户显示的」是同一张图。

## 构建与装机

```
EXIT=0（.build/build-r7.log）
bin/packages/x86_64/base/luci-app-portal-3.0.0-r7.apk    27001 B
bin/packages/x86_64/base/luci-i18n-portal-zh-cn-3.0.0.apk 3513 B
```

装机前核对（`apk adbdump` + 暂存区 grep + `node --check`）：`version: 3.0.0-r7`；
暂存 assets.js 无 `Uploaded`、`callUpload(...)` 后 70 字符内含 `, null)`；暂存
bookmarks.js 四件套在位；压缩产物语法有效。

```
apk add --allow-untrusted ... → (1/2) Upgrading luci-app-portal (3.0.0-r6 -> 3.0.0-r7)
OK: 33.7 MiB in 257 packages
```

## 验证

`sh /tmp/verify-r7.sh` → **PASS=32 FAIL=0**：

| 节 | 内容 | 结果 |
|---|---|---|
| 1 | 版本 `3.0.0-r7（apk 安装）` | ok |
| 2 | r6 全部检查项回归（三个新函数、`maintenance_section` 收 `on_add`、旧代码 0 处、reload 仅限 `reload_soon`、补缓存偏移 4467 < 4578、confirm_scan 无多余 notify、5 条译句进 lmo） | 17 ok |
| 3 | 修复 A：无 `Uploaded %s`、lmo 无「已上传 %s。」、`run_rpc` 成功消息为 null | 3 ok |
| 4 | 修复 B：三件套 + `portal-bm-thumb` + 三分支 URL + onchange 绑定 | 7 ok |
| 5 | 后端 scan 返回 `ports` / `lan_ip` | 2 ok |

附加功能冒烟：设备 `/portal/icons/1791889817.png` 经 HTTP **200 OK**（缩略图 URL
规则真实可访）；scan 前后 `uci show portal` md5 不变（后端零写入）。

## 验证脚本自身的两个误报（已修）

1. **「lmo 无已上传」误报**：enabled 选项的合法译句「……已上传的图标与背景图在两种
   状态下都保留」也含「已上传」三字。收紧为整句 `已上传 %s。`。
2. **区间截取败在空格**：工作区源码 `onchange = function` / `dir), name` 的等号与
   逗号两侧有空格，jsmin 压缩版才无空格。区间正则统一用 `.` 通配两侧空白，
   一条模式同时匹配工作区版与压缩版。

## 待用户确认

`verify-r7.sh` 末尾 6 项：上传无通知（1）、超限仍报错（2）、缩略图显示（3）、
下拉框即时更换（4）、无素材行无缩略图（5）、以及 ROADMAP #23 的 7 项扫描验收（6）。
设备当前没有书签使用素材图（`icon` 均为空），缩略图的真实显示需用户设置后才能看到。
