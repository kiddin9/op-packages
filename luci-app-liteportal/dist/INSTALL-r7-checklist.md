# luci-app-portal 2.0.0-r7 装机实测清单

本轮只修**一个**根因导致的三个现象。r6 的功能特性（上传/重命名/删除、设为背景暂存、
背景版本戳、扫描三层过滤、书签全选）**全部保留，未回退**。

```
dist/luci-app-portal-2.0.0-r7.apk              18453 bytes
  sha256 dfeccdbf66c691e79531bcb51c36105dcf6a69eba90e33565fa1852c6aa8272a
dist/luci-i18n-portal-zh-cn-2.0.0.apk           3207 bytes
  sha256 906e7c03ab41ebb7099f50211292ca31f9562a75a52cbf97d7ed8240de385286
```

> i18n 包每次重建内容都会变（lmo 内嵌时间戳），部署前以现场 `sha256sum *.apk` 为准。

## 0. 装前必读：一定要硬刷新

r6 装过之后，浏览器已经缓存了旧的 `assets.js`。**直接点菜单可能仍在跑有 bug 的旧代码**，
会让你误判「修复没生效」。

```
Ctrl+Shift+R   （或 Ctrl+F5）
```

装完包在设备上也可以直接确认包内是否是新代码：

```sh
grep -c "url +=" /www/luci-static/resources/view/portal/assets.js   # 应为 0
grep -c "render_safe" /www/luci-static/resources/portal/common.js  # 应为 1
```

## 1. 装前的已知状态

- r3：`luci.portal` 从未注册过 → 状态面板与两个维护按钮全死。
- r4：后端修好，但三个页面因 `factory yields invalid constructor` 全部打不开。
- r5：页面能打开，但素材库有 7 个体验问题。
- r6：7 个问题都修了，但**素材库页一点就崩**（本轮修的就是这个）。
- r7：应全部修好。

## 2. r7 修了什么

**根因**：`assets.js` 的 `portal_url()` 里 `const url = ...` 之后又 `url += '?v=' + ...`。
对 `const` 重新赋值抛 `TypeError`。缩略图和文字链接两条路径都传了 `entry`，所以这个
`+=` 分支**每次都走** —— 素材库页只要有一个文件就必崩。

三个现象同源：

| 现象 | 机制 |
|---|---|
| 素材库页 TypeError | `portal_url()` 抛错 |
| 进度条期间点其他菜单无反应 | footstrap 主题的 SPA 路由器把导航**串行化**，抛错的页永远不「painted」，后续导航全部排队，直到 15 秒超时 |
| 点素材库后地址栏跑到 bookmarks | 排队期间点「书签」时地址栏先变了，但页面没换。**不是独立 bug**，阻塞解除后自然对齐 |

| # | 做法 |
|---|---|
| 1 | `portal_url()` 改为单次表达式返回，不引入 `let`，从写法上消除这类缺陷 |
| 2 | 缩略图逐项 `try/catch` 隔离，单个坏文件只降级为文字链接，不再整页白屏 |
| 3 | `common.js` 新增 `render_safe()`，接住同步抛出与 Promise reject，返回可见错误块。三个视图的 `render()` 全部套上 —— 视图正常 painted，串行队列立即释放 |
| 4 | `bookmarks.js` 补上缺失的 `require portal.common` |

**没有改动**：后端 `portal.uc`、`portal.js`、ACL、`menu.d`、`init.d`。
**没有改动**：`luci-theme-footstrap` —— 那是第三方主题，不进本仓库。

## 3. 安装

```sh
apk add --allow-untrusted /tmp/luci-app-portal-2.0.0-r7.apk
```

postinst 会自动建目录、`rpcd reload`、`ubus call luci.portal generate`，**不需要手动重启**。

装完先确认后端注册了：

```sh
ubus list | grep luci.portal        # 应看到 luci.portal
ubus call luci.portal status        # 应返回 ok:true
```

若 `luci.portal` 不在列表里：`/etc/init.d/rpcd restart`。

## 4. 本轮核心验证（务必逐条看）

### 4.1 素材库不再崩溃 ← **本轮重点**

- [ ] 浏览器 **Ctrl+Shift+R** 硬刷新后再点「素材库」
- [ ] 页面**正常渲染**，缩略图可见
- [ ] Console **无** `TypeError: invalid assignment to const 'url'`
- [ ] 地址栏停在 `.../portal/assets`，**没有**跑到 `.../bookmarks`

### 4.2 导航不再被卡 ← **本轮重点**

进度条走动的**瞬间**点另一个菜单（如「常规」或「书签」）：

- [ ] 进度条**立即**结束，页面立刻切换
- [ ] **不再等 15 秒**
- [ ] 地址栏与实际显示的页面对得上

