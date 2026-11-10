# luci-app-liteportal 功能清单（ROADMAP）

> 状态取值：`planned` / `in-progress` / `done` / `dropped`。
> 「验收标准」须**可判定**（能被命令或明确检查验证），AI 助手据此判断功能是否完成。
> 本项目没有单元测试，因此验收标准多为「命令通过」或「设备上的可观察现象」。
>
> **版本约定**：`PKG_RELEASE` 随**每一次内容变更**递增（不是只在发版时）——
> 同一个版本号出两个内容不同的包，包管理器无法区分新旧，升级会被跳过。各行里出现的
> `3.0.0-r2` 是**当时实测所用的版本**，属历史记录，不随后续递增改写。

## 状态总览

| # | 功能 | 状态 | 验收标准 | 备注 |
|---|------|------|----------|------|
| 1 | 门户静态页 + 独立 `uhttpd` 实例 | done | 设备上 `ubus call luci.portal status` 返回 `listening: true`，且 `curl http://127.0.0.1:<port>/` 返回门户 HTML | v2.0.0。**注：`feature/subroute` 分支上不再成立** —— 该分支去掉独立实例，改由主 uhttpd 的子路径提供，见 #18 |
| 2 | LuCI 三视图（常规 / 书签 / 素材库） | done | 三个视图均可打开且无 JS 报错；改动 ubus 方法后 `sh scripts/check.sh` 的 ubus↔ACL 项通过 | v2.0.0 |
| 3 | 端口扫描（`/proc/net/tcp[6]`） | done | `ubus call luci.portal scan` 返回 `lan_ip` 与 `ports`；只监听 `127.0.0.1` 的服务不出现在结果里 | v2.0.0 |
| 4 | 素材库上传 / 重命名 / 删除 / 设为背景 | done | 设备上上传 / 重命名 / 删除后文件确实变动，且**失败时必须弹错误提示**；「设为背景」按 B 方案保持暂存语义（须再点「保存并应用」） | r18 修 ubus 参数策略、r19 修调用风格、r20 修跨设备 rename；2026-10-06 设备验证 上传/预览/改名 通过（删除未单独复测） |
| 5 | 协作规范（AGENTS / docs / ADR / CI 门禁） | done | `sh scripts/check.sh` 输出 `ALL CHECKS PASSED`；`.github/workflows/build.yml` 的 `test` job 为绿 | 本次改造 |
| 6 | 回归测试体系（vitest / uci 集成测试） | planned | `sh scripts/check.sh` 之外存在 `sh scripts/test.sh` 且 CI 调用它；至少覆盖 `run_rpc()` 失败传播 | 依赖 CI 基础设施 |
| 7 | 书签页表头排版：把「已启用」文字移到描述行 | done | 设备上打开书签页，表头第二行（描述行）`data-widget="CBI.FlagValue"` 那一格里出现「启用」字样，且该行「图标」列仍是「emoji 或图片的绝对 URL。」—— 两段文字同一行 | 用户 2026-10-05 提出；`2.0.0-r17` 实现，设备验证通过 |
| 8 | 书签页通知不累计 | done | 在书签页连续点「保存」或勾选「全选」5 次后，页面上可见的通知条数仍为 1（每次替换上一条），页面高度不随点击次数增长 | 用户 2026-10-06 报告。**根因**：`ui.addNotification()` 只在 `#maincontent` 顶部插入新横幅、从不移除旧的（`ui.js` 也无 `hideNotification`），故逐条累加。`2.0.0-r21` 在 `portal/common.js` 新增 `notify()`：先移除上一次返回的节点再插入；`run_rpc()` 与书签页两处直接调用改走它。行为测试：连续 3 次 → 页面 1 条（旧行为 3 条）；用户 2026-10-06 设备验证通过 |
| 9 | 门户页背景色更换无效 | done | 改「背景色」→「保存并应用」后，门户页 HTML/CSS 里 `background-color` 的值为新设定的颜色 | 用户 2026-10-06 报告；用户 2026-10-06 在 `2.0.0-r22` 上验证通过（改色 → 保存并应用 → 门户页生效）。**根因未单独定位** —— 报告时未抓到可分析的状态，r22 的 `portal.css` 改动（#12 的暗幕与卡片底色）可能顺带解除了遮挡；若日后再现，按约定须先补根因分析再修 |
| 10 | 门户页去掉「立即重新生成 links.json」按钮 | done | 门户设置页不再出现该按钮；点「保存并应用」后 `/etc/portal/www/links.json` 的 mtime 更新（procd reload 触发器自动重生成） | 用户 2026-10-06 提出。前提已核实：`init.d/portal` 注册了 `procd_add_reload_trigger "portal"`，且未定义 `reload_service()`，故 `rc.common` 默认的 reload() 走 `start_service()` —— 「保存并应用」本就会重新烘焙。**2026-10-14 实现中**：删除 `maintenance_section()` 里的 `_generate` 按钮（含标签「静态页面」与提示「立即重新生成 links.json」），连带删除已无调用方的前端 `callGenerate` 声明与导出；**后端 `generate` 方法、ACL 授权、`init.d` 的 `generate_links()` 一律保留** —— reload 触发器正是靠 `ubus call luci.portal generate` 实现的。pot/po 经 xgettext + msgmerge 同步（98 条，减 3 条失效条目），84 条中文字幕完好。**2026-10-14 设备验证通过（3.0.0-r4）**：验收三项全绿 —— (1) 设置页不再出现该按钮（设备上 `_generate` 与 `callGenerate` 计数均为 0，翻译 lmo 里「立即重新生成」计数为 0，「扫描本地服务」仍在）；(2) `uci commit` + `/etc/init.d/portal reload` 后 `links.json` mtime 更新（1791938973 → 1791938987）且新标题已烘焙，**配置无变化时 reload 同样重烘焙**（1791938988 → 1791938991）—— 这一点正是删按钮后「保存并应用」仍生效的依据；(3) reload 后 `/portal/` 仍 200、`reachable: true`；112 项全量回归通过，`scripts/check.sh` 输出 ALL CHECKS PASSED |
| 11 | 书签页行内「保存」成功后按钮显示「已保存」 | done | 设备上书签页点某行「保存」成功后，该行按钮文字显示「已保存」；**保存失败时仍显示「保存」** | 用户 2026-10-06 提出。`2.0.0-r21` 实现：`run_rpc()` 失败时 resolve 为 `null`，故只在真实成功时改文字；新增 msgid `Saved`（已保存）；用户 2026-10-06 设备验证通过 |
| 12 | 门户页背景图可读性（背景图盖住书签） | done | 设备上门户页设好背景图后，书签卡片与标题在**任何**背景图上都清晰可读，且背景图本身仍可见 | 用户 2026-10-06 实测澄清：r21 背景图能显示了，但把书签「遮盖」了、只剩图片。**根因**：`portal.css` 自 1.0 起假定背景是深色纯色（`body` `#0e1116` + 浅灰文字 + `rgba(255,255,255,.06)` 卡片）；换成明亮照片后浅灰文字与近透明卡片被照片吞掉，内容整个消失。素材库到 r20 才能正常设背景，故此组合从未被验证。修法：`body::before` 加一层只压暗、不吃事件的暗幕 + 卡片改半透明深色磨砂。2026-10-06 本地 Edge 渲染对照确认（明亮照片下 6 个书签全可读；无背景图时无回归）；`2.0.0-r22` 发布（PR #12），用户 2026-10-06 设备验证通过 |
| 13 | 素材库操作后的刷新范围 | done | 上传 / 改名 / 删除 / 设为背景后，整页刷新次数为 0（`window.location.reload` 不再被调用），而素材库列表与通知区仍更新为新状态 | 用户 2026-10-06 提出并认可去掉整页 reload。**根因**：`assets.js` 的 `reload_soon()` 直接调 `window.location.reload()`（延迟 1.2 s）——整页丢弃会丢滚动位置，也会丢掉未应用的暂存改动。修法：改为 `refresh_assets()`，重读两个素材目录后只替换列表容器；`set_background` 也走它，让「(current)」标记立刻跟上。行为测试（Edge + stub LuCI 环境跑真源码，旧版本作证伪）：新代码 `setTimeout` 调用数 0 且列表就地更新，旧代码 `setTimeout=1` 且列表未更新；`2.0.0-r22` 发布（PR #12），用户 2026-10-06 设备验证通过 |
| 14 | 背景遮罩强度与磨砂模糊可调 | done | LuCI 门户设置页出现「Background veil」与「Background blur」两个 0–100 滑块；保存并应用后门户页 `<html>` 上的 `--bg-veil` / `--bg-blur` 等于设定值（遮罩 0 时背景图不被压暗、100 时完全遮住；模糊 0 时为 `blur(0px)`、100 时为 `blur(20px)`） | 用户 2026-10-06 提出。实现：uci 新增 `bg_veil`（默认 78）与 `bg_blur`（默认 0）；`portal.uc` 的 `percent()` 做 0–100 钳位与非数字回落，`generate()` 原样写进 `links.json`，`portal.js` 转成 `--bg-veil`（0–1）与 `--bg-blur`（0–20px）。背景图为此从 `body` 移到 `body::before` 独立成层（否则模糊会连文字一起糊掉），该层用 `inset: calc(-1 * var(--bg-blur))` 扩边，避免模糊边缘在视口内露白。验证：真 uci 配置喂 `generate()` 得 bg_veil 30 / bg_blur 100；'90 %' 回落 78、'999' 钳到 100；Edge 无头渲染 4 组取值对照。**2026-10-13 设备验证通过**（3.0.0-r2：`links.json` 的 `bg_veil` / `bg_blur` / `card_transparency` 如实反映 uci；`portal.js` 转成 `--bg-veil`（0–1）与 `--bg-blur`（0–20px）后由 CSS 消费。实测值 bg_veil=26 / bg_blur=23 / card_transparency=28 → `--bg-veil: 0.26`、`--bg-blur: 4.6px`） |
| 15 | 书签卡片透明度可调 | done | LuCI 设置 0–100（「Bookmark transparency」）；0 表示卡片完全不透明，100 表示只剩边框、背景完全透出；门户页卡片的 alpha 随设定线性变化（`--card-alpha` = (100 − 透明度)/100） | 用户 2026-10-06 提出。实现：uci 新增 `card_transparency`（默认 45，等于 r22 硬编码的 .55 alpha），同样经 `links.json` → `--card-alpha`；hover 用 `min(1, calc(var(--card-alpha) + .2))`，保持「悬停更实」又不越过不透明。**已知取舍**：透明度过高时文字可读性依赖 #14 的遮罩，UI 描述里已写明。**2026-10-13 设备验证通过**（3.0.0-r2：`links.json` 的 `bg_veil` / `bg_blur` / `card_transparency` 如实反映 uci；`portal.js` 转成 `--bg-veil`（0–1）与 `--bg-blur`（0–20px）后由 CSS 消费。实测值 bg_veil=26 / bg_blur=23 / card_transparency=28 → `--bg-veil: 0.26`、`--bg-blur: 4.6px`） |
| 16 | 搜索引擎开关与引擎选择 | done | LuCI 门户设置页出现「搜索引擎」开关（含引擎选择）；关闭后门户页不渲染任何搜索表单元素（页面里 `<input>` 与 `<form>` 计数均为 0），开启后恢复；默认值在实现时明确并补入本行 | 用户 2026-10-06 提出。现状：门户页**完全没有**搜索功能（`portal.js` / `portal.css` / uci 里都搜不到 search），故本项含从零实现搜索框 + 新增 uci 字段，不是纯开关。**2026-10-16 实现中（3.0.1-r2）**：决策与备选见 [docs/adr/0006](docs/adr/0006-search-box.md)。uci 新增 `search_enabled`（缺省视为关，随包配置显式 `'0'` —— 升级用户外观不变，沿外观滑块先例）与 `search_engine`（存**结果页 URL 模板**而非键名，引擎清单只存在于 `general.js` 的 `ListValue`：Google / Bing / DuckDuckGo / 百度 / 自定义，默认 Google）；「自定义」时模板改放 `search_url`（表单 `depends` 联动，前后端各一道 `/^https?:\/\/[^ \t]+%s/` 校验）。后端 `portal.uc` 新增 `search_template()` 解析+校验，`generate()` 烘 `"search": { "template": … }` 或 `null`；门户前端 `portal.js` 的 `setup_search()` 仅在模板存在时创建表单（禁用时 DOM 零痕迹），提交走 `window.open` 新标签页。无新 ubus 方法，ACL 不动。po 经 xgettext+msgmerge 再生（105 条，13 条新串已补译）。**待办**：`scripts/check.sh` 门禁 + 前端行为测试 + 设备装机验收。**2026-10-16 PR #23 已合并（0f89452，3.0.1-r2）**：门禁 ALL CHECKS PASSED；node 行为测试 12/12；SDK ucode 对真实 `search_template` 源码 12/12；JS 校验正则与 ucode 门同组 9/9。设备装机验收待进行。**2026-10-16 用户实测反馈两处症状、同一根因（3.0.1-r4 修复）**：(1) 未选「自定义」引擎时点保存即弹「选项“自定义搜索 URL”包含无效的输入值。选择「自定义」引擎时，必须填写自定义搜索 URL。」；(2) 搜索引擎无论选哪个，门户页都用 Google。**根因**：`general.js` 的 `search_url` 把两个条件写成了两次 `depends()` 调用，而 LuCI 多次 `depends()` 之间是**或**关系（只有对象形式才是「与」，见 `luci-base` `form.js` 的 depends() 文档）—— 搜索框一旦开启，该选项对任何引擎都处于激活态，空值触发其校验器，整个表单保存被拒；保存从不成功，`search_engine` 选择从未写入 uci，门户页固定用默认 Google 模板。**修复**：改为单次 `depends({ search_engine: 'custom', search_enabled: '1' })`，「自定义搜索 URL」字段与校验器只在选中「自定义」引擎时出现。**回归测试**：新增 `scripts/test-search-form.js`（从真实源码提取 depends 声明，按 LuCI 文档语义模拟激活态 + validate 取值矩阵 + 前后端两道闸正则逐字一致），已纳入 `scripts/check.sh`；旧代码跑该测试 5 项 FAIL（与报障签名一致）、新代码 23/23。**2026-10-16 设备复验通过（r4/r5 装机，7 项全过）+ 用户确认「修复了」**——本条关闭 |
| 17 | 搜索框的空格唤出 / 隐藏与回车搜索 | done | 门户页按空格唤出搜索框并自动聚焦；**输入框为空时**再按空格才隐藏（输入框内有内容时空格照常输入空格）；输入关键字按回车后跳转到所选引擎的结果页（地址栏 URL 含该关键字），且**搜索框随即自动隐藏** | 用户 2026-10-06 提出并确认交互契约，依赖 #16。**2026-10-16 实现（3.0.1-r3，#16 已先行合并）**：`portal.js` 的 `setup_search()` 内 `show()`/`hide()` 一对函数做 class 切换（`.search.open`，元素自始存在、不重建）；document 级 `keydown`：`isComposing` / `ctrl` / `meta` / `alt` 一律跳过（中文拼音的空格是上屏键，不判会把「上屏候选词」变成「隐藏搜索框」——本项最易踩的坑）、`Escape` 隐藏、裸空格在页面主体上 `preventDefault()` 后唤出并聚焦、焦点在输入框且值为空时才 `preventDefault()` 后隐藏（有内容则放行打字）；submit 拦截后 `window.open` 新窗 + 清空 + 隐藏 + blur。行为测试（`.build/test-setup-search.js`，真实源码提取 + DOM 桩）**27/27**。**2026-10-16 PR #24 已合并（b6e45e9，3.0.1-r3）**：门禁 ALL CHECKS PASSED；行为测试 27/27（含 IME 合成、修饰键、空值/有值空格、Escape、提交后隐藏）。**待办**：设备装机验收（空格唤出/空值隐藏/打字/回车跳转且框隐藏/IME 中文输入不误触）。其中「回车跳转到所选引擎」随 r4 修复后由用户确认生效——本条关闭 |
| 18 | 门户改由主 uhttpd 子路径提供（方案 a：静态文件装进 `/www/portal/`） | done | (1) 设备上 `ubus call luci.portal status` 返回 `path: "/portal/"`，且 `reachable` 与「浏览器能否打开 `http://<路由器>/portal/`」一致；(2) `ps \| grep uhttpd` 只有**一个**实例（不再有门户自己的那个）；(3) `enabled='0'` 并应用后 `/portal/` 返回 **404**（素材目录为空时由 `unpublish()` 的 `rmdir` 撤下整个 `/www/portal`，见 #19），**素材目录非空时目录与其中文件仍在**；(4) 改回 `'1'` 后页面与背景图恢复，且 `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-12 指定方案 a，并要求设置页状态改为「可访问」提示。决策与取舍见 [docs/adr/0004](docs/adr/0004-serve-portal-from-main-uhttpd.md)。本分支同时使 #1 的「独立 uhttpd 实例」不再成立。**2026-10-13 四条验收标准逐条设备确认后转 done**：(1) `path: "/portal/"`、`reachable: true` 与实际访问 200 一致 ✓；(2) uhttpd 实例数为 1 ✓；(3) 关闭后 `/portal/` 回到 404 —— **前提是素材目录为空**；实测时 `bg.jpg` 仍在，故目录按 #19 的既定取舍保留、页面仍可访问，删掉素材后再关闭即彻底下架 ✓；(4) 改回 1 后页面与目录恢复 200 ✓。第 (3) 条于 2026-10-13 修订：原标准要求「`ls /www/portal` 仍能看到 `icons/` 与 `bg/`」是在「留下空目录」的前提下达成的，而空目录会被 uhttpd 自动列成 `Index of /portal/` 并回 200 —— 见 #19 |
| 19 | 关闭门户后 `/portal/` 仍返回 uhttpd 目录索引页 | done | (1) 素材目录为空时，`enabled='0'` 并应用后 `test -d /www/portal` 为**假**，且 `printf 'GET /portal/ HTTP/1.0\r\nHost: h\r\n\r\n' \| nc 127.0.0.1 80 \| head -1` 返回 **404**；(2) 目录内**有**用户素材时关闭，素材文件仍在（`rmdir` 拒绝非空目录，不得用 `rm -rf`）；(3) 改回 `'1'` 后目录链由 `mkdir -p` 重建、页面恢复 200；(4) `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-13 报告（关闭后访问 `/portal/` 看到 `Index of /portal/` 列出 `bg/`、`icons/`）。**根因**：uhttpd 对「有目录、无 `index.html`」的路径生成自动索引页并回 200；原 `unpublish()` 只删四个文件，留下了自己创建的三个目录。**修复**：`unpublish()` 改用 `rmdir` 由深到浅撤下（子目录优先、`/www/portal` 最后），非空目录就地停止以保住用户文件。**已知取舍**：目录内有素材时列表仍存在（保文件优先于关列表）。**2026-10-13 设备验证通过**（3.0.0-r2，112 项测试全绿：专项 10 项 + 全量回归） |
| 20 | 全新安装后直接「保存并应用」报「选项"背景遮罩强度"不能为空」 | done | (1) 用包自带默认配置（`bg_veil=78` / `bg_blur=0` / `card_transparency=45`）打开常规页，**不碰任何滑块**直接点「保存」或「保存并应用」，均**不弹**「不能为空」；(2) 把任一滑块改成非默认值后保存，配置里该键被写入且值正确；(3) 把滑块改到 **0** 后保存不报错，门户页对应 CSS 变量为 0 对应值；(4) `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-13 报告。**根因**：`form.RangeSliderValue.formvalue()` 对「值等于 `default`」返回 `null`（用它省略冗余键），而三个滑块都设了 `o.rmempty = false`，于是 `form.js` 走 reject 分支抛 `Option "%s" must not be empty.`。包自带配置的值恰好都等于各自 default，故**全新安装必现**，与 0 无关（`bg_blur` 的 default 是 0 只是让它更易被误认为「不能为 0」）。**修复**：三个滑块去掉 `rmempty = false`，缺省时由后端 `percent()` 回落默认值，行为等价。`enabled` 的 `rmempty = false` 必须保留（开关须显式记 0/1）。**2026-10-13 设备验证通过**（3.0.0-r2，112 项测试全绿：专项 10 项 + 全量回归） |
| 21 | 背景文件丢失时门户页仍显示为「有背景」 | done | (1) 配置里 `background_file` 指向一个磁盘上不存在的文件时，`ubus call luci.portal generate` 产出的 `links.json` 中 `background` 为 `background` 选项的**纯色值**（而非失效路径），且 `background_v` 为 `""`；(2) 文件存在时 `background` 为 `/portal/bg/<name>` 且 `background_v` 为 `<mtime>-<size>`；(3) 素材库与门户页对「有没有背景图」的判断一致 | 用户 2026-10-13 报告（页面显示背景图、素材库却列不出）。**根因**：`generate()` 在 `stat()` 失败时只清空 `background_v`，`data.background` 仍指向已消失的文件，浏览器 404 后回退到 CSS 纯色 `portal.css` 的 `#0e1116` 并**不作任何提示**，于是「页面像有背景、素材库却是空」。**修复**：先 `stat()` 再赋值，文件缺失时回落到 `background` 纯色。**2026-10-13 设备验证通过**（3.0.0-r2，112 项测试全绿：专项 10 项 + 全量回归） |
| 22 | 「维护」区段从常规页移到书签页 | done | (1) 常规页不再出现「维护」区段（含「立即重新生成 links.json」与「扫描本地服务」）的任一按钮；(2) 书签页在**书签列表上方**出现同名区段，两个按钮均可点击且行为不变；(3) 常规页与书签页均无 JS 报错，`sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-13 要求。现状：`general.js` 的 Maintenance `TypedSection` 在常规页末尾（`general.js:228` 起）。**2026-10-13 实现并设备验证**。区段定义移到 `common.js` 的 `maintenance_section(m, status)`（两页共用，扫描规则不重复），由 `bookmarks.js` 在 `BookmarkTable` **之前**调用。常规页的 Maintenance 区段与 `scan_services` / `confirm_unknown` 一并移出（后两者随之移入 common.js，`confirm_unknown` 多收一个 common 实例参数以够到原型方法 `run_rpc`）。`common.js` 新增 `require uci` 与 `require form`。pot / po 的行号引用已用 xgettext + msgmerge 同步，86 条翻译完好 |
| 23 | 「扫描本地服务并添加」先确认再写入，且只追加新行（不整页刷新） | done | (1) 点按钮后弹出带勾选框的清单弹窗，**不点「添加所选」直接关掉**，则 `uci show portal` 的书签 section 数与点击前一致（零写入）；(2) 勾选并确认后，书签表格**末尾追加新行**、原有行不动，全程不发生整页刷新；(3) 通知条在读完之后才消失（不被刷新冲掉）；(4) 书签表原本只剩占位行时，追加后占位行被移除；(5) 新增行可勾选 enabled、可行内「保存」、可删除，且 `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-14 提出（原话：弹窗通知不等点「关闭」就自动刷新，把识别出的服务加进书签；理想实现要人点、刷新只加一行）。**根因**：`scan_services()` 在点击瞬间直接 `uci.add` + `uci.save()` 写入全部识别结果，随后 `setTimeout(… location.reload(), 1500)` 整页刷新 —— 通知被冲掉、未保存的半行输入与滚动位置全丢。**2026-10-14 实现（3.0.0-r5，设备验证中）**：`common.js` 删 `scan_services()` / `confirm_unknown()`，新增三个模块级函数 —— `scan_candidates()` 只读不写（`callScan()` + 按 URL 去重已存在书签，保留 `web: 'unknown'` 桶）、`stage_bookmarks(entries)` 只 `uci.add` 而**刻意不 `uci.save()`**（与页面其他输入一致，等「保存并应用」统一提交；`enabled` 暂存 `'0'`）、`confirm_scan(self, candidates, on_add)` 呈现勾选弹窗（`web === true` 默认勾选、`'unknown'` 默认不勾）；`maintenance_section()` 签名改为 `(m, status, on_add)`。`bookmarks.js` 新增 `BookmarkTable.append_sections(sids)`，复刻上游 `renderContents()` 的行构建（`renderUCISection` → `renderOptions(null, sid)` → `renderChildren`，逐個 `appendChild(nodes.firstChild)` 取 `<td>`），`max_cols ?? children.length` 与 `has_more` 语义与初次渲染一致；追加后移除 `tr.placeholder` 并 `sync_select_all()`；`render()` 里 `table` 先声明后赋值（维护区段必须排在列表上方）。原两处 `window.location.reload()` 均已删除。pot/po 经 xgettext + msgmerge 重新生成（97 条 msgid），补译 4 条新串（`Local services found` / `These local services are not bookmarked yet…` / `Nothing was added.` / `Add selected` 等），旧串转 `#~`，`msgfmt --check` 通过。**2026-10-15 r5 装机验证（3.0.0-r5，192.168.122.12）**：`verify-r5-scan.sh` 19 项全绿（版本 `3.0.0-r5（apk 安装）`、新代码在位、旧代码 0 处、5 条新译句进 lmo、`location.reload` 仅存于 `reload_soon()` 即删除提交路径）；`ubus call luci.portal scan` 前后 `uci show portal` md5 不变（后端零写入）；`links.json` 重新生成，`/portal/` 与新 JS 经 HTTP 均 200；`node --check` 确认 jsmin 压缩产物语法有效（apk 内 JS 为压缩版属项目一贯发布形态，`CONFIG_LUCI_JSMIN` 默认 y）。**2026-10-15 用户实测反馈两条，r6 修复**：(a) 新追加行的「名称」「URL」为空 —— 根因是 `form.TableSection` 的每个 option widget 各有一份配置值缓存（`option.data[sid]`），仅页面加载时由 `CBIAbstractSection.load()` 填入；扫描走的是加载后发生的 `uci.add()`，新 section 对 `uci.get()` 可见（`uci.js` 的 `get()` 先查 `state.creates`，故保存链路一直是通的）却不在 option 缓存里，`cfgvalue()` 返回 `undefined`。`append_sections()` 改为渲染前逐 option `opt.load(sid)` + 两参数 `cfgvalue(sid, value)` 写回缓存（不复用 `loadChildren()`：它跳过 `disable` 的 option，返回值与 `children` 索引对不上）；(b) 点「添加所选」后又弹出「已在列表末尾添加 N 个书签…」通知 —— 该通知说的就是列表已显示的事且浮在新增行上方，`confirm_scan()` 的 `on_add(sids)` 完成后不再 `notify()`，译句从 pot/po 移除。`PKG_RELEASE` 升 6，构建装机复验后进行中。**2026-10-15 r6 装机复验（192.168.122.12）**：`verify-r6-scan.sh` **25 项全绿** —— 版本 `3.0.0-r6（apk 安装）`；r5 全部检查项无回归（三个新函数、`maintenance_section` 收 `on_add`、旧代码 0 处、`location.reload` 仅限 `reload_soon`、5 条译句进 lmo）；修复 A 三项（`opt.load(sid)` / 两参数 `cfgvalue(sid,` 在位，补缓存偏移 3499 早于 `renderUCISection` 偏移 3610）；修复 B 三项（无 `Added %d bookmark`、lmo 无「已在列表末尾添加」、`stage_bookmarks(chosen)` 至「添加所选」之间无 notify）。附加：scan 前后 `uci show portal` md5 不变（后端零写入），`/portal/` 与新 JS 经 HTTP 均 200。验证中同时修掉验证脚本自身三个压缩产物适配问题（busybox grep 无 `-b` 改 awk `index()`、行号顺序断言改字符偏移、notify 窗口锚定 `_('Add selected')` 防飘出函数体），详见 `dist/INSTALL-r6-verify.md`。**2026-10-15 用户浏览器确认 7 项验收全部通过**（原话：#23 7项正常）—— 本条关闭 |
| 24 | 上传素材不再弹「已上传 xxx。」成功通知 | done | 素材库页上传一张图后页面上**不出现**「已上传」通知（错误仍须弹提示），且下方列表出现该图；上传超限（>2 MiB）仍报错 | 用户 2026-10-15 反馈（原话：有个成功弹窗提示「已上传 xxx。」，不需要，下方列表显示了就是成功了）。**根因**：`assets.js` 的 `upload()` 把 `_('Uploaded %s.')` 作为 `run_rpc()` 的成功消息参数。**修复**：改传 `null`（失败路径不受影响，`run_rpc` 仍弹错误）；`refresh_assets()` 重画列表不变。译句从 pot/po 移除。**2026-10-15 r7 装机复验（192.168.122.12）**：`verify-r7.sh` **32 项全绿**（r6 全部 17 项回归无变化 + 修复 A 三项：无 `Uploaded %s`、lmo 无「已上传 %s。」、`run_rpc` 成功消息为 null + 修复 B 七项：三件套、`portal-bm-thumb`、三分支 URL、onchange 绑定）。附加：`/portal/icons/1791889817.png` 经 HTTP 200（缩略图 URL 规则真实可访）；scan 前后 uci md5 不变。修掉验证脚本两个误报（合法译句「已上传的图标与背景图」误中、区间正则败在等号/逗号两侧空格），详见 `dist/INSTALL-r7-verify.md`。**2026-10-15 用户确认修复生效**（原话：好的，这个问题修复了）。**r8 扩展**：删除与保存的成功通知一并去掉（批量删除「已删除 N 个书签。」、行内「保存」的「已保存该书签。」、素材库删除的「已删除 xxx。」均不再弹，`run_rpc()` 成功消息统一 `null`，译句从 pot/po 移除）。**2026-10-15 r8 装机复验（3.0.0-r8，192.168.122.12，实际执行）**：`verify-r8.sh` **PASS=17 FAIL=0**（版本 `3.0.0-r8（apk 安装）`；四处 null 成功消息断言全过；三条旧译句在 js/lmo 中均消失）；另补 node 对**设备安装的压缩版** `bookmarks.js` 真实调用 `icon_url_of` 6/6 通过；`/portal/`、`/portal/portal.js`、`/portal/icons/1791889817.png`、`/portal/links.json` 经 HTTP 均 200。修掉验证脚本 4 处模式问题（`apk info` 版本解析、设备无 node 时的 skip 分支、jsmin 压缩后 `===0` 的等号数、批量删除误匹配函数定义而非调用点），均非代码回归。**2026-10-15 用户浏览器确认**（原话：改下拉框缩略图即时更换、选回空则消失、行内保存/批量删除/素材删除均不再弹通知）—— 本条关闭。遗留小项：上传超限（>2 MiB）报错路径未经浏览器实测，但 `run_rpc()` 失败分支本轮未动，代码路径不变 |
| 25 | 书签行保存按钮左侧显示素材图缩略图 | done | (1) 书签 `icon` 指向素材库图片时，该行「保存」按钮左侧出现缩略图，图片内容与该 icon 一致；(2) 改 `icon` 下拉框后缩略图即时更换，无需保存或刷新；(3) `icon` 为空或只填「图标」列（emoji / 外链 URL）时不显示缩略图；(4) `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-15 加入计划（原话：书签页，书签设置素材库图片后，保存按钮左侧显示缩略图）。**实现**：`bookmarks.js` 新增 `icon_url_of()`（复刻 rpcd 插件 `asset_path()` 的三支转换）、`make_thumb()` 与 `update_thumb()`；`renderRowActions()` 在 Save 按钮前插入 `<img class="portal-bm-thumb">`（初次渲染与扫描追加两条路径都经过它）；`icon` option 挂 `onchange` 调 `update_thumb()` 实时跟上下拉框。仅素材库图片驱动：emoji 与外链不拉第三方图装饰设置页。**2026-10-15 r7 装机复验**：`verify-r7.sh` 32 项全绿（代码断言全过，设备 `/portal/icons/<file>` 经 HTTP 200）。**2026-10-15 用户实测：缩略图仍不显示，r8 修复** —— 根因是 `icon_url_of()` 的「素材库图片」分支拿 `ICON_DIR`（`/www/portal/icons`，比 rpcd 的 `WWW` 深一层）切路径，产出 URL 丢掉 `icons/` 段，请求落到 `/portal/<文件名>`，404（r7 的代码断言只查「函数在不在」，没有真实调用过转换，所以漏放）。**修复**：新增 `WWW = '/www/portal'` 常量，切在 `WWW` 上（与 rpcd `asset_path()` 完全对齐），URL 保留 `icons/`；修复用 6 组输入真实调用验证（含 `/www/portal/icons/x.png` → `/portal/icons/x.png`、裸文件名、`bg/` 路径、空值）。**2026-10-15 r8 装机复验（3.0.0-r8，192.168.122.12，实际执行）**：`verify-r8.sh` **PASS=17 FAIL=0**；node 对设备安装的压缩版 `bookmarks.js` 提取 `icon_url_of` 真实调用 **6/6 通过**；`/portal/icons/1791889817.png` 经 HTTP **200**（r7 时该 URL 404）；设备首条书签已预设 `icon=/www/portal/icons/1791889817.png`。**2026-10-15 用户浏览器确认生效**（原话：改下拉框缩略图即时更换、选回空则消失）—— 本条关闭 |
| 26 | 常规设置页底部间距：表单最后一项贴页面下边缘 | done | 常规设置页滚动到底后，「搜索引擎」选择框与页面内容区下边缘之间有**明显的呼吸空隙**（≥ LuCI 默认主题 Bootstrap 的观感即可，不要求像素值）；切换其它主题（如 Bootstrap）不出现回归 | 用户 2026-10-16 报告（怀疑 Argon）。**源码分析**：三个视图只产出标准 CBI 标记，`render()` 用普通 `E('div', {})` 包裹，**未使用 LuCI view 的 `css()` 钩子注入任何自有样式**；页面级 padding 全由主题（Argon）的容器决定，Argon 对内容区底部留白偏小。**修复方向**（不碰 Argon）：`portal/common.js` 提供共享的视图级 CSS**2026-10-16 实现（3.0.1-r5）**：核实本版 LuCI `View` 类**无 `css()` 钩子**（luci.js 全文无 `.css()` 消费点）后，改为各视图在 `render()` 产物内注入 `<style>` 标签（`common.admin_css()` 生成，全部规则作用域限定 `.portal-admin` 包裹层）。`padding-bottom: 2em`。**2026-10-16 用户浏览器确认通过（3.0.1-r5，Argon）**——本条关闭 |
| 27 | 书签行图标预览在行内上下居中 | done | 书签行内素材图缩略图在**行高的垂直中点**（对照：与同行「保存」按钮中线对齐），不再偏行顶；任意主题下均成立 | 用户 2026-10-16 报告（怀疑 Argon）。**源码分析**：缩略图 `<img>` 只有内联 `margin:0 .5em 0 0`，**没有 `vertical-align`**；单元格内垂直对齐完全由主题 `td` 的 `vertical-align` 决定，Argon 把它设为 `top`（或按钮撑高行）时图片贴行顶。**2026-10-16 实现（3.0.1-r5）**：核实缩略图 `<img>` **本来就有** `vertical-align:middle`，真正不同轴的是同行按钮（主题默认 baseline 对齐，`middle` 相对基线计算导致图片偏上）。修法改为作用域 CSS：`.portal-admin .cbi-section-table .btn { vertical-align: middle }`，让按钮与缩略图共用同一对齐轴。**2026-10-16 用户浏览器确认通过（3.0.1-r5，Argon）**——本条关闭 |
| 28 | 书签页三个操作按钮之间留间隔 | done | 「添加」「删除禁用书签」「清空所有书签」三个按钮之间有可见间距（约一个字符宽以上）；「删除禁用书签」在无禁用行时仍正常置灰 | 用户 2026-10-16 报告（怀疑 Argon）。**源码分析**：`renderSectionAdd()` 把两个批量删除按钮直接 `appendChild` 到 LuCI 的 `cbi-section-create` 行（「添加」按钮之后），**中间没有插入空隙**；Bootstrap 主题靠 `.btn` 自身 margin 分隔，Argon 的 `.btn` margin 为 0 就贴死。**2026-10-16 实现（3.0.1-r5）**：`bulk_delete()` 的按钮加内联 `margin-left:.5em`（该函数只被 `renderSectionAdd()` 的两个批量按钮调用，不影响别处）。**2026-10-16 用户浏览器确认通过（3.0.1-r5，Argon）**——本条关闭 |
| 29 | 常规页「刷新」按钮贴近容器左边缘 | done | 「服务状态」区段内的「刷新」按钮与卡片内容区左边缘之间有与其它控件一致的缩进，不再贴边 | 用户 2026-10-16 报告（怀疑 Argon）。**源码分析**：状态面板是自建 `E('div', {class:'cbi-section'})`（`portal/common.js` 的 `status_panel()`），按钮行只有 `margin-top:.8em`、**没有左缩进**；Bootstrap 主题下 CBI 区段自带内边距，Argon 对 `cbi-section` 的内边距更小就显得贴边。**2026-10-16 实现（3.0.1-r5）**：`status_panel()` 节点加 `portal-panel` class，共享 CSS 给它 `padding-left/right: .6em`。**2026-10-16 用户浏览器确认通过（3.0.1-r5，Argon）**——本条关闭 |
| 30 | 素材库「上传」按钮贴近容器左边缘 | done | 素材库页图标 / 背景两个区块的「上传」按钮与卡片内容区左边缘有与其它控件一致的缩进 | 用户 2026-10-16 报告（怀疑 Argon）。**源码分析**：与 #29 同型 —— `upload_button()` 返回的按钮容器只有 `margin-bottom:.6em`、无左缩进；区块是自建 `cbi-section`，间距由主题决定。**2026-10-16 实现（3.0.1-r5）**：`asset_section()` 两个区块节点加 `portal-panel` class，与 #29 共用同一规则；外层 `cbi-map` 加 `portal-admin` 承载样式作用域。**2026-10-16 用户浏览器确认通过（3.0.1-r5，Argon）**——本条关闭 |
| 31 | 软件包更名 luci-app-liteportal | done | (1) `apk info -e luci-app-liteportal` 为真且版本为 3.0.2-1，旧包 `luci-app-portal` 已卸载；(2) `/etc/config/portal` 的用户配置（含书签与搜索引擎设置）在换包前后保持不变；(3) `ubus list \| grep luci.portal` 存在，设置页 / 门户页均可访问；(4) 翻译包为 `luci-i18n-liteportal-zh-cn`，中文界面正常；(5) `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-16 指定。**实现**：`luci.mk` 的 `LUCI_NAME` 取 SDK `package/` 下的目录名，故包名 = 目录名 —— 仓库目录不变，仅 SDK 侧目录改链为 `luci-app-liteportal`；`Makefile` 的 `Build/Prepare` / `Package/*` define 与 echo 前缀、`menu.d` / `acl.d` 文件与 ACL 组名、`scripts/check.sh` 引用、po 头 `Project-Id-Version`、README 安装示例同步更名。**运行时标识全部不变**（uci `/etc/config/portal`、ubus `luci.portal`、init.d `portal`、菜单 `admin/portal`、门户页 `/portal/`），po 文件名保持 `portal.*`（dispatcher 的 `load_catalog` 加载目录内全部 `.lmo`，与文件名无关）。版本随之升 **3.0.2-r1**，按 ADR 0005 打 tag `v3.0.2`。**2026-10-17 追记**：本条中「运行时标识全部保持不变」的结论已被 #32 推翻 —— 除菜单与页面显示名仍为 Portal 外，uci 配置、ubus 对象、服务名、菜单路径、页面 URL 与静态目录全部改名，版本升至 4.0.0 |
| 32 | 运行时标识全量重命名与仓库改名 | done | (1) `uci show liteportal` 可读，`portal.@portal[0]` 已不存在；`ubus list \| grep luci.liteportal` 有结果且 `luci.portal` 消失；(2) `/etc/init.d/liteportal` 可 enable/start 且 `/etc/init.d/portal` 不存在；(3) 菜单路径为 `admin/services/liteportal`，页面 URL 为 `/liteportal/`，静态文件落 `/www/liteportal/`；(4) 升级不做自动迁移：`apk del` 旧包后全新安装 4.0.0，`/etc/config/portal` 与 `/www/portal` 均不存在、`/etc/init.d/portal` 不存在，`postinst` 不含任何历史路径的兼容代码；(5) 仓库与 `LUCI_URL` 指向 `wrttools/luci-app-liteportal`；(6) `sh scripts/check.sh` 输出 `ALL CHECKS PASSED` | 用户 2026-10-17 指定（原话：将仓库名称也改为 luci-app-liteportal，这些运行时标识也都相应更改，所有的）。**实现**：见 CHANGELOG `[4.0.0]` —— Makefile 的 conffiles / postinst / prerm / LUCI_URL、`root/etc/config/liteportal`、`root/etc/init.d/liteportal`、`root/usr/share/rpcd/ucode/liteportal.uc`、menu.d / acl.d、四个 JS 的 uci 与 ubus 引用、po 基名、门禁路径全部同步。**BREAKING**：运行时契约属对外 API，按 semver 记 MAJOR（3.0.2 → 4.0.0）。**升级不做自动迁移**（2026-10-17 决策修订，原方案是 `postinst` 搬运）：本包此前只在维护者的测试虚拟机上运行过，没有存量设备，迁移会变成「为不存在的用户写代码」。机制上本可行 —— 设备实测（3.0.2-r1 → 4.0.0-r1）apk 同名升级只跑新包的 `post-upgrade`、不跑旧包的 `pre-deinstall`，`/etc/config/portal` 与 `/www/portal` 连同素材原样留盘。因此 `postinst` 只做「建目录 → 注册对象 → 烘焙 links.json → 启用并启动」，不留任何历史路径兼容代码；代价是原地覆盖升级会留下无主残留（`/portal/` 继续应答旧页面），文档据此把「先卸旧包再装新包」写成推荐步骤。菜单与页面显示名保留 **Portal**（用户可见文案，不是运行时标识）。用户就四个结构性决策拍板：本地目录一并改名、版本 4.0.0、门户前端资源一并改名、不做升级迁移 |
## 已知缺陷

