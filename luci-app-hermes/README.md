# luci-app-hermes

OpenWrt LuCI 插件，为 [Hermes Agent](https://github.com/nousresearch/hermes-agent) 提供 Web 管理界面。

[![Release](https://img.shields.io/github/v/release/Boos4721/luci-app-hermes)](https://github.com/Boos4721/luci-app-hermes/releases)
[![Build IPK](https://img.shields.io/github/actions/workflow/status/Boos4721/luci-app-hermes/build-ipk.yml?label=build-ipk)](https://github.com/Boos4721/luci-app-hermes/actions/workflows/build-ipk.yml)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

## 功能特性

- **一键安装**：自动下载 Python3 + 创建虚拟环境 + 安装 Hermes Agent，适配 OpenWrt/ImmortalWrt
- **Web 管理界面**：概况、设置、Web 控制台、配置终端 全中文 UI
- **Web 控制台**：内嵌 Hermes Agent Gateway Web UI，支持完整 AI 交互
- **配置终端**：内嵌 WebSocket PTY，支持交互式配置管理
- **资源自适应**：根据设备内存自动限制 Python 进程内存，防止 OOM
- **磁盘空间优化**：安装前预检空间，PyPI 多镜像重试（阿里云 → 清华 → PyPI 官方）
- **BusyBox 兼容**：完整适配 OpenWrt BusyBox 环境
- **OpenWrt 安全**：LuCI 鉴权保护，Token 认证机制
- **服务管理**：支持 Gateway 和 PTY 独立启停、自动重启

## 支持架构

| 架构 | 说明 |
|------|------|
| all | 架构无关包，Python 运行时通过 opkg 自动安装 |

支持所有 OpenWrt/ImmortalWrt 设备（x86_64、aarch64、armv7l 等）。

---

## 安装（推荐）

在 OpenWrt 路由器上执行一条命令即可完成安装：

```sh
opkg update && opkg install luci-app-hermes
```

或者使用一键脚本（从 GitHub 直接安装）：

```sh
sh -c "$(wget -qO- https://cdn.jsdelivr.net/gh/Boos4721/luci-app-hermes@main/scripts/install.sh)"
```

> 脚本会自动下载最新版 `.ipk`，通过 `opkg` 安装，并清除 LuCI 缓存。

---

### 方式二：手动下载 IPK

从 [Releases](https://github.com/Boos4721/luci-app-hermes/releases) 页面下载最新版：

```sh
wget -O /tmp/luci-app-hermes.ipk \
  https://github.com/Boos4721/luci-app-hermes/releases/latest/download/luci-app-hermes_*_all.ipk
opkg install --force-reinstall /tmp/luci-app-hermes.ipk
```

### 方式三：作为 OpenWrt feeds

```bash
# 在 feeds.conf.default 中添加
src-git hermes https://github.com/Boos4721/luci-app-hermes.git

# 更新并安装
./scripts/feeds update hermes
./scripts/feeds install luci-app-hermes
make package/luci-app-hermes/compile V=s
```

---

## 安装后配置

1. 打开 LuCI → **服务** → **Hermes Agent**
2. 点击 **更多** → **安装环境**，等待 Python3 + Hermes Agent 安装完成（约 5~15 分钟）
3. 启用服务，在 **设置** 中配置 API Endpoint 和 API Key
4. 在 **Web 控制台** 中与 AI 模型交互

## 磁盘空间不足解决方案

OpenWrt 设备 root 分区通常只有 1GB 以下，Python + Hermes Agent 安装包约 500MB。

**解决方案：bind mount tmpfs**

```bash
# 在 /etc/rc.local 中添加（开机自动执行）
mkdir -p /tmp/hermes
mount --bind /tmp/hermes /opt/hermes
```

> `/tmp` 通常挂载为 tmpfs，大小约为物理内存的 50%，重启后数据丢失，需重新安装

---

## 目录结构

```
luci-app-hermes/
├── .github/workflows/
│   └── build-ipk.yml            # 自动编译 IPK，推送 tag 时触发
├── htdocs/
│   └── luci-static/resources/view/
│       └── hermes.js            # LuCI JS 视图（主 UI）
├── luasrc/
│   ├── controller/hermes.lua    # LuCI 路由控制器
│   ├── model/cbi/hermes.lua     # CBI 配置模型（兼容旧版 LuCI）
│   └── view/hermes/             # Lua 视图模板
├── root/
│   ├── etc/
│   │   ├── config/hermes        # UCI 默认配置
│   │   ├── init.d/hermes        # procd 服务脚本
│   │   └── uci-defaults/        # 首次安装初始化
│   └── usr/
│       ├── bin/hermes-env       # 安装/管理脚本（核心）
│       └── share/hermes/
│           ├── luci-helper      # LuCI RPC 辅助脚本
│           ├── web-pty.py       # WebSocket PTY 服务器
│           └── ui/              # Web 控制台 UI
├── po/zh_Hans/hermes.po         # 中文翻译
├── scripts/
│   └── install.sh               # 一键安装脚本
├── Makefile
├── VERSION
└── LICENSE
```

---

## 常见问题

**Q: 安装时提示 python3 找不到**
A: 插件依赖 `python3` 和 `python3-pip`，确保 OpenWrt 软件源已更新（`opkg update`）。

**Q: Hermes Agent 安装失败，pip 超时**
A: hermes-env 已内置三镜像重试（阿里云 → 清华 → PyPI 官方）。如仍失败，检查路由器 DNS 和网络连接，或手动执行 `hermes-env setup` 查看详细日志。

**Q: 安装完成后 Gateway 不启动**
A: 检查磁盘空间：`df -h /opt`，若已满需配置 bind mount 到 tmpfs。同时确认 Python 虚拟环境已正确安装：`hermes-env check`。

**Q: 内存不足设备如何使用**
A: 插件自动根据内存设置进程限制（512MB RAM → 限制 256MB），无需手动配置。

**Q: Web 控制台无法访问**
A: 确保服务已启用并在 **设置** 中配置了正确的 API Endpoint 和 API Key。Gateway 默认端口 3000，PTY 端口 3001。

**Q: 配置终端无法输入**
A: 确保点击终端区域使其获得焦点，然后输入命令并按 Enter。

---

## 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|---------|
| 2026.05.10 | 2026-05-10 | 初始发布，支持 LuCI 24/25，Python-based 架构 |

---

## 致谢

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) — AI Agent 核心
- [ImmortalWrt](https://immortalwrt.org) — 主要测试平台

## License

GPL-3.0 © [Boos4721](https://github.com/Boos4721)
