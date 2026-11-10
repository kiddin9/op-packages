# luci-app-portal 3.0.1-r5 装机验证记录（管理页间距规范化，ROADMAP #26–#30）

日期：2026-10-16
设备：192.168.122.12（ImmortalWrt，apk v3，Argon 主题）

## 构建与产物

- 命令：touchshim 包装 `make package/luci-app-portal/compile -j16 V=s`（沙箱外单实例），日志 `.build/build-release-3.0.1-r5.log`，`EXIT=0`
- 产物：`luci-app-portal-3.0.1-r5.apk`（29,574 B）、`luci-i18n-portal-zh-cn-3.0.1.apk`
- sha256（两端一致）：`378cfa22db252ed6…`

## 修复内容（PR #26，合并为 69359fc）

| 项 | 症状 | 修法 |
|---|---|---|
| #26 | 常规页表单最后一项贴页面下边缘 | `.portal-admin { padding-bottom: 2em }` |
| #27 | 书签行缩略图偏行顶 | `.portal-admin .cbi-section-table .btn { vertical-align: middle }`（缩略图本就 middle，统一按钮对齐轴） |
| #28 | 书签页三按钮贴死 | 批量删除按钮内联 `margin-left:.5em` |
| #29 | 刷新按钮贴左边缘 | 手建面板加 `portal-panel` class → 左右 `padding .6em` |
| #30 | 上传按钮贴左边缘 | 素材两区块同用 `portal-panel` |

实现要点：本版 LuCI `View` 类**无 `css()` 钩子**（luci.js 全文无 `.css()` 消费点，已核实），共享样式 `common.admin_css()` 由各视图在 `render()` 产物内注入 `<style>` 标签，规则全部作用域限定 `.portal-admin`，不触碰主题。

## 设备验证（已过）

| # | 验证点 | 结果 |
|---|---|---|
| 1 | 设备 `common.js` 含 `.portal-admin { padding-bottom: 2em }` 与 `admin_css` | ✓ |
| 2 | `general.js` 含 `portal-admin`（style 注入 + 包裹层） | ✓ |
| 3 | `bookmarks.js` 含 `margin-left:.5em` 与 `portal-admin` | ✓ |
| 4 | `assets.js` 含 `portal-panel` 与 `portal-admin` | ✓ |
| 5 | HTTP 层 `common.js` / `general.js` 均 200 | ✓ |
| 6 | 安装版本 `luci-app-portal-3.0.1-r5` | ✓ |

同时确认 r4 的搜索修复（`depends({search_engine:'custom',search_enabled:'1'})`）仍在包内。

## 待用户浏览器复验（五处，Argon 下）

1. 常规页滚到底：搜索引擎选择框与页面下边缘有呼吸空隙；
2. 书签行：缩略图与行内按钮中线对齐；
3. 书签页：「添加」与两个批量删除按钮之间有间隔；
4. 常规页：「刷新」按钮不再贴卡片左缘；
5. 素材库：「上传」按钮不再贴左缘。
另请确认 Bootstrap 等其它主题下无回归。**浏览器缓存 SPA JS，需 Ctrl+Shift+R 硬刷新。**
