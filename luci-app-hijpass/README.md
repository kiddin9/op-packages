# 编译

## OpenWrt 软件包

在已添加本包、安装所需 feeds 并完成配置的 OpenWrt 源码树或 SDK 根目录执行（首次编译需要联网）：

```sh
make package/luci-app-hijpass/clean
make package/luci-app-hijpass/compile V=s
```

## OpenWrt 固件

在 OpenWrt 源码树根目录执行，在菜单中选中本包后编译：

```sh
make menuconfig
make -j"$(nproc)"
```

## 本地 JS

仓库中默认js是已经编译好的最新版本。如想自行编译，安装 Node.js 18 或更高版本，在本仓库根目录执行：

```sh
cd ts-src
npm install
npm run build
```

输出目录：`htdocs/luci-static/resources/view/hijpass/`（相对于仓库根目录）。