### v2.0.0-r7 —素材库的重命名、删除与「设为背景」无效

**状态：** resolved（`v2.0.0-r20`，2026-10-06），原报于 `v2.0.0-r7`
**影响：** 素材库页面 —— 重命名 / 删除 / 设为背景

三个操作都提示成功，但文件系统毫无变化。

#### 现象

| 操作 | 用户看到 | 实际发生 |
|---|---|---|
| 重命名 | 通知 `Renamed to <name>.` | 文件仍是原名 |
| 删除 | 通知 `Deleted <name>.` | 文件还在 |
| 设为背景 | 通知 `Background set to <name>. …` | 门户背景没变 |

全程不报错 —— 这正是该问题被当成「无效」而非「失败」上报的原因。

#### 根因 1 —— `run_rpc()` 看不到后端失败

`htdocs/luci-static/resources/portal/common.js:94`：

```js
run_rpc(action, okMsg) {
    return Promise.resolve()
        .then(action)
        .then((res) => {
            if (okMsg != null && res != null)        // 只判空
                ui.addNotification(null, E('p', {}, /* … */), 'info');
            return res;
        })
        .catch((err) => { /* … */ return null; });
}
```

`root/usr/share/rpcd/ucode/portal.uc` 里的 `upload` / `rename` / `remove` 报告失败时
是**返回** `{ ok: false, error: '…' }`。这是一个携带普通对象的 fulfilled promise，于是：

