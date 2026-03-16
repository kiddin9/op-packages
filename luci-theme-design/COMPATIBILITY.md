# 版本兼容性说明

## 支持的 OpenWrt 版本

本主题已针对以下 OpenWrt 版本进行优化和测试：

- ✅ **OpenWrt 21.x** - 完全支持
- ✅ **OpenWrt 23.x** - 完全支持  
- ✅ **OpenWrt 24.x** - 完全支持

## 主要兼容性改进

### 1. LuCI API 兼容
- 兼容新旧版本的 `L.env.dispatchpath` 和 `L.env.requestpath`
- 支持不同版本的 ubus 调用方式
- 自动检测并适配 LuCI 版本

### 2. JavaScript 依赖
- jQuery 可选：在没有 jQuery 的环境下使用原生 JavaScript
- 动画效果降级：无 jQuery 时使用 CSS 过渡
- 兼容层自动检测运行环境

### 3. 资源加载
- 版本化资源 URL，避免缓存问题
- 兼容不同版本的资源路径结构

## 已知问题

### OpenWrt 23/24 特定问题
1. 某些第三方插件可能需要单独适配
2. 如果遇到菜单显示问题，请清除浏览器缓存

## 测试建议

编译安装后，请测试以下功能：
- [ ] 登录界面显示正常
- [ ] 主菜单展开/收起
- [ ] 移动端响应式布局
- [ ] 深色模式切换
- [ ] 各插件页面样式

## 反馈问题

如果在特定版本遇到问题，请提供：
1. OpenWrt 版本号
2. LuCI 版本号
3. 浏览器类型和版本
4. 具体问题截图

## 技术细节

### 兼容层实现
主题包含 `compat.js` 兼容层，自动检测 LuCI 版本并提供统一接口。

### 版本检测
```javascript
// 检测是否为新版本 LuCI (23+)
if (L.env.luci_version) {
    var majorVersion = parseInt(L.env.luci_version.split('.')[0]);
    var isNewVersion = majorVersion >= 23;
}
```

### jQuery 降级
当 jQuery 不可用时，自动使用原生 DOM API：
- `$(el).slideUp()` → `el.style.display = 'none'`
- `$(el).css()` → `el.style.property = value`
