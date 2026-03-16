# 更新日志

## [7.0] - 2025-12-05

### 新增
- ✨ 支持 OpenWrt 23.x 版本
- ✨ 支持 OpenWrt 24.x 版本
- ✨ 新增版本兼容层 (`compat.js`)

### 改进
- 🔧 优化 LuCI API 调用，兼容新旧版本
- 🔧 jQuery 依赖改为可选，无 jQuery 环境下自动降级
- 🔧 改进 ubus 调用方式，支持不同版本
- 🔧 优化菜单渲染逻辑，增加空值检查
- 🔧 改进资源加载，添加版本化 URL

### 修复
- 🐛 修复新版本 LuCI 中 `dispatchpath` 未定义问题
- 🐛 修复新版本中 `requestpath` 访问错误
- 🐛 修复无 jQuery 环境下动画失效问题
- 🐛 修复某些元素可能不存在导致的错误

### 技术改进
- 📦 更新 Makefile 版本号到 7.0
- 📦 改进错误处理和边界检查
- 📦 优化代码结构，提高可维护性

## [6.0] - 2023-02-24

### 之前的更新
- 修复安装 package 提示信息背景泛白
- 优化菜单缩放
- 优化显示网口 down 状态显示图标
- 优化 logo 显示
- 新增各设备状态图标显示
- 更换 logo 显示为字体 "OpenWrt"，支持以主机名显示 logo
- 修复部分插件显示 bug
- 修复 vssr 状态 bar
- 修复诸多 bug
- 修复兼容部分插件样式
- 修复 aliyundrive-webdav 样式
- 修复 vssr 在 iOS/iPadOS WebApp 模式下显示异常
- 修复 openclash 插件在 iOS/iPadOS WebApp 模式下 env(safe-area-inset-bottom) = 0
- 优化菜单 hover action 状态分辨
- 支持 luci-app-wizard 向导菜单
- Update header box-shadow style
- Update uci-change overflow
- Fix nlbw component
- Added QSDK/QWRT wizard and iStore menu icon fonts
