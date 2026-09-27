# luci-app-dlna-player

> 把 OpenWrt 设备（尤其是 x86 小主机）变成一台 **DLNA 音乐播放器** —— 自动探测声卡、配置 MPD 播放、支持手机投送。

> 🤖 **本插件由 AI 编写**（从需求梳理、代码实现到调试排错，全程由 AI 完成）。

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

## ✨ 特性

- 🔍 **声卡自动探测** —— 无需手动找 `hw:X,Y`，自动识别模拟输出设备
- 🔊 **自动解除静音** —— ALSA 新装默认静音，脚本自动处理
- 🎵 **MPD 自动配置** —— 自动生成可用的 `mpd.conf`
- 📡 **DLNA 投送** —— 手机（网易云 / QQ音乐 / BubbleUPnP）直接投送
- 🎚️ **实时音量 / 进度滑块** —— 网页上直接拖动调节
- 🔍 **音乐库搜索** —— 歌曲多了也能快速找到
- 🔁 **播放模式** —— 循环 / 随机 / 顺序播放
- 💾 **持久化音量** —— 绕过 tmpfs，重启后音量不丢
- 🌏 **中文界面** —— 内置翻译，开箱即用
- 🔄 **完整开机自启** —— 服务顺序自动编排

## 📋 适用场景

- x86 小主机 / 软路由装了 OpenWrt，想用它的 **3.5mm 音频口**放歌
- 想把 OpenWrt 变成一台 **DLNA 音箱**
- 树莓派等带音频输出的设备

## 📦 安装

在 OpenWrt 源码根目录执行：

```bash
# 1. 进入 package 目录，克隆插件
cd package
git clone https://github.com/sakura-builder1/luci-app-dlna-player.git

# 2. 回到源码根目录
cd ..

# 3. 更新一下 feeds（首次编译需要）
./scripts/feeds update -a && ./scripts/feeds install -a

# 4. 只编译这个插件
make package/luci-app-dlna-player/compile V=s
```

编译产物在：

```
bin/packages/<架构>/base/luci-app-dlna-player_*.ipk
```

例如 x86_64：

```
bin/packages/x86_64/base/luci-app-dlna-player_1.0.0-r5_all.ipk
```

把它拷到路由器上安装：

```bash
scp bin/packages/x86_64/base/luci-app-dlna-player_*.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
opkg install /tmp/luci-app-dlna-player_*.ipk
/etc/init.d/rpcd restart          # 重要！否则菜单不显示
```

> 💡 依赖会自动带上（mpd-full / upmpdcli / alsa-utils / 常见声卡驱动），不用手动选。

安装后在 **服务 → DLNA 音乐播放器** 里配置使用。

## ⚙️ 配置项

配置文件：`/etc/config/dlna-player`

```uci
config audio 'main'
	option enabled '0'              # 是否启用（默认关闭）
	option device ''                # 声卡设备，留空=自动探测（如 hw:3,0）
	option music_dir '/srv/music'   # 音乐目录
	option volume '40'              # 默认音量 0-100
	option dlna_name ''             # DLNA 显示名，留空=用主机名
	option unmute '1'               # 自动解除 ALSA 静音
	option persist_volume '1'       # 持久化音量
```

修改后应用：

```bash
uci set dlna-player.main.volume='60'
uci commit dlna-player
/etc/init.d/dlna-player start
```

## 🏗️ 工作原理

```
启动流程：
  S50 dlna-player          → 探测声卡 + 修权限 + 解静音 + 生成 mpd.conf + 建目录
  S93 mpd                  → 启动 MPD（以 root 运行）
  S94 dlna-player-volume   → 设置默认音量（有持久状态则跳过）
  S95 upmpdcli             → 启动 DLNA 服务

播放链路：
  手机 App ──DLNA──▶ upmpdcli ──MPD协议──▶ MPD ──ALSA──▶ 声卡 ──▶ 🎵
```

<img width="2191" height="1249" alt="image" src="https://github.com/user-attachments/assets/a1da170e-ccb9-431b-a01e-f13b0502f0a3" />


## 🔧 兼容性

| OpenWrt 版本 | 状态 |
|---|---|
| 24.10 | ✅ 已测试 |
| 23.05 | ⚠️ 理论可用，未测试 |
| 25.12 | ⚠️ 需要适配 `apk` |

## 📄 License

GPL-3.0

本项目采用 **GNU General Public License v3.0** 授权 —— 你可以自由使用、修改、分发，
但**衍生作品必须同样以 GPL-3.0 开源**，不能闭源独吞。
