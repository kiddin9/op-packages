# Testing — luci-app-substore

## 单元测试
`tests/` 下每个测试文件均可独立运行，全部为纯 Lua 5.1：

| 测试文件 | 覆盖内容 |
|---------|---------|
| `run_tests.lua` | util(base64/json/url/hostport)、node、parser 基础 |
| `converter_*_test.lua` | 协议转换、URL 模板渲染 |
| `node_*_test.lua` | 节点模型扩展、分组、重命名 |
| `output_clash_meta_test.lua` | Clash.Meta / Mihomo YAML 生成 |
| `output_formats_test.lua` | 13 种目标格式统一分发 |
| `core_link_test.lua` | 订阅 token + generate_link 链接生成 |
| `parser_clash_yaml_test.lua` | Clash YAML 解析 |
| `parser_json_config_test.lua` | sing-box / V2Ray / Clash JSON 解析 |
| `parser_input_test.lua` | 多客户端配置导入（sing-box/V2Ray/Surge/QX） |
| `parser_local_link_test.lua` | 局域网订阅链接检测与解析 |

运行全部：`for f in tests/*.lua; do lua5.1 "$f" || exit 1; done`

## 集成测试
1. 编译安装到目标设备
2. 添加订阅 URL，手动更新，验证节点数
3. 节点浏览：筛选、排序
4. 输出生成：13 种格式下拉均可生成
5. 订阅链接：复制 `/substore/download?token=...&target=ClashMeta` 到 Passwall/OpenClash 验证可拉取
6. 输入源：导入 Clash YAML / sing-box JSON / V2Ray JSON / Surge / QX 配置验证解析
7. 定时更新：修改 Settings cron，验证 `/etc/cron.d/substore` 生成
8. 规则应用：设置协议过滤、关键词，验证节点列表/输出受影响

## 安全测试
- SSRF：尝试内网 URL，被拒绝
- 大响应：>10MB 被截断
- 恶意 Base64/JSON：解析失败不崩溃

## 回归测试
每次阶段发布前执行 `tests/run_tests.lua` 并在目标设备手动验证菜单/功能。
