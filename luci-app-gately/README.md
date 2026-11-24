# OpenWrt Gately (`luci-app-gately`)

将 [wangwanjie/gately](https://github.com/wangwanjie/gately) 核心二进制编译与官方提供的 `deploy/openwrt/luci`、`deploy/openwrt/gately.init` 整合为单一的 `luci-app-gately` OpenWrt 软件包（兼容 OpenWrt 24.10 `opkg` 与 25.12+ `apk`）。

## 特性说明

- **单包一体化构建**：仅拉取一次上游源码包，编译 `gately` 静态二进制并直接铺装上游自带的 LuCI 页面、10 语言 `.lmo` 翻译包、`rpcd` 脚本、`procd` 启动脚本及 `/lib/upgrade/keep.d/gately` 固件升级保留规则，声明 `PROVIDES:=gately`。
- **对齐上游构建优化**：默认注入 `coraza.disabled_operators.validateSchema` 编译标签（剔除未使用的算子依赖，缩减约 2.3 MB 体积）、`CGO_ENABLED=0` 与 `-s -w` 符号剥离。
- **可选菜单裁剪（`Config.in`）**：在 `make menuconfig`（`LuCI -> 3. Applications -> luci-app-gately -> Configuration`）中支持按需选择前端打包语言档位（全语言 / 中英 / 仅简体中文）或裁剪 24 个可选模块以适配小闪存路由器。

## 编译方式

编译环境需具备 OpenWrt SDK / Buildroot（上游[构建要求](https://gately.cn/en/docs/guide/contributing)为 Go 1.26+、Node.js 24+ 与 `pnpm`）：

```sh
git clone https://github.com/kiddin9/openwrt-gately.git package/openwrt-gately
make package/luci-app-gately/compile V=s
```

默认管理地址为 `http://<路由器IP>:16680`，初始账号密码为 `admin` / `gately.cn`（详见[官方安装文档](https://gately.cn/en/docs/guide/install)）。
