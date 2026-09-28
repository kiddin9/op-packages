# NetWiz (luci-app-netwiz) 🚀

[English](#english) | [简体中文](#简体中文)

**NetWiz** —— 您的专属 OpenWrt 极简网络设置向导。开箱即用，化繁为简。

凭借严谨缜密的底层逻辑，NetWiz 不仅为您提供直观的交互与大小屏极致丝滑的 UI 体验，更带来全方位的企业级网络守护：

🛡️ 智能配置与防呆守护：搭载企业级 LAN 口防失联机制与全网段冲突排雷（智能解决 IP、网关、WAN/LAN 冲突）。支持 WAN 口上网方式盲插智能切换（断开 10 秒后重新接入自动侦测）、智能防错校验、一键开启 IPv6，以及智能 Wi-Fi 满血释放（无物理硬件时自动隐藏）。

📊 企业级网络管控：深入系统内核，提供灾备级全自动配置管理。涵盖终端流量透视、IP 智能分组、一键批量绑定静态 IP 策略组以及一键防火墙控制，让复杂网络管理得心应手。

📦 首创 SmartGhost 智能恢复：NetWiz 不仅仅是设置向导，更打造了独家首创智能备份与恢复的完美闭环。搭载「SmartGhost 全量离线系统恢复」技术，无需全程联网，无惧跨版本刷机！能在彻底断网的新固件上，一键完美恢复您的插件与复杂网络配置，并提供商用级的防内存溢出（OOM）保护与跨网段无缝跃迁的丝滑恢复体验。

**NetWiz (Network Wizard)** — Your exclusive, minimalist OpenWrt network setup wizard. Ready out of the box, turning complexity into simplicity.

Built upon rigorous and well-structured underlying logic, NetWiz delivers not only a seamlessly smooth and responsive UI across all screen sizes but also comprehensive, enterprise-grade network protection:

🛡️ Intelligent Setup & Failsafe Protection: Features an enterprise-grade LAN fail-safe mechanism and proactive conflict resolution across IP, Gateway, WAN, and LAN subnets. It supports smart WAN mode blind-switching (auto-detects when the cable is reinserted after a 10-second disconnection), smart error-prevention validation, one-click IPv6 activation, and full-performance Wi-Fi configuration (automatically hides when no physical hardware is detected).

📊 Enterprise-Grade Network Management: Diving deep into the system kernel, NetWiz empowers you with disaster-recovery-level automated management. It offers terminal traffic visibility, smart IP grouping, one-click batch binding for static IP policy groups, and one-click firewall control.

📦 SmartGhost Offline Full Recovery: Much more than just a setup wizard, NetWiz pioneers a perfect closed-loop backup and restore ecosystem. Powered by the original "SmartGhost Full Offline System Recovery" technology, it requires no continuous internet connection and eliminates the fear of cross-version firmware flashing. It can perfectly clone and restore all your third-party plugins and complex network configs onto newly flashed, completely offline firmware—all while delivering commercial-grade Out-of-Memory (OOM) protection and a seamless cross-subnet recovery experience.

![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg) ![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05_|_25.x+-blue.svg) ![ImmortalWrt](https://img.shields.io/badge/ImmortalWrt-Supported-orange.svg) ![Downloads](https://img.shields.io/github/downloads/huchd0/luci-app-netwiz/total.svg?logo=github) ![Views](https://komarev.com/ghpvc/?username=huchd0-luci-app-netwiz&label=Views&color=blue&style=flat) ![License](https://img.shields.io/badge/License-GPL--3.0-green.svg)

---

## English

### Description

**NetWiz (Network Setup Wizard)** is a minimalist, secure, and "zero-destructive" network configuration interface exclusively designed for OpenWrt and ImmortalWrt.

Tailored perfectly for novice users, it enables secure, one-click configuration of secondary routers (Dynamic/Static IP) and Bypass/AP (Wired Repeater) environments. For users who have just flashed a new system, setting up the network is essential for internet access, yet native settings are often deeply hidden and error-prone. Blindly and forcefully resetting network configuration files can **wipe out your configured device lists**, causing carefully crafted network bridges, VLANs, and physical NIC bindings to **crash instantly or trigger inexplicable issues**. **NetWiz is born to solve this exact pain point.**

### Installation Methods

[Use the one-click command for quick installation.](#install)

```bash
if wget -qO /tmp/nw_inst.sh https://raw.githubusercontent.com/huchd0/luci-app-netwiz/master/install.sh; then sh /tmp/nw_inst.sh; else sh /etc/netwiz/custom_pkgs/install.sh; fi
```

## 🤝 Compatibility Guide

* **Firmware Support:** OpenWrt 23.05+ and ImmortalWrt 23.05+ are recommended (Flawlessly supports the new 25.x+ branches and is fully compatible with the `nftables` environment).
* **Architecture Support:** Universal compatibility across all architectures (x86_64, aarch64, ramips/mt7621, etc.).

**💡 Ultimate System Compatibility:**
NetWiz achieves true "zero external dependencies," utilizing no C/C++/Go compiled binaries or third-party modules. Backed by a highly rigorous underlying safeguard and fallback architecture, NetWiz delivers outstanding compatibility across various branches and heavily modified (custom-built) firmwares. Whether on legacy systems or the new generation `fw4`/DSA architecture post-23.05, it adapts perfectly and runs with rock-solid stability.

## ✨ Core Features & Advantages

### 💻 Modern Architecture
* **Lightning-Fast & Stutter-Free:** Built on a modern responsive and elastic architecture, saying goodbye to clunky and laggy interfaces. It perfectly adapts to both desktop and mobile screens for a silky-smooth experience.
* **Strict Privilege Isolation:** Complete separation of UI operations and underlying system privileges. The frontend has no direct permission to modify core configs; all changes are safely executed by a trusted sandbox proxy.
* **Native Multi-Language Support:** Automatically switches between Simplified Chinese, Traditional Chinese, and English based on your system environment.
* **Extensive Hardware Compatibility:** Intelligently adapts to multi-chip and multi-band hardware, maximizing hardware potential and unleashing full Wi-Fi signal strength.

### 🛡️ Comprehensive Safeguards
* **Failsafe Rollback Mechanism:** Afraid that a configuration error will lock you out of the backend? Don't worry! Applying new configurations triggers a 120-second safety countdown. If no real new IP connections access the LAN port after the change, the system automatically reverts to the previous configuration **(gracefully recovers even upon unexpected power loss or reboot)**.
* **Smart Error Prevention:** Strictly and accurately intercepts high-risk operations such as "IP conflicts or incorrectly filled information," preventing router endless loops right from the source.
* **Bypass/AP Mode Auto-Safeguard:** Switch to Bypass or AP (Wired Repeater) mode safely with one click. The system automatically disables conflicting services, provides smart setup guidance, and helps you fill in the correct information without disrupting your existing home network topology. Beginner-friendly.
* **Comprehensive Device Dashboard:** Master the real-time dynamics of all online, offline, and static devices.
* **Traffic Analysis Probe:** Hover to view the P2P and Web connection distribution for any specific device.
* **Full-Link Disaster Recovery:** Roll back or import external configuration files at any time.

### ⚡ Ultimate Seamless Experience
* **Smart WAN Mode Switching:** Detects the physical plug/unplug status of the WAN cable and intelligently adapts the network mode. It perfectly filters out "pseudo-disconnections" caused by dial-up failures or software reboots **(unplugging the network cable and reconnecting after 10 seconds triggers the smart mode-switching mechanism)**.
* **Auto-Detection & Instant Redirection:** After modifying the IP, the frontend silently probes the new address. Once the network connects, it instantly redirects, ensuring a buttery-smooth experience.
* **Non-Disruptive Network Settings:** Applying partial network settings keeps Wi-Fi stable and connected without interfering with other devices' internet access.
* **Seamless Bi-Directional Sync:** When switching between "Band Steering (Merged)" and "Split Band" modes, Wi-Fi passwords and SSIDs are intelligently synchronized, eliminating the hassle of repetitive typing. Built-in historical config memory.
* **One-Click IPv6:** Intelligently issues IPv6 addresses with one click, saying goodbye to obscure DHCPv6, SLAAC, and relay settings. With a simple tap, the system automatically assigns IPv6 addresses to your devices.
* **One-Click Seamless Wi-Fi Roaming:** Enable seamless roaming without requiring professional technical skills. Just meet two conditions for automatic, silky-smooth Wi-Fi transitions between multiple routers: identical Wi-Fi names/passwords and devices on the same LAN. *(Note: Ensure no multiple DHCP servers exist in the environment; if routers are close to each other, stagger channels to avoid co-channel signal interference.)*
* **Quick Wireless Repeater (WISP):** Enter the upstream Wi-Fi credentials to receive the signal and broadcast your own exclusive Wi-Fi network.

### 📶 Powerful Smart Wi-Fi Control
* **Universal Hardware Adaptation:** Automatically takes over all physical wireless NICs in the system, seamlessly adapting whether it's a single-band, dual-band, tri-band, or even multi-band router.
* **Hidden Fault Repair:** Targets incomplete, conflicting, or corrupted underlying configurations. Automatically cleans up legacy error Wi-Fi configs in the system and corrects stuck network states, ensuring highly stable wireless performance.
* **Full Bandwidth Unleashed:** Say goodbye to crippled network speeds! When saving configurations, it intelligently identifies hardware limits and silently optimizes Wi-Fi bandwidth for maximum throughput.

### 🧭 Quick Navigation
👉 **Find the 👉 Network Wizard directly at the end of the LuCI primary menu (right before the "Logout" button).**

---

### 🚀 Four Core Supported Modules:

1. 🔌 **Broadband Dial-up (PPPoE)**
   * **Scenario:** The optical modem is in pure bridge mode; this router handles the dial-up directly, acting as the whole-house network hub.
   * **Behavior:** Accurately writes broadband accounts and passwords, strips residual legacy gateway settings, and safely restarts underlying dial-up processes.

2. 📶 **Wi-Fi Settings (Auto-hides if no hardware is detected)**
   * **Scenario:** Initializing the wireless network for the first time, or modifying the whole-house Wi-Fi name, password, and security encryption protocol.
   * **Behavior:** Intelligently detects the number of underlying physical chips and dynamically renders the UI. Supports one-click "Band Steering (Merged)" for a whole-house smart roaming network, or splitting into independent 2.4G/5G/5G_Game networks. Perfectly compatible with legacy 802.11b IoT devices.

3. 🌐 **Secondary Router Mode (DHCP / Static IP)**
   * **Scenario:** The modem handles dial-up, or there is an existing main router upstream. This device acts as a secondary router or subnet router.
   * **Behavior:** Freely choose "Dynamic IP (DHCP)" or "Static IP". Automatically takes over WAN port configurations and intelligently validates subnets to prevent routing loops.

4. 🏠 **LAN Settings (Main Router / Bypass/AP Mode Toggle)**
   * **Scenario:** Only modifying the device's internal management IP; or a main router already exists, and this device serves purely as an auxiliary gateway / Bypass router (AP Wired Repeater).
   * **Behavior:** One-click toggle for "Bypass/AP Mode". The system automatically disables the local DHCP service and enforces main router gateway input. If acting as the main router, it smartly prompts to leave the gateway blank, guaranteeing zero destruction to the existing LAN topology.

---

## ✨ Device Management Expert: Core Features

### ⚡ Connection Radar & Kernel-Level Traffic Insight
* **Real-Time Connection Tracking:** Deeply parses the core modules of network connection states, capturing the underlying network connections of terminal devices in real-time.
* **Smart Traffic Categorization:** Automatically and accurately categorizes traffic into Web/HTTPS, DNS/NTP, UDP Media, and P2P High-Port downloads, displayed via an **intuitive dynamic pie chart**.
* **Abnormal Terminal Alert:** Automatically identifies cross-subnet devices and suspected spoofed MAC devices.

### 🏷️ Smart IP Grouping & Batch Static Assignment
* **Fully Automated Categorization:** Accurately identifies Mobile (Phones/Tablets), PC (Workstations), and IoT (Smart Home devices).
* **Multi-Strategy Batch Deployment:** Select multiple devices to execute a one-click **sequential assignment**, **smart exclusive subnet assignment by device type**, or assign to **custom departments/rooms**.
* **Secure Anti-Conflict:** Built-in smart anti-conflict algorithm. Automatically postpones IP allocation when conflicts occur, eliminating network paralysis.

### 🌐 Pure-Blood IPv6 Deep Support
* **Seamless Parsing:** Automatically filters out link-local addresses (`fe80`) to accurately extract public IPv6 addresses.
* **PC Keep-Alive Mechanism:** An exclusive `v6pc_` active timestamp mechanism prevents PC IPv6 addresses from frequently shifting, which leads to lost connections.

### 🛡️ One-Click Firewall & Access Control
* **⛔ Block Internet:** Cut off external network access with one click while preserving LAN communication. Takes effect in seconds.
* **🛡️ LAN Isolation:** One-click ban on accessing other devices within the internal network (prevents bypass router snooping and smart home privacy leaks).
* **🚀 DMZ Host:** Expose all ports of a specific device to the public network with one click (with automatic mutual-exclusion validation to prevent conflicts).
* **🔌 Wake on LAN (WOL):** Deeply integrated; the wake button automatically appears when a device goes offline.

### 📦 Disaster-Recovery Level Config Management
* **Lossless Auto-Backup:** When the network topology changes (e.g., modifying DHCP or firewall), the backend automatically calculates the MD5 of core configuration files and generates a `.tar.gz` backup archive upon changes.
* **One-Click Import/Export:** Pack and download all current static IPs, blacklists, and isolation rules to your PC. Or, easily restore them from the cloud/local storage after flashing the firmware, automatically waking up all advanced proxy and DNS plugins post-recovery.

---

## 简体中文

### 📖简介 | [English](#english)

**NetWiz (网络设置向导)** 是一款专为 OpenWrt / ImmortalWrt 设计的极简、安全且“零破坏”的网络配置界面。

NetWiz极其适合新手用户，能够一键安全地配置二级路由（动态 / 静态 IP）以及旁路由 / AP（有线中继）环境。对于刚刷完系统的玩家，正确配置网络是上网的第一步，但系统自带的设置隐藏较深且容易配错。此时若盲目、暴力地重置整个网络配置文件，会**清空路由器的已配置清单**，导致精心设置的网桥（Bridge）、VLAN 和物理网卡绑定**崩溃或引发莫名其妙的故障**。**NetWiz 专为解决此痛点而生。**

## 🤝 兼容性说明

* **固件支持**：建议 OpenWrt 23.05 及以上版本、ImmortalWrt 23.05 及以上版本（完美支持 25.x+ 新分支，全面兼容 nftables 环境）。
* **架构支持**：全架构通用 (x86_64, aarch64, ramips/mt7621 等)。

**💡 极致的系统兼容性：**
NetWiz 的“零外部依赖”，无任何 C/C++/Go 编译件、第三方模块 和 扎实严谨的底层防护与兜底架构，使 NetWiz 在不同分支和各类魔改固件中表现出众的兼容能力。无论是老旧系统，还是 23.05 之后的新一代 fw4/DSA 架构，皆能适配，稳定运行。

## ✨ 核心特性与优势

### 💻 现代化架构
* **极速加载不卡顿：** 采用最新响应式、弹性架构，告别传统界面的简陋与卡顿，完美适配电脑和手机屏幕，操作如丝般顺滑。
* **严格的权限隔离：** 界面操作与底层系统权限彻底分离。前端不具备直接修改底层配置的权限，所有变更均由受信任的沙箱代理安全执行。
* **优雅的 UI 细节：** 告别烦人的弹窗打扰，版本更新采用简洁的右上角小红点提示，状态一目了然。（暂未启用）
* **原生多语言支持：** 根据您的系统环境，自动切换简体中文、繁体中文或英文界面。
* **兼容众多品牌硬件：** 智能适配多芯片频段硬件，最大化挖掘硬件性能，满血释放 Wi-Fi 信号。

### 🛡️ 全方位的守护
* **安全回退机制：** 配置错误导致无法连接后台？不用怕！应用新配置后会启动 120 秒安全倒计时。LAN 口配置后若无真实的新 IP 访问连接，系统将自动恢复到修改前的配置 **（意外断电重启依然优雅恢复）**。
* **智能防错校验：** 严格并精准拦截“ IP 冲突、信息填错”等高危操作，从源头防止路由死循环。
* **旁路由 / AP 模式自动排雷：** 一键安全切换旁路由或 AP（有线中继）模式。系统会自动帮您关掉冲突服务，智能指引您正确填写信息，绝不破坏现有的家庭网络拓扑，新手也能轻松设置。
* **设备综合大盘：** 掌握所有在线、离线及静态设备的实时动态。
* **流量分析探针：** 悬停即可查看该设备的 P2P 与 Web 连接数分布。
* **全链路灾备：** 随时回滚或导入外部配置文件。

### ⚡ 极致的无感体验
* **WAN 口上网方式智能切换：** 自动识别 WAN 口网线的物理插拔状态并智能适配，完美过滤由拨号失败、软件重启引起的“假性掉线” **（拔插 WAN 口网线间隔十秒，即可触发智能切换机制）**。
* **自动探活，秒级跳转：** 修改 IP 后，前端会静默探测新地址，网络一旦连通立刻瞬间跳转，体验丝滑流畅。
* **改设置不断网：** 在应用部分网络设置时，Wi-Fi 保持稳定不断开，不干扰其他设备的正常上网。
* **双向数据无缝同步：** 在“多频合一”与“分频独立”模式间切换时，Wi-Fi 密码与 SSID 智能双向传递，彻底告别重复输入的烦恼。自带历史配置记忆功能。
* **一键开启 IPv6：** 智能下发 IPv6 地址，告别晦涩难懂的 DHCPv6、SLAAC 和中继设置。轻轻一点，系统即可为设备自动下发公网 IPv6。
* **一键 Wi-Fi 无缝漫游：** 用户无需专业技术，仅需满足两项条件即可拥有多路由器间 Wi-Fi 的自动“丝滑”跳转：Wi-Fi 名称、密码一致，且设备处于同一局域网。**（注意：环境中请勿存在多个 DHCP 服务；若路由器摆放距离较近，建议错开信道，避免同频干扰。）**
* **快速启用无线中继 (WISP)：** 输入上级 Wi-Fi 帐号密码接收信号，并广播您自己的专属 Wi-Fi 网络。

### 📶 强大的无线智控
* **自动适配所有硬件：** 自动接管系统内所有物理无线网卡，无论是单频、双频还是三频（甚至多频）路由器，均能完美适配。
* **修复隐藏故障：** 针对各种残缺、冲突或被带偏的底层配置，自动清理系统中遗留的错误 Wi-Fi 配置，纠正被卡死的网络状态，让无线表现更稳定。
* **智能频宽满血释放：** 告别残血网络！在保存配置时，智能识别硬件极限，静默优化并提升 Wi-Fi 频宽，轻松跑满带宽。

### 🧭 快捷导航
👉 **在 LuCI 一级菜单的最后面（“退出”按钮的前一个），即可直接找到 👉 网络向导**。

---

## 🚀 核心支持的四大模块

1. 🔌 **宽带拨号 (PPPoE)**
   * **适用场景**：光猫为纯桥接模式，由本路由器直接进行宽带拨号上网，承担全屋网络枢纽。
   * **行为**：精准写入宽带账号与密码，剥离多余网关遗留，安全重启底层拨号进程。

2. 📶 **Wi-Fi 设置（无硬件时自动隐藏）**
   * **适用场景**：首次配置无线网络，或 修改全屋 Wi-Fi 名称、密码 及 是否启用无线中继 (WISP)。
   * **行为**：智能接管底层物理芯片并动态渲染界面。支持一键“多频合一”组建全屋智能漫游网，或拆分为独立的 2.4G / 5G / 5G_Game 频段；可以启用兼容旧版古董智能物联设备 **(网速会被拖累、稳定性变差)**；默认开启不同路由器间5G频段的Wi-Fi信号顺滑切换功能。
     
3. 🌐 **二级路由模式 (DHCP / 静态 IP)**
   * **适用场景**：光猫已经负责拨号，或者上级有主路由，本设备作为二级路由或子网段路由接入。
   * **行为**：可自由选择“动态获取”或“静态绑定”，自动接管 WAN 口配置，智能校验网段避免死循环。

4. 🏠 **局域网设置 (主路由 / 旁路由切换)**
   * **适用场景**：仅需修改设备内网管理 IP；或者网络内已有主路由，本设备仅作为辅助网关或旁路由（AP 有线中继）。
   * **行为**：一键开启“旁路由模式”，系统将自动关闭本机 DHCP 服务，并要求必须填写主路由网关；若为主路由，则提示网关留空，不会破坏现有局域网拓扑。

---

## ✨ 设备管理专家核心特性

### ⚡ 终端雷达 & 内核级流量透视 (Connection Radar)
* **实时连接追踪**：深入解析网络连接状态的核心模块，实时捕获终端设备的底层网络连接。
* **智能流量分类**：自动将流量精准分类为 Web/HTTPS、DNS/NTP、UDP 媒体、P2P 高端口下载，并以**直观的动态圆饼图**展示。
* **异常终端预警**：自动识别跨网段设备与疑似伪装 MAC 设备。

### 🏷️ 智能 IP 分组与批量绑定固定 IP (Smart IP Assignment)
* **全自动分类**：精准识别 Mobile（手机 / 平板）、PC（电脑 / 工作站）、IoT（智能家居）。
* **多策略批量下发**：支持选择多个设备，一键执行**顺序分配**、**按设备类型智能分配专属网段**，或分配至**自定义部门 / 房间**。
* **安全防冲突**：内置智能防冲突算法，IP 冲突时自动顺延，杜绝网络瘫痪。

### 🌐 纯血 IPv6 深度支持
* **无感解析**：自动过滤本地链路地址（`fe80`），精准提取公网 IPv6。
* **PC 存活保活机制**：独创的 `v6pc_` 活跃时间戳机制，防止 PC 设备的 IPv6 地址频繁变动导致失联。

### 🛡️ 一键防火墙与访问控制 (Firewall Control)
* **⛔ 断网 (Block)**：一键阻断设备访问外网，保留局域网通信，秒级生效。
* **🛡️ 局域网隔离 (Isolate)**：一键禁止设备访问内网其他设备（防旁路由嗅探、防智能家居隐私泄露）。
* **🚀 DMZ 主机**：一键将特定设备的全部端口暴露至公网（自动互斥校验，防止冲突）。
* **🔌 局域网唤醒 (WOL)**：深度集成，设备离线时自动显示唤醒按钮。

### 📦 灾备级配置管理 (Auto-Backup & Disaster Recovery)
* **无损自动备份**：当网络拓扑发生改变时（如修改 DHCP、防火墙），后台自动计算核心配置文件的 MD5，并在变动时自动生成 `.tar.gz` 备份存档。
* **一键导入 / 导出**：支持将当前所有的静态 IP、黑名单、隔离规则打包下载到电脑，或在刷机后一键从云端 / 本地恢复，恢复后自动唤醒所有高级代理与 DNS 插件。

---

<span id="install"></span>
## 一、🚀 极速安装 (推荐)

我们提供了一键智能安装脚本。无论你是老系统还是新系统，只需在 SSH 终端中直接复制并执行以下单行命令，即可自动完成 **【判断系统架构 -> 下载对应格式 -> 安装 -> 修复权限与清理缓存】** 的全流程：

```bash
if wget -qO /tmp/nw_inst.sh https://raw.githubusercontent.com/huchd0/luci-app-netwiz/master/install.sh; then sh /tmp/nw_inst.sh; else sh /etc/netwiz/custom_pkgs/install.sh; fi
```

💡 **提示**：如果你的网络无法直接访问 GitHub Raw，可以在链接前加上代理加速，例如：
```bash
if wget -qO /tmp/nw_inst.sh https://ghproxy.net/https://raw.githubusercontent.com/huchd0/luci-app-netwiz/master/install.sh; then sh /tmp/nw_inst.sh; else sh /etc/netwiz/custom_pkgs/install.sh; fi
```

---

## 二、🛠️ 手动安装 (离线包)

如果你习惯手动操作，请前往 [Releases 页面] 下载最新的安装包，并使用 WinSCP 将其上传至路由器的 `/tmp/` 目录。

**对于 OpenWrt 25.x 及最新快照版 (`.apk` 格式)：**
上传至 `/tmp/` 目录后，运行以下命令（注意：新版 25.x 由于签名限制，官方界面直接上传安装会报 `Error 99`，优先使用上方的命令行安装）。

**手动上传：**
```bash
apk add --allow-untrusted /tmp/*netwiz*.apk
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* && /etc/init.d/rpcd restart
```
**官方界面上传(不要点安装)：**
```bash
apk add --allow-untrusted /tmp/upload.apk
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* && /etc/init.d/rpcd restart
```
**对于 OpenWrt 23.05 及更早系统 (`.ipk` 格式)：**
以下两种方式任选其一：
1. 网页端：在系统后台使用 “系统 -> 软件包 -> 上传软件包” 正常安装。
2. 命令行：上传至 `/tmp/` 目录后，运行以下命令：
```bash
opkg install /tmp/*netwiz*.ipk
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* && /etc/init.d/rpcd restart
```

## 💡 常见问题 (FAQ)

**Q：安装后点击菜单提示 `HTTP 404` 或 `Object not found (-32000)`？**
A：这是 OpenWrt 系统的权限通行证 (ACL) 和前端缓存机制未更新所致。请在 SSH 中执行彻底清理命令：
```bash
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* && /etc/init.d/rpcd restart
```
**做完后，请务必点击网页右上角“退出登录”，重新输入密码进入后台即可解决。**

**Q：在局域网设置里修改了 IP 后，为什么一直在转圈，打不开网页了？**
A：如果您修改了本机的局域网 IP，点击“确认应用”后底层网络会立刻重置。系统会在几秒后尝试为您自动跳转，如果由于浏览器安全策略未跳转成功，原有的旧 IP 网页将失效。请直接在浏览器地址栏手动输入您新设置的 IP 地址即可恢复访问。

**Q：切换上网方式后无法打开网页，打不开网页了？**
A：通常是因为操作系统的 DNS 缓存没清，请尝试断开电脑/手机的 Wi-Fi 重新连接，或在电脑执行：ipconfig /flushdns。

**Q：🆘 救援指南：进不去后台怎么办**

检查网络连接与手动指定 IP（如果电脑无法自动获取 IP 地址），导致浏览器打不开后台：
* 请确保网线插在路由器的 **LAN 口** 上。
* 将电脑网卡的 IP 获取方式改为“手动/静态 IP”。
* IP 地址设置为：`192.168.100.2`（与路由器同网段的其他地址）。
* 子网掩码设置为：`255.255.255.0`。
* 设置完成后，再次尝试访问路由器后台 `192.168.100.1`。

## Q：🆘 救援指南：构建固件时内置Netwiz，刷后进不去后台怎么办？

如果在刷入固件后遇到无法连接、向导界面异常或无法进入管理后台的情况，请不要紧张，按照以下步骤进行排查与救援：

### 1. 触发隐藏的紧急救援通道 (Netwiz 防卡死机)
如果您已经连接上路由器的网络，但遇到了前端白屏、向导无限循环或界面卡死的问题，可以利用系统内置的防劫持救援通道：
* 请在浏览器中直接输入并访问：`http://192.168.100.1/cgi-bin/luci/rescue`（请将 IP 替换为您的实际路由器默认 IP）。
* 此操作会触发底层的紧急释放指令，强制解除向导的网关劫持，并将您安全地送回官方原生的 LuCI 登录页面。

### 2. SSH 后台命令修复
如果您依然可以通过 SSH 连接路由器（默认端口 `22`），您可以通过命令行手动解除向导锁定并重启网络：
```bash
# 解除向导锁定并恢复原生 LuCI 入口
uci set netwiz.global.configured='1'
uci commit netwiz
[ -f /www/cgi-bin/luci.bak ] && mv -f /www/cgi-bin/luci.bak /www/cgi-bin/luci

# 重启网页服务器与网络服务
/etc/init.d/uhttpd restart
/etc/init.d/network restart
```
---

## 📸 界面预览
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/40905f7e-fa8b-4bc6-8bc8-846f81b3673c" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/6bb6a808-901a-4911-9769-a27ad5700508" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/66a9e97b-c2d1-431f-8981-995f4358b4fa" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/7d056b14-9a88-4d0e-a0ea-2fae7a5f8233" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/2254dffb-bd82-40e0-9d58-0c9f90d60512" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/f2bd9091-2a1d-4b37-9104-3071dbf9d71a" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/01bbdd3a-ab4c-493f-adbd-09a5087f2de4" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/e02aefe9-51f8-4c15-8a93-932b48e4594d" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/52e42b52-11e3-4c61-87e6-17a689451be7" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/d55ff995-4e19-4fca-9059-60779777c4d9" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/a1593cdb-1384-4b78-af35-107fa7ed4f60" />
<img width="680" alt="Image" src="https://github.com/user-attachments/assets/6b3b6aeb-8ed0-4612-a187-c7d8a40b0d67" />

---

## 📄 协议与鸣谢

本项目基于 GPL-3.0 license 开源。

特别感谢 **OpenWrt 开源社区**、**LuCI 框架** 以及 **ImmortalWrt 团队** 提供坚实的基础架构支撑。

---

## ☕ 赞助与支持

如果您觉得这个插件让您的网络配置体验变得更加优雅、省心，欢迎请作者喝杯咖啡，这将是持续维护与更新的最大动力！❤️

<img src="https://github.com/huchd0/openwrt-x86-64-build/blob/master/.github/Donate.jpg" width="680" alt="Donate">

---

[返回顶部](#top)
