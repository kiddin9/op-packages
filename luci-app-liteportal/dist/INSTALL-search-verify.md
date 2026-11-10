# 3.0.1-r2 / r3 装机实测记录 —— 门户页搜索框（ROADMAP #16 / #17）

- **日期**：2026-10-16
- **设备**：192.168.122.12（ImmortalWrt，apk）
- **版本线**：`3.0.1-r2`（#16，PR #23，合并提交 `0f89452`）→ `3.0.1-r3`（#17，PR #24，合并提交 `b6e45e9`）
- **决策记录**：`docs/adr/0006-search-box.md`
- **验收脚本**：`.build/verify-search.sh`（设备侧， busybox 兼容）

## 装了什么

| 项 | 值 |
|---|---|
| 装机前版本 | 3.0.0-r8 |
| 装机后版本 | **3.0.1-r3**（`apk list -I` 确认） |
| 资产 | `luci-app-portal-3.0.1-r3.apk`（29443 B）+ `luci-i18n-portal-zh-cn-3.0.1.apk`（3706 B） |
| uci 变化 | 预设 `search_enabled='1'`、`search_engine='https://www.google.com/search?q=%s'`（供点击测试；升级用户默认不带这两项，即保持关闭） |
| 构建 | touchshim 沙箱外单实例，EXIT=0（任务系统的 failed 为误报，以日志 EXIT 与产物为准） |

## 自动验收结果（`verify-search.sh`：PASS=16 FAIL=0）

| # | 检查 | 结果 |
|---|---|---|
| 1 | 已安装版本 = 3.0.1-r3 | ok |
| 2 | 设置页 `general.js` 含 `search_enabled` / `search_engine` / `search_url` / Custom 项 | ok ×4 |
| 3 | 门户前端 `portal.js` 含 `setup_search()`、IME `isComposing` 守卫、`.open` class 切换、`window.open` | ok ×4 |
| 4 | `links.json` 烘出 `"search": { "template": "https://www.google.com/search?q=%s" }` | ok |
| 5 | uci 预设 `search_enabled=1` + Google 引擎 | ok ×2 |
| 6 | HTTP：`/`、`/portal/`、`/portal/portal.js`、`/portal/links.json` | ok ×4 |

**#16「关闭后零表单」的设备级证据**（验收标准第 2 条）：

```
uci set …search_enabled=0 → reload → links.json: "search": null
uci set …search_enabled=1 → reload → links.json: "search": { "template": "https://www.google.com/search?q=%s" }
```

关闭时前端拿不到模板即不创建任何元素（node 行为测试专项用例佐证：禁用时
FORM/INPUT 创建数为 0），因此页面 `<input>` / `<form>` 计数为 0。

## 其他验证（合并前已完成）

- `sh scripts/check.sh`：ALL CHECKS PASSED（r2、r3 各一次）
- node 行为测试 `.build/test-setup-search.js`（真实 `portal.js` 源码提取 + DOM 桩）：**27/27** ——
  覆盖禁用零 DOM、空查询不开窗、关键字 trim+编码、`&`/`#`/空格编码、`%s` 后固定后缀保留、
  新窗+noopener、空格唤出+聚焦、空值空格隐藏、有值空格放行、IME 合成不响应、
  ctrl/alt 组合键不响应、Escape 隐藏、提交后开窗+清空+隐藏+blur
- SDK ucode 对真实 `search_template()` 源码：**12/12**（预设/自定义/缺省/空值/非 https/含空格/含 tab/带后缀）
- 前端 `validate` 正则与后端 ucode 门同组用例 **9/9**（逐字相同的 `/^https?:\/\/[^ \t]+%s/`）

## 待用户浏览器点击确认（#16 / #17 剩余验收）

设备已预设 `search_enabled=1` + Google，打开 `http://192.168.122.12/portal/`（Ctrl+Shift+R 硬刷新）即可测：

| # | 操作 | 预期 |
|---|---|---|
| 1 | 打开门户页 | 标题与书签网格之间**看不到**搜索框（默认隐藏） |
| 2 | 页面任意位置按空格 | 搜索框出现并自动聚焦 |
| 3 | 输入框有内容时按空格 | 正常输入空格，框不消失 |
| 4 | 清空输入框再按空格 | 框隐藏 |
| 5 | 用中文拼音输入关键词（空格上屏） | 上屏不触发隐藏（IME 守卫） |
| 6 | 输入关键字按回车 | 新标签页打开 Google 结果页（地址栏含关键字），门户页搜索框已隐藏且输入被清空 |
| 7 | 按 Escape | 框隐藏 |
| 8 | LuCI「常规」页 | 「搜索框」开关 + 「搜索引擎」下拉（Google/Bing/DuckDuckGo/百度/自定义）可见；选「自定义」出现 URL 输入框，乱填会被表单拦下 |
| 9 | 关掉开关 → 保存并应用 | 门户页不再有搜索框（links.json `search: null`） |

## 遗留小项

- 上传超限（>2 MiB）报错路径仍未经浏览器实测（`run_rpc()` 失败分支自 r7 起未动）。
- 移动端无实体键盘，空格唤出不可达；触屏设备的唤出方式（常驻图标等）未做，如需再议。
- 自定义引擎把任意第三方 URL 交给访客浏览器访问，隐私提示仅写在设置页描述里（ADR 0006 已记录此取舍）。
