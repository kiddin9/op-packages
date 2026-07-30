![GitHub License](https://img.shields.io/github/license/itv3/homeproxy?style=for-the-badge&logo=github)
![GitHub Release](https://img.shields.io/github/v/release/itv3/homeproxy?style=for-the-badge&logo=github)
![GitHub Downloads](https://img.shields.io/github/downloads/itv3/homeproxy/total?style=for-the-badge&logo=github)

# HomeProxy Custom

这是基于 [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) 的个人自定义版本。

当前维护分支：[`master`](https://github.com/itv3/homeproxy/tree/master)

适用环境：

- ImmortalWrt / OpenWrt 使用 `apk` 包管理器的版本
- 已启用 firewall4
- 已安装或可从系统源安装 `sing-box`

已在以下环境验证：

- ImmortalWrt 25.12.0
- sing-box 1.12.25
- apk-tools 3.0.5

## 与上游的关系

上游原版仓库：

<https://github.com/immortalwrt/homeproxy>

本仓库只维护个人使用所需的增强功能，尽量跟随上游代码。上游 HomeProxy 更新后，需要把上游变更合并到本分支，再重新构建自定义 APK。

## 优化内容

1. 支持 SS2022 + ShadowTLS 类型节点

   - Shadowsocks 节点页面增加 `启用 ShadowTLS`。
   - 勾选后显示 ShadowTLS 地址、端口、密码、伪装 SNI、版本。
   - 生成 sing-box 配置时使用 Shadowsocks outbound + ShadowTLS detour。

2. 添加 Selector 类型路由节点

   - 路由节点类型新增 `Selector`：可包含具体代理节点、已有路由节点。
   - `Selector` / `URLTest` 路由节点支持“节点正则”，可按代理节点标签自动筛选节点，并与手选节点合并去重。
   - LuCI 会预览正则命中后的生效节点，便于确认实际进入路由节点的代理列表。
   - 增加递归引用检查，避免路由节点互相引用形成循环。

3. 节点页 / 订阅页添加测速按钮

   - 基于 sing-box Clash API `/proxies/{tag}/delay`，默认使用 `https://www.gstatic.com/generate_204` 测试延迟。
   - 页面顶部测速按钮可对当前页面节点发起批量测速。
   - 单击节点延迟可对该节点单独测速。
   - 测速基于当前运行配置；若希望订阅节点可测速，请通过节点正则 `.*` 或其他表达式将其加入运行节点组。

4. 路由规则直选节点

   - 路由规则出站可以直接选择某个具体代理节点。
   - 生成器会自动补齐该节点需要的 sing-box outbound。

5. HomeProxy 配置备份 / 恢复

   - HomeProxy 菜单下新增 `备份 / 恢复` 页面。
   - 导出：`/etc/config/homeproxy`、`/etc/homeproxy/resources/direct_list.txt`、`/etc/homeproxy/resources/proxy_list.txt` 以及用户上传到 `/etc/homeproxy/certs/` 的证书和私钥文件。
   - 导入时只接受上述 HomeProxy 源配置路径，恢复前会生成 `/tmp/homeproxy-rollback.tar.gz` 便于回滚。

6. 添加 MetaCubeXD 面板入口

   - 默认开启 Clash API，并添加 HomeProxy 面板代理，用于隐藏 SS2022 + ShadowTLS 生成链路中的中间层节点 `cfg-xxx-out-shadowtls`。
   - 客户端页面添加 `MetaCubeXD 面板` 按钮。
   - 默认跳转到 [https://metacubexd.pages.dev/#/overview](https://metacubexd.pages.dev/#/overview)，跳转时自动带入 HomeProxy 面板代理的 host、port、secret 等参数。
   - 使用远程 MetaCubeXD 面板时，Clash API secret 会提供给该网页；安全要求较高时建议使用自建面板或本地面板。
   - 可通过 MetaCubeXD 面板切换节点、测速、查看连接状态等。

7. 运行时 outbound tag 映射为节点真实名称

   - 生成 sing-box 配置时，将运行时 outbound tag 从 `cfg-<section>-out` 映射为节点 `label`。
   - MetaCubeXD / Yacd / Clash API / LuCI 节点测速会显示真实节点名称，便于识别和排障。
   - 同名节点、保留 tag、内部 `cfg-*` 命名空间冲突时，会生成稳定后缀，避免重复 tag。
   - ShadowTLS 中间层会同步映射，且仍由 HomeProxy 面板代理隐藏。

8. 订阅导入和运行兜底增强

   - 订阅更新支持识别 Surge / Clash 托管配置中的 `proxies:` 节点列表。
   - 订阅节点带 TLS 证书指纹但当前 sing-box 不支持时，默认跳过并写入诊断；可显式开启兼容回退。
   - 删除失效订阅节点时，会同步清理主节点、路由节点、路由规则、DNS、规则集中的引用。
   - 非 `custom` 路由模式下，主节点为空时可回退使用 `routing.default_outbound`。
   - 订阅拉取失败时会记录诊断；`wget` 会在普通拉取失败后尝试 IPv4 回退。
   - 订阅更新的重启语义与 `update_via_proxy` 有关：未启用“使用代理更新”时，成功更新后会重启 HomeProxy；启用后，只有节点新增、更新、删除，或主节点 / 主 UDP 节点因失效订阅节点被清空时才重启。完全没有可用节点时只记录失败状态和诊断；脚本异常时会按兜底逻辑重启服务。

9. 自定义 Release 自动发布

   - push 到 `master` 后自动构建 APK/IPK artifact，用于检查构建是否成功。
   - 打 `custom-*` tag 后会现场构建内置中文翻译的签名 APK 和 v3 软件源索引，并自动发布到 GitHub Releases。
   - 一键安装会自动导入公钥、配置软件源并安装 / 升级 HomeProxy。

10. 定时检查上游更新

   - GitHub Actions 每天检查一次 `immortalwrt/homeproxy:master`。
   - 如果上游有新提交，会创建或更新带 `upstream-update` 标签的 Issue。
   - 检查只负责提醒，不会自动合并代码，也不会自动发布新 APK。

## 安装和更新

### 安装场景

`homeproxy-custom` 是本仓库发布的自定义 HomeProxy 包，用于替换上游 `luci-app-homeproxy`，不是和原版并存的第二套 HomeProxy。

- 从未安装过 HomeProxy：可以直接安装 `homeproxy-custom`。
- 已安装上游 `luci-app-homeproxy`：安装 `homeproxy-custom` 会替换原版文件，原配置 `/etc/config/homeproxy` 会按包管理器规则保留。
- 已删除上游 `luci-app-homeproxy`：可以直接安装 `homeproxy-custom`。
- 简体中文翻译已经内置，不需要再安装 `luci-i18n-homeproxy-zh-cn`。

### A. 一键安装（推荐）

适合全新安装、升级，以及从原版 HomeProxy 迁移：

```sh
wget -O - https://github.com/itv3/homeproxy/raw/refs/heads/master/install.sh | ash
```

脚本会自动导入公钥、添加软件源、更新索引并安装 / 升级 `homeproxy-custom`。如果软件源安装失败，会自动回退到直接 APK 安装。

### B. WebUI 软件源安装 / 升级

1. 下载 latest release 中的 `homeproxy-custom.pem`。
2. 进入 OpenWrt WebUI：`系统 -> 管理权 -> 软件包仓库公钥`，把 `homeproxy-custom.pem` 文件拖进输入框，添加软件包仓库公钥。
3. 进入 `系统 -> 软件包 -> 配置 apk`，在 `/etc/apk/repositories.d/customfeeds.list` 输入框内追加：

```text
https://github.com/itv3/homeproxy/releases/latest/download/Packages.adb
```

4. 回到 `系统 -> 软件包` 页面，点击 `更新列表`，搜索 `homeproxy-custom` 安装。
5. 以后有新版本，更新列表后可在这个页面直接升级 `homeproxy-custom`。

### C. 手动上传 APK 安装 / 升级（备选）

1. 先按上面的方式添加 `homeproxy-custom.pem` 公钥。
2. 下载 latest release 中的 `homeproxy-custom_all.apk`。
3. 进入 `系统 -> 软件包`，上传 `homeproxy-custom_all.apk` 安装 / 升级。

如果从旧的 `luci-app-homeproxy` 迁移时遇到 `breaks: world[luci-app-homeproxy><...]` 报错，请使用一键安装命令完成迁移。

### D. SSH 软件源安装 / 升级

也可以手动添加软件源文件：

```sh
wget -O /etc/apk/keys/homeproxy-custom.pem https://github.com/itv3/homeproxy/releases/latest/download/homeproxy-custom.pem
printf '%s\n' 'https://github.com/itv3/homeproxy/releases/latest/download/Packages.adb' > /etc/apk/repositories.d/homeproxy-custom.list
apk update
apk del luci-i18n-homeproxy-zh-cn 2>/dev/null || true
apk add homeproxy-custom
```

清理升级产生的 `.apk-new` 文件：

```sh
find /etc/homeproxy /etc/config -name "*.apk-new" -exec rm -f {} \; 2>/dev/null || true
```

重启服务：

```sh
/etc/init.d/homeproxy restart
```

## 给开发者 / AI 的维护说明

只看本 README 应该能完成一次新功能开发和发布。当前自定义版主要涉及下面几类文件：

```text
htdocs/luci-static/resources/view/homeproxy/client.js   # 客户端页面、路由节点、路由规则接入
htdocs/luci-static/resources/view/homeproxy/node.js     # 节点页面、SS2022 + ShadowTLS 表单接入
htdocs/luci-static/resources/view/homeproxy/backup.js   # HomeProxy 源配置备份 / 恢复页面
htdocs/luci-static/resources/homeproxy/dashboard.js     # MetaCubeXD 面板入口 helper
htdocs/luci-static/resources/homeproxy/diagnostics.js   # 配置诊断前端 helper
htdocs/luci-static/resources/homeproxy/node-filter.js   # 节点正则预览前端 helper
htdocs/luci-static/resources/homeproxy/routing-node.js  # 路由节点前端 helper
htdocs/luci-static/resources/homeproxy/tcping.js        # 节点测速前端 helper
root/etc/homeproxy/scripts/generate_client.uc           # 生成 sing-box 客户端配置
root/etc/homeproxy/scripts/clash_api.uc                 # Clash API controller 地址解析和本机地址归一化 helper
root/etc/homeproxy/scripts/clash_api_proxy.uc           # MetaCubeXD 读取用 Clash API 过滤代理
root/etc/homeproxy/scripts/homeproxy.uc                 # 公共工具函数和订阅下载 helper
root/etc/homeproxy/scripts/migrate_config.uc            # 旧配置迁移和默认配置补齐
root/etc/homeproxy/scripts/node_filter.uc               # 节点正则限制 helper
root/etc/homeproxy/scripts/node_references.uc           # 节点引用收集和删除订阅节点清理
root/etc/homeproxy/scripts/outbound_tag.uc              # outbound tag 映射和去重
root/etc/homeproxy/scripts/routing_target.uc            # 路由节点解析 helper
root/etc/homeproxy/scripts/subscription_parsers.uc      # Surge / Clash 托管配置 parser
root/etc/homeproxy/scripts/update_subscriptions.uc      # 订阅导入、节点增删改和重启调度
root/etc/homeproxy/scripts/firewall_pre.uc              # TUN 启动前置规则
root/etc/homeproxy/scripts/firewall_post.ut             # nftables 规则模板
root/etc/init.d/homeproxy                               # procd 启动、TProxy/TUN 路由和面板代理实例
root/etc/config/homeproxy                               # 新安装时的默认配置
root/usr/share/rpcd/ucode/luci.homeproxy                # HomeProxy 基础 RPC
root/usr/share/rpcd/ucode/luci.homeproxy_backup         # HomeProxy 备份 / 恢复 RPC
root/usr/share/rpcd/ucode/luci.homeproxy_node_tools     # 节点引用、节点正则预览、订阅更新和诊断 RPC
root/usr/share/rpcd/ucode/luci.homeproxy_tcping         # 节点测速 RPC
tests/generator-golden                                  # 生成器 golden fixture 和目标机运行器
docs/security/OUTBOUND_TAG_RENAME_DESIGN.md             # outbound tag 可读化长期设计记录
.github/build-ipk.sh                                    # APK/IPK 打包脚本
.github/workflows/build-ipk.yml                        # push / PR 后自动构建 APK/IPK artifact
.github/workflows/release-custom-apk.yml               # tag 后现场构建 APK 并发布 GitHub Release
.github/workflows/check-upstream.yml                   # 定时检查上游是否有新提交
install.sh                                              # 路由器一键安装脚本
```

### 开发新功能

```sh
git clone git@github.com:itv3/homeproxy.git
cd homeproxy
git checkout master
git remote add upstream https://github.com/immortalwrt/homeproxy.git 2>/dev/null || true
git fetch origin
git fetch upstream
```

修改代码后先做基本检查：

```sh
git diff --check
sh -n install.sh
node tests/generator-golden/check_cases.js
```

如果改了 `generate_client.uc`，还需要在带 `ucode` 的 OpenWrt/ImmortalWrt 目标机上运行完整 golden fixture。CI 的 `Build ipk for HomeProxy` 也会在 OpenWrt rootfs 容器中执行这一步：

```sh
ucode -S tests/generator-golden/run_cases.uc tests/generator-golden
```

如果改了 GitHub Actions workflow，可额外检查 YAML：

```sh
ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].each { |f| YAML.load_file(f) }; puts "yaml ok"'
```

提交并推送：

```sh
git add <changed-files>
git commit -m "feat: describe the change"
git push origin master
```

推送后 GitHub Actions 会自动构建 APK/IPK artifact，用来确认代码能正常打包。这个构建不会再提交 `dist/` 文件。

进入 GitHub `Actions` 页面确认 `Build ipk for HomeProxy` 成功后，再发布 Release。

### 发布新版本

tag 必须打在要发布的源码提交上。推荐格式：

```sh
FEATURE_SHA="$(git rev-parse --short HEAD)"
TAG="custom-$(date +%Y%m%d)-${FEATURE_SHA}"
git tag -a "$TAG" -m "HomeProxy Custom ${TAG#custom-}"
git push origin "$TAG"
```

推送 tag 后，`Release custom APK` workflow 会现场构建内置中文翻译的签名 APK 和软件源索引，创建 GitHub Release，并上传：

```text
homeproxy-custom_all.apk
Packages.adb
homeproxy-custom.pem
```

Release 标题、APK 软件包版本和软件源描述会把 tag 中的 `YYYYMMDD-短SHA` 转成 `YYYYMMDD.HHMMSS~短SHA`，其中 `HHMMSS` 取 tag 指向提交的北京时间提交时间，例如 `custom-20260615-1b55552` 会显示为 `20260615.141105~1b55552`。日期后的时间段保证同一天连续发布时 apk-tools 能正确判断新版本大于旧版本；`~短SHA` 只作为展示和追踪用的提交标识。

发布后检查：

```sh
curl -fsSL https://api.github.com/repos/itv3/homeproxy/releases/latest \
  | jq -r '.tag_name, .assets[].name, .assets[].digest'
```

## HomeProxy 上游更新后怎么办

不要直接用上游包覆盖本自定义包。上游更新提醒由 `.github/workflows/check-upstream.yml` 负责：

- 每天北京时间 10:00 自动检查一次。
- 也可以在 GitHub 页面进入 `Actions` -> `Check upstream updates` -> `Run workflow` 手动检查。
- 如果上游有新提交，会创建或更新一个带 `upstream-update` 标签的 Issue。
- 如需邮件通知，在仓库页面 `Watch` -> `Custom` 中勾选 `Issues`，并在 GitHub 通知设置中为 watching 启用 `Email`。
- 这个 workflow 只提醒，不会自动 merge，因为上游改动可能和自定义功能冲突。

收到提醒后，推荐让开发者或 AI 按下面流程操作。

### 1. 同步上游并合并到维护分支

```sh
git fetch upstream
git fetch origin
git checkout master
git merge upstream/master
```

容易发生冲突的文件：

```text
htdocs/luci-static/resources/view/homeproxy/client.js
htdocs/luci-static/resources/view/homeproxy/node.js
root/etc/homeproxy/scripts/generate_client.uc
root/etc/homeproxy/scripts/outbound_tag.uc
root/etc/homeproxy/scripts/routing_target.uc
root/etc/homeproxy/scripts/node_references.uc
root/etc/homeproxy/scripts/update_subscriptions.uc
root/etc/homeproxy/scripts/homeproxy.uc
root/etc/homeproxy/scripts/migrate_config.uc
root/etc/homeproxy/scripts/firewall_pre.uc
root/etc/homeproxy/scripts/firewall_post.ut
root/etc/init.d/homeproxy
root/etc/config/homeproxy
root/usr/share/rpcd/ucode/luci.homeproxy
```

如果出现冲突，优先保留上游的新结构，再重新套回本仓库的自定义能力：

- SS2022 + ShadowTLS 表单和生成逻辑。
- 路由节点 Selector。
- Selector 可包含具体节点和已有路由节点。
- Selector / URLTest 路由节点支持按节点名称正则筛选节点。
- 节点页 / 订阅页测速按钮。
- 路由规则可直接选择具体节点。
- HomeProxy 源配置备份 / 恢复。
- MetaCubeXD 面板入口、Clash API 默认配置和面板代理。
- 运行时 outbound tag 映射为节点真实名称。
- Surge / Clash 托管配置订阅解析、TLS 证书指纹兼容策略。
- 非 `custom` 模式下 `default_outbound` 兜底，以及订阅删除时的引用清理。

### 2. 本地检查

合并完成后先跑基础检查：

```sh
git diff --check
sh -n install.sh
ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].each { |f| YAML.load_file(f) }; puts "yaml ok"'
```

如果改到了 LuCI JavaScript，建议再跑：

```sh
node --check htdocs/luci-static/resources/homeproxy.js
node --check htdocs/luci-static/resources/view/homeproxy/client.js
node --check htdocs/luci-static/resources/view/homeproxy/node.js
```

### 3. 推送并等待自动构建

```sh
git push origin master
```

推送后 `Build ipk for HomeProxy` workflow 会自动构建 APK/IPK artifact，用来确认代码能正常打包。这个 workflow 不会再提交 `dist/` 文件。

进入 GitHub `Actions` 页面确认 `Build ipk for HomeProxy` 成功后，再发布 Release。

### 4. 发布新的自定义 APK

tag 必须打在要发布的源码提交上：

```sh
FEATURE_SHA="$(git rev-parse --short HEAD)"
TAG="custom-$(date +%Y%m%d)-${FEATURE_SHA}"
git tag -a "$TAG" -m "HomeProxy Custom ${TAG#custom-}"
git push origin "$TAG"
```

推送 tag 后，`Release custom APK` workflow 会发布新版 APK 到 GitHub Releases。发布后检查：

Release 标题、APK 软件包版本和软件源描述会把 tag 中的 `YYYYMMDD-短SHA` 转成 `YYYYMMDD.HHMMSS~短SHA`，其中 `HHMMSS` 取 tag 指向提交的北京时间提交时间，例如 `custom-20260615-1b55552` 会显示为 `20260615.141105~1b55552`。日期后的时间段保证同一天连续发布时 apk-tools 能正确判断新版本大于旧版本；`~短SHA` 只作为展示和追踪用的提交标识。

```sh
curl -fsSL https://api.github.com/repos/itv3/homeproxy/releases/latest \
  | jq -r '.tag_name, .assets[].name, .assets[].digest'
```

如果上游更新提醒 Issue 还开着，确认自定义分支已经包含上游最新版后，可以关闭该 Issue。

## 注意

MetaCubeXD 的规则开关对当前 sing-box Clash API 不生效。sing-box 当前只提供 `/rules` 读取接口，没有实现 `PATCH /rules/disable` 这种运行时禁用规则的接口。
