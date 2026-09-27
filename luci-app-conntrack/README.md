<img width="750" height="400" alt="image" src="https://github.com/user-attachments/assets/fdd8b243-608f-4522-abcc-40ce645c249f" />
<img width="720" height="600" alt="image" src="https://github.com/user-attachments/assets/f1b1d812-2a47-48a2-a9af-5d16d461327a" />

# luci-app-conntrack

[English](#english) | [中文说明](#中文说明)

---

## English

A highly-optimized, lightweight **Realtime Connection Tracking & Network Audit Monitor** for OpenWrt/LEDE. This plugin provides single-direction (TX/RX split), high-frequency, millisecond-level traffic visualization directly within the LuCI web interface.

### 🚀 Key Features

* **Zero Kernel Contamination (No kmod):** 
  Unlike legacy traffic accounting tools, it does not inject any custom hooks or proprietary kernel modules. It fully leverages the Linux native `/proc/net/nf_conntrack` subsystem—data that the kernel already maintains for NAT routing—guaranteeing **zero system pollution and maximum stability**.
* **UI Features:**
  * **Realtime Connection Speed:** Displays instant throughput for each traffic direction in real time.
  * **Bit / B Unit Toggling:** Seamlessly switch between `Bit` (bps/Mbps) and `B` (B/s/MB/s) locally via JS without dropping the SSE pipeline.
  * **Original/Reply Traffic Splitting:** Tears apart conntrack rows to display precise directional analytics (TX/RX isolation).
  * **QUIC/HTTP3 Recognition:** Automatically sniffs out modern HTTP/3 streams via UDP 443 heuristic auditing.
  * **IPv4/v6 double stacks** supported.
  * **Adaptive Layout with Tooltips:** Prevents UI breakage from long IPv6 addresses using CSS ellipsis combined with native hover tooltips.
  * **Specific IP / Local & Loopback IP filter** supported.
  * **Local host name** supported.
  * **GeoIP info** supported.
  * **Experiment feature** Show app name(YouTube, Instagram, TikTok, etc.) associated with the connection, this will need to patch kmod-nf-conntrack (patch file: 999-netfilter-custom-payload-telemetry-nf_conntrack.patch).
  * **Cutomized App Icons***
    
### 🛠️ Architecture & Directory Tree

Conforms strictly to the `luci.mk` unified application build framework:

```text
luci-app-conntrack/
├── Makefile                # Build script using feeds/luci/luci.mk
├── luasrc/
│   ├── controller/
│   │   └── conntrack.lua   # Non-blocking Event-Stream (SSE) backend server
│   └── view/
│       └── conntrack/
│           └── conntrack.htm # Vanilla JS dynamic reconnect frontend view
└── po/
    └── zh-cn/
        └── conntrack.po    # I18n translation source file
```

### 🧱 Installation & Compilation

```bash
# Update compilation feeds
./scripts/feeds update -i
./scripts/feeds install -f luci-app-conntrack

# Compile the package independently
make package/feeds/luci/luci-app-conntrack/compile V=s
```

---

## 中文说明

一款为 OpenWrt/LEDE 深度定制、工业级稳定的**实时连接跟踪与单向流量审计看板**。该插件完全基于轻量级的 Event-Stream (SSE) 长连接架构下运行，无需刷新页面即可在 Web 界面实现真正高频、正反向物理隔离的网络吞吐审计。

### 🚀 核心优势

* **零内核污染 (无需 kmod)：** 
  不同于传统流量统计插件需要往内核安插臃肿的探针或第三方驱动，本插件完全基于 Linux 内核原生维护的 `/proc/net/nf_conntrack`（连接跟踪表）作为数据源。对系统内核**零开销、零污染**，保障极限负载下的系统稳定性。
* **UI 特性：**
  * **实时连接速率：** 高频显示每一条活跃网络连接当前的实时瞬时物理吞吐速率。
  * **前端零延迟单位切换：** 表头集成智能交互按钮，支持在 `Bit`（比特率，Mbps）和 `B`（字节率，MB/s）之间 1 毫秒无缝切换，无需掐断或重启后台长连接。
  * **正反单向流量分离：** 将 conntrack 报文拆分为 Original（发起方）与 Reply（回应方），实现真正的单向 TX/RX 独立审计与降序排列。
  * **QUIC / HTTP3 智能识别：** 基于启发式行为审计，自动将隐藏在 UDP 443 端口下的现代高并发视频/下载流标记并显示为 `QUIC` 协议。
  * **IPv4/v6 双栈支持**
  * **超长 IPv6 弹性布局：** 引入 CSS 精确截断裁切，使超长 IPv6 地址自动变为省略号，鼠标悬停时原生 Tooltip 气泡自动浮现完整内容，排版永不撑破。
  * **手动指定IP或本地以及回环IP 过滤支持**
  * **本地主机名显示支持**
  * **地理IP信息显示支持**
  * **实验特色** 显示与连接相关的应用名称(YouTube, Instagram, TikTok, 王者荣耀..), 你需要给内核模块 kmod-nf-conntrack 打补丁 (补丁文件: 999-netfilter-custom-payload-telemetry-nf_conntrack.patch).
  * ** 定制化App图标库 **
    
### 🧱 依赖与安装

本插件在 OpenWrt 源码树下的标准相对路径为 `package/feeds/luci/luci-app-conntrack`：

```bash
# 1. 刷新编译环境 feeds 映射
./scripts/feeds update -i
./scripts/feeds install -f luci-app-conntrack

# 2. 单包高效构建 
make package/feeds/luci/luci-app-conntrack/compile V=s
```