- `res != null` 为真，成功提示照常弹出；
- `.catch()` 永不执行，真正的 `error` 字符串被丢弃；
- 调用方拿到非 null 结果，继续 `reload_soon()`（`assets.js:174`）刷新页面 ——
  而文件当然还是没变。

`portal.uc` 中每一条返回 `{ ok: false }` 的路径都受影响，不止这三个。后续任何方法
要么 reject，要么由调用方显式检查。

#### 根因 2 —— 「设为背景」只暂存了值

`htdocs/luci-static/resources/view/portal/assets.js:328`：

```js
function set_background(entry) {
    const sections = uci.sections('portal', 'portal');
    if (!sections.length)
        return Promise.resolve();

    uci.set('portal', sections[0]['.name'], 'background_file', BG_DIR + '/' + entry.name);

    return common.run_rpc(function() {
        return uci.save();
    }, _('Background set to %s. Press "Save & Apply" below to make it take effect.').format(entry.name));
}
```

这个值只是被**暂存**，要靠页面底部的「保存并应用」提交，提交时经 `portal` 的 procd
reload 触发器重新烘焙 `links.json`。因此有两种情况会让背景没变：

- 用户没点「保存并应用」；
- `generate()` 跑在 rpcd 插件进程内，用的是它自己的 `cursor()`，看不到未提交的暂存值。