> 这条依赖你的主题是 `luci-theme-footstrap`。若你用的是 bootstrap / argon，
> 现象本来就不出现，勾「不适用」即可。

### 4.3 错误兜底确实生效（可选验证）

如果你想确认第 3 条修复不是摆设，可以在设备上临时改坏一行制造异常：

```sh
# 备份
cp /www/luci-static/resources/view/portal/assets.js /tmp/assets.js.bak
# 故意在 portal_url 里插一行会抛错的代码，例如在 return 之前加：
#     throw new Error('deliberate');
```

- [ ] 页面显示**错误块**（而不是整页白屏）
- [ ] 进度条**立即**结束
- [ ] 立刻点其他菜单能正常跳转

```sh
# 验证完还原
cp /tmp/assets.js.bak /www/luci-static/resources/view/portal/assets.js
```

## 5. r6 的功能回归（确认没被改坏）

### 5.1 上传与大小限制
- [ ] 选 **< 2 MiB** 的图 → 提示成功，列表出现，缩略图可见
- [ ] 选 **> 2 MiB** 的图 → 提示「图片超过 2 MiB（x.x MiB）。」，**不发起上传**
- [ ] 对 **> 256 KiB** 的图，缩略图**直接可见**（r5 失败处）

### 5.2 重命名
- [ ] 点「重命名」→ 改名 → 确认，文件与列表同步更新
- [ ] 对 **> 256 KiB** 的图标重命名 → **成功**（验证绕过 rpcd 的 256 KiB 上限）
- [ ] 改成非法名（含空格或中文）→ 提示「文件名不合法。」且不生效

### 5.3 删除
- [ ] 删一个正被书签引用的图标 → 提示成功，
      **打开 `/etc/config/portal` 确认 `link.icon` 那一行已消失**
- [ ] 删当前背景图 → `background_file` 被清掉，门户页回落到背景色

> 这一条务必看文件而不只看 UI。rpcd 插件里 `uci.save()` 是空操作，必须 `uci.commit()`。

### 5.4 设为背景（暂存语义）
- [ ] 点「设为背景」→ 提示「背景已设为 xxx，按下方保存并应用后生效」
- [ ] 此时直接开门户页，背景应当**还是旧的**
- [ ] 按「保存并应用」→ 门户页背景变新
- [ ] 在门户页按 **F5** → 仍是新图

### 5.5 扫描
- [ ] 常规页点「扫描本地服务并添加（禁用）」
- [ ] 弹窗列出未识别端口（1053、7890 之类）→ 点「忽略」或「添加为禁用书签」
- [ ] 书签页里**不应出现** ssh / DNS / mdns / wireguard 的条目

```sh
ubus call luci.portal scan
# 非 Web 端口    -> "web": false
# 已知 Web 端口  -> "web": true
# 未知端口        -> "web": "unknown"
```

### 5.6 书签页全选
- [ ] 点「全选」→ 所有行的「已启用」复选框**同时勾上**
- [ ] 按「保存并应用」→ `ubus call luci.portal status` 的 `links` 数量与勾选数一致

### 5.7 常规页状态面板
- [ ] 「保存并应用」后「进程存活」「端口已监听」都为绿
- [ ] 关掉「启用门户」→ 保存并应用 → 面板显示「已禁用」，
      `ubus call luci.portal status` 返回 `enabled:false`

## 6. 出问题时的排查

```sh
# 后端是否注册
ubus list | grep luci.portal

# 包内代码是否真的是 r7
grep -c "url +=" /www/luci-static/resources/view/portal/assets.js   # 0 = 新代码
grep -c render_safe /www/luci-static/resources/portal/common.js     # 1 = 新代码

# 手动生成
ubus call luci.portal generate
```

| 现象 | 排查方向 |
|---|---|
| 还报 `const 'url'` | ① 没硬刷新；② 上面的 `grep -c "url +="` 不是 0（装错包了） |
| 还报 `factory yields invalid constructor` | 模块缓存：`rm -f /tmp/luci-indexcache.*.json /tmp/luci-modulecache/*` 后重登 |
| 素材操作报 PermissionError | ACL 没生效：`/etc/init.d/rpcd restart` 后**重新登录** |
| 缩略图显示为「打开」文字链接 | LuCI 走 HTTPS，浏览器拦截门户的 HTTP 图片（混合内容）。已知限制，不是 bug |
| 进度条仍卡 15 秒 | 确认主题：`uci get luci.main.mediaurlbase` 无关，看 LuCI 界面主题是否为 footstrap |

## 7. 回滚

```sh
apk del luci-app-portal
```

`/etc/config/portal` 是 conffile，按包管理器规则保留；`/etc/portal` 会被清理。
