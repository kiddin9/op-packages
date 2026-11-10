# 运行时标识从 `portal` 全量更名为 `liteportal`

- 状态：已接受
- 日期：2026-10-17
- 决策者：cocolight

## 背景

3.0.2（ADR 0005 之后的首个正式版）只改了 apk / ipk 的**包名**，运行时标识一律保留
`portal`：uci 配置文件 `/etc/config/portal`、ubus 对象 `luci.portal`、服务
`/etc/init.d/portal`、菜单 `admin/services/portal`、门户页 URL `/portal/`、静态目录
`/www/portal`，以及 `portal.uc` / `portal.po` 等文件名的全部。当时的判断是「包名与
运行时标识是两件事，前者会重名冲突，后者不会」。

这个判断在实践中留下了一个长期的认知负担：仓库名、包名、菜单路径、URL、日志 tag
分属两套术语，读代码、写文档、排查故障都要在 `portal` 与 `liteportal` 之间来回翻译。
用户据此要求把两者统一（原话：*将仓库名称也改为 luci-app-liteportal，这些运行时
标识也都相应更改，所有的*）。

## 决策

1. **所有构成对外契约的标识改为 `liteportal`**，一次改齐：

   | 类别 | 旧 | 新 |
   |---|---|---|
   | uci 配置 | `/etc/config/portal`，section 类型 `config portal` | `/etc/config/liteportal`，`config liteportal` |
   | ubus | `luci.portal` | `luci.liteportal` |
   | 服务 | `/etc/init.d/portal` | `/etc/init.d/liteportal` |
   | 菜单 | `admin/services/portal` | `admin/services/liteportal` |
   | 页面 URL | `/portal/` | `/liteportal/` |
   | 静态目录 | `/www/portal` | `/www/liteportal` |
   | 前端模板 | `/usr/share/portal/www` | `/usr/share/liteportal/www` |
   | 上传暂存 | `/tmp/portal_upload.tmp` | `/tmp/liteportal_upload.tmp` |
   | 视图与资源 | `view/portal/`、`resources/portal/` | `view/liteportal/`、`resources/liteportal/` |
   | 后端插件 / 翻译 | `portal.uc`、`portal.po`、`portal.pot` | `liteportal.uc`、`liteportal.po`、`liteportal.pot` |

   门户前端资源文件（`liteportal.js` / `liteportal.css`）与视图样式作用域类
   （`.liteportal-admin` / `.liteportal-panel` / `.liteportal-bm-thumb`）一并更名，
   后者会让主题里针对旧类名的自定义样式失效，代价可接受（那是内部钩子）。

2. **版本记 `4.0.0`**（3.0.2 → 4.0.0）。uci 配置名、ubus 对象与 URL 都是对外 API，
   改名属不兼容变更，按语义化版本记 MAJOR。

3. **不做自动迁移**。`postinst` 不搬运 `/etc/config/portal` 与 `/www/portal`，升级
   方式为先 `apk del` 旧包、再装新包。理由只有一个：本包此前只在维护者的测试虚拟机
   上运行过，没有存量设备，「迁移」是为不存在的用户写代码。

   机制上本可行 —— apk-tools 在同名升级时执行**新版本**的 `post-upgrade` 钩子，
   **不执行旧版本的** `pre-deinstall`；已在设备上实测（3.0.2-r1 → 4.0.0-r1）：
   `/etc/config/portal` 与 `/www/portal` 连同其中的素材在升级后原样留在盘上。所以
   这不是「搬不动」而是「不需要搬」。

   代价是这两个目录会变成无主残留：没人读它们，但 `/portal/` 会继续用旧页面应答，
   直到 `/www/portal` 被手工删掉。因此文档给出的升级步骤是**先卸旧包**（借它自己的
   `prerm` 清干净）、再装新包，而不是原地覆盖。

4. **菜单与页面显示名保留 `Portal`**。那是面向用户的文案，不是标识符；改它只会让
   中文界面多出一个英文单词，且要牵动翻译目录。

5. **仓库更名为 `wrttools/luci-app-liteportal`**，`Makefile` 的 `LUCI_URL` 同步。
   GitHub 对旧 URL 提供重定向。

## 后果

- 正面：仓库、包、配置、对象、服务、路径、日志全部同名，读代码与排障不再需要翻译
  层；`scripts/check.sh` 的交叉引用（ubus 方法 ↔ ACL）也随之统一到 `luci.liteportal`。
- 负面：这是一次不兼容变更。用户若把 `/portal/` 加入过书签会 404；任何外部脚本里写
  死的 `ubus call luci.portal …`、`uci get portal.@portal[0]…`、`/etc/init.d/portal`
  都要跟着改。
- 负面：**旧配置与素材不带过来**。先卸旧包再装新包时，书签、外观与搜索设置回到包内
  默认值，已上传的图标与背景图随旧包的 `prerm` 一起消失。这是「没有存量用户」这一
  前提的直接代价：前提一旦不成立（包被发布给第三方），这条决策就要重审。
- 若选择原地覆盖升级（不卸旧包），`/etc/config/portal` 与 `/www/portal` 会成为无主
  残留并继续占用旧路径 —— `/portal/` 仍然应答旧页面。文档把「先卸后装」写成推荐步骤，
  但无法在代码层阻止用户覆盖升级。
- `postinst` 里不出现任何历史路径的兼容代码，安装脚本只做「建目录 → 注册对象 →
  烘焙 links.json → 启用并启动服务」。

## 替代方案

1. **保留 `/portal/`，在服务端加 301 重定向到 `/liteportal/`。** 放弃：门户由主
   uhttpd 按目录直接提供静态文件（ADR 0004），项目没有 uhttpd 之外的服务端能力，
   而 uhttpd 的重定向配置是全局的 `option redirect`，为一个路径改全局配置不划算。
2. **发布一个转发用的兼容包（空包，仅保留旧名下的 ubus 与 init 脚本）。** 放弃：
   那是一个需要永久维护、只在升级窗口有意义的东西，与项目「不引入冗余组件」的取向
   冲突。
3. **`postinst` 自动搬运旧配置与素材。** 曾按此实现，后放弃：机制上可行（见「决策」
   第 3 条），但「没有存量用户」这一前提让它没有服务对象 —— 为不存在的用户维护一条
   无人验证的数据搬运路径，收益是零。
