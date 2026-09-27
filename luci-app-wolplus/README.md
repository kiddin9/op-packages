# luci-app-wolplus（网络唤醒++）

<br>中文 | [English](README_en.md)

一款更方便的**网络唤醒（Wake on LAN）**插件 —— 在 LuCI 里管理待唤醒的主机，一键开机。

> 🤖 **本次 24.10 适配由 AI 完成**（ucode 后端 + JS 前端重写）。

## 🙏 致谢与来源

本项目改编自 **[@sundaqiang](https://github.com/sundaqiang/openwrt-packages/tree/master/luci-app-wolplus)** 的
`luci-app-wolplus`，在原版基础上适配 **OpenWrt 24.10**（新版 LuCI 的 JS/ucode 架构）。

原版采用 Apache-2.0 授权，本项目**沿用同一协议**，并保留原作者署名。

## ✨ 特性

- 🖥️ **主机列表管理** —— 增删改、拖动排序
- 🔍 **自动补全 MAC** —— 从局域网主机表里直接选，不用手敲
- 🎛️ **指定网卡** —— 多网卡机器可指定从哪块网卡发唤醒包
- ⚡ **一键唤醒** —— 点一下按钮就发包
- 🌏 **中文界面** —— 自带翻译
- 🔧 **适配 OpenWrt 24.10** —— ucode 后端 + 新版 LuCI JS 前端

## 📦 安装

### 方式一：编译成 ipk（推荐）

在 OpenWrt 源码根目录执行：

```bash
# 1. 进入 package 目录，克隆插件
cd package
git clone https://github.com/sakura-builder1/luci-app-wolplus.git

# 2. 回到源码根目录
cd ..

# 3. 更新一下 feeds（首次编译需要）
./scripts/feeds update -a && ./scripts/feeds install -a

# 4. 只编译这个插件
make package/luci-app-wolplus/compile V=s
```

编译产物在：

```
bin/packages/<架构>/base/luci-app-wolplus_*.ipk
```

拷到路由器安装：

```bash
scp bin/packages/x86_64/base/luci-app-wolplus_*.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
opkg install /tmp/luci-app-wolplus_*.ipk
/etc/init.d/rpcd restart          # 重要！否则菜单不显示
```

### 方式二：集成进固件

```bash
make menuconfig
```

进入：

```
LuCI
  └── Applications
        └── <M> luci-app-wolplus
```

> 💡 依赖会自动带上：`luci-base` `etherwake` `rpcd` `ucode` `ucode-mod-fs` `ucode-mod-uci`

然后正常编译固件：

```bash
make -j$(nproc)
```

安装后在 **服务 → Wake on LAN +** 里使用。

## 🔧 兼容性

| OpenWrt 版本 | 状态 |
|---|---|
| 24.10 | ✅ 已适配并测试 |
| 23.05 | ⚠️ 需要旧版 LuCI（Lua/CBI）|
| 25.12 | ⚠️ 需要适配 `apk` |

## 📄 License

<img width="2197" height="1265" alt="image" src="https://github.com/user-attachments/assets/fc2c1099-7b40-48e9-81bc-40fd22161c1d" />

Apache-2.0

沿用原版协议。原作者 [@sundaqiang](https://github.com/sundaqiang/openwrt-packages)，
本适配版由 AI 编写。
