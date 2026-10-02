# Testing — luci-app-substore

## 单元测试
`tests/` 下每个测试文件均可独立运行，全部为纯 Lua 5.1：

| 测试文件 | 覆盖内容 |
|---------|---------|
| `run_tests.lua` | util(base64/json/url/hostport)、node、parser 基础 |
| `node_*_test.lua` | 节点模型扩展、分组、重命名 |
| `output_clash_meta_test.lua` | Clash.Meta / Mihomo YAML 生成 |
| `output_formats_test.lua` | 15 种目标格式统一分发 |
| `output_full_config_test.lua` | sing-box / V2Ray 完整配置输出 |
| `vmess_cipher_test.lua` | vmess 加密方式（cipher）与 TLS 层（security）不混淆 |
| `core_link_test.lua` | 订阅 token + generate_link 链接生成 |
| `parser_clash_yaml_test.lua` | Clash YAML 解析 |
| `parser_json_config_test.lua` | sing-box / V2Ray / Clash JSON 解析 |
| `parser_input_test.lua` | 多客户端配置导入（sing-box/V2Ray/Surge/QX） |
| `parser_local_link_test.lua` | 局域网订阅链接检测与解析 |
| `singbox_transport_test.lua` | sing-box `transport` 对象（ws / grpc / http / httpupgrade）读取 |
| `list_lock_test.lua` | 订阅列表 `mkdir` 互斥锁、陈旧锁回收、可重入 |
| `qx_tag_comma_test.lua` | QX 节点名含逗号时的整条丢弃 |
| `dns_fallback_test.lua` | DNS 解析回退（nixio → nslookup）与连接时对端地址校验；**wget 后端在无法校验时拒绝** |
| `parser_mixed_format_test.lua` | 混合格式文本导入：明确报错（7 种组合）+ 单一格式不误判（Surge `[Proxy]` / Clash YAML / sing-box JSON / YAML 流式映射）+ 远程 `M.parse` 行为未变 |
| `acl_menu_test.lua` | 菜单 ACL 接线：ACL 组定义、`depends.acl` 引用同一组名、Makefile 确实安装 acl.d / menu.d |
| `data_integrity_test.lua` | 写入失败被上报而非吞掉（`M.remove` / `M.ensure_token` 注入 `atomic_write` 失败） |
| `subscriptions_format_gate_test.lua` | 订阅列表页格式下拉的启用条件（真实渲染模板后断言） |
| `subscriptions_bulk_delete_test.lua` | 订阅列表页勾选批量删除：选择框列 / 全选 / 删除按钮 / 空选不删（真实渲染模板后断言） |
| `user_agent_test.lua` | 订阅客户端类型（User-Agent）：取值校验、`-A`/`-U` 进入命令行、重定向每一跳带 UA、预设解析、core 透传、控制器接线 |
| `core_combo_test.lua` | 组合订阅：合并/重算、来源校验、**删除源订阅后组合立刻重算**（节点/下载链接/来源剪除/来源删光的报错/无关组合不受影响） |

运行全部：`for f in tests/*.lua; do lua5.1 "$f" || exit 1; done`

## 集成测试
1. 编译安装到目标设备
2. 添加订阅 URL，手动更新，验证节点数
2.1 订阅列表勾选批量删除：表头全选 / 单条勾选、一条都没勾选时点「删除」不删除任何东西、
   多条一次删除、删除后 `/etc/cron.d/substore` 同步刷新
2.2 组合订阅随源删除重算：建 A+B 组合 → 删除 A → 组合节点数立刻只剩 B 的、
   「来源」列不再出现裸 id、组合下载链接不再含 A 的节点；把来源删光时组合报错而非静默 0 节点
2.3 混合格式文本导入：粘贴「URI 行 + WireGuard `.conf`」的混合文本 → **明确报错**并
   列出两种格式，而不是只导入一半；再分别单独导入两种格式，均应成功
2.4 部分删除失败时 cron 同步：构造一条删除会失败的订阅（如手工改坏 nodes 文件名），
   与一条正常订阅一起勾选删除 → 至少一条被删掉时 `/etc/cron.d/substore` **必须**被重写
3. 节点浏览：筛选、排序
4. 输出生成：15 种格式下拉均可生成
5. 订阅链接：复制 `/substore/download?token=...&target=ClashMeta` 到 Passwall/OpenClash 验证可拉取
6. 输入源：导入 Clash YAML / sing-box JSON / V2Ray JSON / Surge / QX 配置验证解析
7. 定时更新：修改 Settings cron，验证 `/etc/cron.d/substore` 生成
8. 规则应用：设置协议过滤、关键词，验证节点列表/输出受影响
9. **ACL** —— ✅ **已于 2026-10-02 在设备上实测通过**：新建一个非 root 的 LuCI 用户
   （不在 `luci-app-substore` 组内），登录后**看不到**本应用入口；把该用户加入组后
   入口**出现**；该用户**直接访问 URL**
   （`/cgi-bin/luci/admin/services/substore/list`）返回 **403 Forbidden**
   （依据：ucode dispatcher 在 `dispatch()` 里对路径上累积的 `depends.acl` 做校验，
   不足即 403 —— 已从上游源码核实，并已由本次设备实测确认）
10. **表单 token**：提交任一写操作（保存订阅 / 删除 / 节点保存）应正常生效；
    手工构造一个缺 `token` 或 token 不匹配的 POST，应看到**错误提示**而不是静默无反应

## 安全测试
- SSRF：尝试内网 URL，被拒绝
- 大响应：>10MB 被截断
- 恶意 Base64/JSON：解析失败不崩溃

## 回归测试
每次阶段发布前执行 `tests/run_tests.lua` 并在目标设备手动验证菜单/功能。
