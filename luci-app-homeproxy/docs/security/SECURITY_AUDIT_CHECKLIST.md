# HomeProxy 安全修复审核清单

**审核分支**: `security-fixes-20260614`
**提交范围**: `custom/homeproxy-enhancements..security-fixes-20260614`（共 6 轮复核，提交数以 `git log` 为准）
**修复项目**: 20/20 全部完成
**详细文档**: 见 `SECURITY_FIXES_IMPLEMENTATION.md`

---

## ✅ 必须审核的安全关键修复

### 1. 命令注入 RCE (U-H1) - Critical
**文件**: `root/usr/share/rpcd/ucode/luci.homeproxy:800`
- [ ] 确认 `shellquote()` 函数正确包裹用户输入
- [ ] 测试特殊字符（`; $ | & ` 等）是否被正确转义

### 2. 安装脚本信任链 (C-H1) - Medium
**文件**: `install.sh`
- [ ] 确认公钥指纹硬编码且正确
- [ ] 确认 fallback 路径先验证签名再安装
- [ ] 确认移除了 `--allow-untrusted` 标志

### 3. RPC 权限边界 (C-M1) - Medium
**文件**: `root/usr/share/rpcd/acl.d/luci-app-homeproxy.json`
- [ ] 确认 read 权限只包含 3 个只读方法
- [ ] 确认 write 权限包含所有写入方法
- [ ] 确认没有遗漏的方法

### 4. 路径穿越 (N-M1) - Medium
**文件**: `root/usr/share/rpcd/ucode/luci.homeproxy:871`
- [ ] 确认白名单只包含 4 个资源类型
- [ ] 测试非白名单类型是否被拒绝

### 5. 备份完整性校验 (C-M3) - Low
**文件**: `root/usr/share/rpcd/ucode/luci.homeproxy`
- [ ] 确认 SHA-256 计算逻辑正确
- [ ] 确认恢复时验证逻辑完整
- [ ] 测试篡改备份文件是否能被检测

---

## ✅ 需要功能测试的修复

### 6. 临时文件随机化 (C-L1)
**测试步骤**:
1. [ ] WebUI 生成备份 → 检查文件名是否随机
2. [ ] 上传备份文件 → 检查路径是否随机
3. [ ] 恢复备份 → 检查功能是否正常
4. [ ] 多次备份 → 确认文件名不冲突

### 7. 服务验证回滚 (C-L2)
**测试步骤**:
1. [ ] 恢复正常备份 → 服务应正常启动
2. [ ] 恢复损坏配置 → 应自动回滚
3. [ ] 检查回滚后配置是否恢复

### 8. Clash API 资源限制 (C-H2, C-L4)
**测试步骤**:
1. [ ] 并发 65 个连接 → 第 65 个应被拒绝
2. [ ] 发送超大请求 (>256KB) → 应断开连接
3. [ ] 保持连接 idle 超过 30 秒 → 应超时断开

---

## ✅ 代码质量审核（可选）

### 9. 代码重构 (2.11-2.13, 2.15)
- [ ] `generate_outbound` 拆分是否合理
- [ ] 表单字段工厂函数是否可用
- [ ] 错误收集机制是否完整
- [ ] Clash API 注释是否清晰

### 10. CI/CD 优化 (2.16-2.17)
- [ ] apk-tools 缓存是否生效
- [ ] 语法检查是否正常运行
- [ ] 私钥清理 trap 是否正确

---

## 🔍 快速验证命令

```bash
# 1. 检查关键文件修改（相对主分支的完整改动）
git diff custom/homeproxy-enhancements..security-fixes-20260614 --stat

# 2. 查看 shellquote 使用
grep -n "shellquote" root/usr/share/rpcd/ucode/luci.homeproxy

# 3. 查看 ACL 配置
cat root/usr/share/rpcd/acl.d/luci-app-homeproxy.json | jq .

# 4. 查看资源类型白名单
grep -A5 "allowed_types" root/usr/share/rpcd/ucode/luci.homeproxy

# 5. 验证语法
sh -n install.sh
node --check htdocs/luci-static/resources/view/homeproxy/backup.js
node --check htdocs/luci-static/resources/view/homeproxy/client.js
# ucode 脚本（node 仅做基础语法检查，ucode≠ESM，不能替代真机或 ucode -c）
node --check --input-type=module < root/etc/homeproxy/scripts/generate_client.uc
node --check --input-type=module < root/etc/homeproxy/scripts/clash_api_proxy.uc
sed 's/^return /export default /' root/usr/share/rpcd/ucode/luci.homeproxy | node --check --input-type=module
```

---

## 📋 审核通过标准

- [ ] 所有 5 个安全关键修复已审核通过
- [ ] 功能测试 3 项通过（C-L1, C-L2, C-H2/C-L4）
- [ ] 快速验证命令无错误
- [ ] 代码风格符合项目规范
- [ ] 无明显的逻辑错误或遗漏

---

## 🚀 审核通过后操作

```bash
# 1. 合并到主分支
git checkout custom/homeproxy-enhancements
git merge security-fixes-20260614 --no-edit

# 2. 推送到远程
git push origin custom/homeproxy-enhancements

# 3. 触发 CI 构建
# GitHub Actions 会自动运行

# 4. 等待 CI 完成后创建 Release
```

---

**审核人**: _______________
**审核日期**: _______________
**审核结果**: [ ] 通过  [ ] 需要修改
**备注**: _______________