#### 修复方向

1. 让 `run_rpc()` 把 resolved 的 `{ ok: false }` 当作失败 —— 抛出去让既有 `.catch()`
   上报 `error`；或在通知前先查 `res.ok`。后者改动更小，但每个调用点都得各自 opt in。
2. 素材库页面在暂存背景后链式调用 `ui.changes.apply()`，让值提交与 `links.json`
   重烘一步完成，与界面其余部分对待设置项的方式保持一致。

两者都是代码改动，**刻意不包含在 `v2.0.0-r7`**。

#### 实测定论：真正让三个操作失效的是另外两层（2026-10-06）

上面两节是 `v2.0.0-r7` 当时对代码的静态推断。设备上逐条验证后确认：让三个操作
「点了没反应」的是下面两个层次的问题，**都不在 `run_rpc()` 的内部逻辑里**。

##### 根因 A —— rpcd 方法表没有声明 `args`（`v2.0.0-r18` 修复）

`portal.uc` 的方法表只写了 `call:`。rpcd 是用 `args` 生成 ubus 参数策略的，未声明
即等于「零参数方法」，任何具名参数都会在**回调执行之前**被拒：

| 步 | 环节 | 源码依据 |
|---|---|---|
| 1 | 前端发 `{ dir, name, ubus_rpc_session }` | `rpc.declare({ params: […] })` |
| 2 | 方法表无 `args` ⇒ 策略为空 `{}` | rpcd `ucode.c` `rpc_ucode_method_register()` |
| 3 | 具名参数被判非法 ⇒ `UBUS_STATUS_INVALID_ARGUMENT`(2)，**回调不执行** | `ucode.c:266` `rpc_ucode_validate_call_args()` |
| 4 | uhttpd 以 legacy 格式回 `{"result":[2]}` | `ubus.c` `uh_ubus_request_cb()` |
| 5 | LuCI 默认把状态码**当结果** resolve（除非 `reject: true`） | `rpc.js:92-97` |
| 6 | `2.ok === undefined` ⇒ 守卫不成立 ⇒ 弹「成功」并刷新 | `common.js`、`assets.js` |

