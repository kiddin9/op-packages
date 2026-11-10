# luci-app-liteportal 3.0.2-r1 装机验证记录（软件包更名，ROADMAP #31）

日期：2026-10-16
设备：192.168.122.12（ImmortalWrt，apk v3）

## 构建与产物

- 目标：`make package/luci-app-liteportal/compile -j16 V=s`（SDK 侧软链已改为
  `package/luci-app-liteportal -> 本仓库`），日志 `.build/build-release-3.0.2.log`，`EXIT=0`
- 产物：
  - `luci-app-liteportal-3.0.2-r1.apk`（29,589 B）
  - `luci-i18n-liteportal-zh-cn-3.0.2.apk`（3,710 B）
- 包元数据（`apk adbdump`）：`name: luci-app-liteportal`、`version: 3.0.2-r1`、`arch: noarch`
- sha256（luci-app-liteportal-3.0.2-r1.apk）：`f068364c532ca547…`

## 升级路径（BREAKING，实测走通）

```sh
cp /etc/config/portal /tmp/portal.conf.bak        # 备份（conffile 随旧包移除）
apk del luci-i18n-portal-zh-cn luci-app-portal
apk add --allow-untrusted /tmp/luci-app-liteportal-3.0.2-r1.apk \
                          /tmp/luci-i18n-liteportal-zh-cn-3.0.2.apk
```

## 设备验证（7 项全过）

| # | 验证点 | 结果 |
|---|---|---|
| 1 | `/portal/` 与 `/portal/links.json` HTTP 状态 | 均 200 |
| 2 | `links.json` 的 `search.template` 保留用户选择 | `https://www.bing.com/search?q=%s` |
| 3 | 书签数据保留 | 1 条 |
| 4 | `ubus call luci.portal status` | `ok/enabled/published/server_listening/reachable` 均 true，`generated: true` |
| 5 | 视图文件落地 | `general.js` / `bookmarks.js` / `assets.js` |
| 6 | 翻译 lmo 为 `portal.zh-cn.lmo`（文件名不变） | ✓ |
| 7 | 旧包清除 | `apk info -e luci-app-portal` 为空 |
| 附 | 配置 md5 前后一致（`63b3be1f…`） | ✓ 用户数据无损 |
| 附 | 注册文件为 `menu.d/luci-app-liteportal.json`、`acl.d/luci-app-liteportal.json` | ✓ |

## 说明

- 旧包卸载时 `ubus call service delete { "name": "portal" } (Not found)` 是
  `rc.common` 的 `procd_kill` 对未注册 procd 实例的固定噪音，非缺陷。
- `/etc/config/portal.apk-new` 是包自带配置（本版 search 三键与用户配置相同，无需合并）。
- 运行时标识全部未变：uci `/etc/config/portal`、ubus `luci.portal`、
  `/etc/init.d/portal`、菜单 `admin/portal`、门户页 `/portal/`。
