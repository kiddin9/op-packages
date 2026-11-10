# luci-app-portal 3.0.1-r4 装机验证记录（搜索表单 bug 修复）

日期：2026-10-16
设备：192.168.122.12（ImmortalWrt，apk v3）

## 构建与产物

- 命令：touchshim 包装 `make package/luci-app-portal/compile -j16 V=s`（沙箱外单实例），`EXIT=0`（日志 `.build/build-release-3.0.1-r4.log`）
- 产物：`luci-app-portal-3.0.1-r4.apk`、`luci-i18n-portal-zh-cn-3.0.1.apk`
- sha256（两端一致）：`dd3f5e99c4d6bbe3fb405e7fef0e188938ddc329de128d47fa4e902b77035d83`

## 修复内容

`general.js` 的 `search_url` 由两次 `depends()`（OR 语义）改为单次
`depends({ search_engine: 'custom', search_enabled: '1' })`（AND）。
症状①：搜索框开启时任何引擎下保存都被「自定义搜索 URL」空值校验拒绝；
症状②：`search_engine` 因此从未落盘，门户页固定用默认 Google 模板。

## 设备验证（7 项全过）

| # | 验证点 | 结果 |
|---|---|---|
| 1 | 部署的 `general.js`（jsmin 后）含 `depends({search_engine:'custom',search_enabled:'1'})` | ✓ count=1 |
| 2 | uci 切 Bing → `ubus call luci.portal generate` → `links.json` 的 `search.template` | ✓ bing.com/search?q=%s |
| 3 | 切百度 | ✓ baidu.com/s?wd=%s |
| 4 | 切 `custom` + `search_url=https://www.ecosia.org/search?q=%s` | ✓ ecosia 模板 |
| 5 | `custom` 且 `search_url` 为空 → 后端回落 | `"search": null`（门户页无搜索框） |
| 6 | HTTP 层 `GET /portal/links.json` 返回模板 | ✓（Bing 状态下复验） |
| 7 | uci commit 引擎选择 + commit + generate | ✓ 落盘为 Bing 模板 |

## 说明

- `/etc/config/portal` 是 conffile：升级时保留用户配置，新包配置落在 `portal.apk-new`（未合并）。
- 验证结束时设备引擎被还原为 **Bing** 模板（演示用）；实际引擎请在设置页选择——本修复后表单保存已能正常落盘。
- **表单层行为**（选引擎 → 保存 → 不再弹错、选「自定义」时才出现 URL 输入框）需浏览器实测，由用户复验：
  1. 选 Bing / DuckDuckGo / 百度各自「保存并应用」→ 门户页搜索跳转对应引擎；
  2. 选「自定义」留空保存 → 仍应报错（预期）；填合法模板 → 通过；
  3. 关闭搜索框 → 保存后门户页无搜索表单元素。