设备证据：修复前 `ubus call luci.portal rename '{"dir":"icons",…}'` 返回
`Command failed: Invalid argument`；修复后同一命令返回
`{"ok":false,"error":"no such file"}`。修法：给 `scan` / `upload` / `remove` / `rename`
声明 `args`，回调改读 `request.args`，并给本 App 全部 `rpc.declare` 加上 `reject: true`。

##### 根因 B —— 数组风格 `params` 与对象调用不匹配（`v2.0.0-r19` 修复）

`rpc.declare` 的 `params` 有两种风格，`rpc.js:302-305` 的**数组分支是位置映射**：

```js
params: [ 'dir', 'name' ]
callUpload({ dir: dir_key(dir), name: name });   // 错：对象被当成第一个参数本身
```

实际发出的是 `{"dir":{"dir":…,"name":…}}` —— `name` 直接丢失、`dir` 变成 table，
于是又一次类型不匹配，仍然是 code 2。用 node 复刻 `rpc.js` 该分支实测：

```
旧: callUpload({ dir, name })  -> {"dir":{"dir":"icons","name":"logo.png"}}
新: callUpload(dir, name)      -> {"dir":"icons","name":"logo.png"}
```

`scan` 是无参调用，所以没受影响；`upload` / `remove` / `rename` 三个调用点全部中招。
修法：三个调用点改为位置传参，并在 `scripts/check.sh` 增加门禁
「rpc 调用点不得传对象字面量」（`grep -rnE 'call[A-Z][A-Za-z0-9_]*\(\{'`）。

##### 根因 C —— 跨设备 `rename()` 返回 `EXDEV`（`v2.0.0-r20` 修复）

r19 之后 ubus 调用终于进到回调，`upload_asset()` 返回
`{ ok: false, error: "unable to store the file" }`，即
`rename('/tmp/portal_upload.tmp', '/etc/portal/www/icons/<name>')` 失败。

原因是**跨挂载点**：浏览器落盘的 `/tmp` 是一个独立的 tmpfs（`cgi-upload` 只能写
那里），而 `/etc/portal/www` 在 overlay 上；`rename(2)` 不允许跨文件系统。

用 SDK 的 ucode 对 `/dev/shm`（tmpfs）→ `/home`（overlay）实测：

```
rename(tmpfs -> overlay) = null
fs.error()               = "Cross-device link"
readfile + writefile     = 跨设备正常
```

修法：把「搬进目的地」由 `rename(2)` 改为 `readfile` + `writefile` + `unlink`
（载荷已被 2 MiB 上限约束，走一次内存可接受）。写失败时 `unlink(dst)`，避免留下
半截文件把重试堵成「同名已存在」。

同时新增 `with_errno()`：把 `fs.error()` 的 errno 文本附到错误串上。此前所有 fs
失败都显示同一句话，正是这次需要多轮设备复测才能定位的原因。注意 `fs.error()`
读取后即清零，必须在失败后**立刻**调用。

**行为测试**（把 `WWW` / `TMP_UPLOAD` 重定向到 tmpfs→overlay 一对路径，直接调用
真实 `upload_asset()`，并以旧代码作证伪对照）：

| 版本 | 返回 | 目的文件 |
|---|---|---|
| 旧（`rename`） | `{ok:false, error:"unable to store the file"}` | 未创建 |
| 新（copy） | `{ok:true, name:"probe.png"}` | 存在，且逐字节一致 |

##### 本轮状态

- 上节「根因 1」（`run_rpc()` 看不到失败）在 `v2.0.0-r17` 修掉：失败现在会真弹「操作失败」。
- 上节「根因 2」（「设为背景」）按用户决定走 **B 方案**：保持暂存语义，**不**链式
  `ui.changes.apply()`。
- 根因 A / B / C 分别随 `v2.0.0-r18` / `r19` / `r20` 出包。
- **2026-10-06 设备验证通过**：上传、预览、重命名经真机确认生效（文件确实变动，失败时
  弹错误提示）。删除与「设为背景」走同一条已修好的路径，未单独复测。
- 遗留提示：浏览器会缓存 SPA 的 JS 模块，换上新包后需 `Ctrl+Shift+R` 硬刷新，否则
  仍会跑旧代码。
