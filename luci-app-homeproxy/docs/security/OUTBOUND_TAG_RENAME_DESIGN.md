# 出站 Tag 可读化设计

> 目标: 让 MetaCubeXD / YACD / Clash API 看到真实节点名,而不是 `cfg-<section>-out`。

| 项目 | 内容 |
|---|---|
| 状态 | 已实现,待审核 |
| 日期 | 2026-06-19 |
| 分支 | `custom/homeproxy-enhancements` |
| 第一约束 | 最小入侵,上游升级友好 |
| 去重策略 | section id 字典序排序 + 先到先得(最小 section id 保留原名,其余加稳定后缀) |
| 涉及文件 | `outbound_tag.uc`、`generate_client.uc`、`luci.homeproxy_tcping` |
| 明确不改 | `clash_api_proxy.uc`;前端 `node.js`(按 label / section 展示,不读 runtime tag) |

## 1. 问题与目标

HomeProxy 的 UCI section id 在节点创建时由 `md5(label)` 生成。`generate_client.uc` 当前用 section id 拼出运行时 tag:

```ucode
tag: 'cfg-' + node['.name'] + '-out'
```

所以用户看到的是:

```text
label = 🇺🇸us.CDN
tag   = cfg-6f330f9c9c5ec2427b4cd7d588aab6df-out
```

目标:

1. 最终 sing-box / Clash API 中的节点 outbound tag 使用当前 `label`。
2. `label` 改名后,下次生成配置时 tag 跟随变化。
3. 重名、空名、保留名冲突时自动处理,且结果稳定。
4. 不改 UCI section id,不新增 UCI 字段。
5. 不在 `generate_client.uc` 里逐处改 `cfg-...-out` 拼接逻辑。

## 2. 方案选择

采用 **rename pass**:

1. `generate_client.uc` 继续按现有逻辑生成完整 config,内部引用仍先保持 `cfg-<section>-out`。
2. 写盘前通过独立模块 `outbound_tag.uc` 构建 `cfg-<section>-out -> final_tag` 映射(按 section id 排序做确定性去重,见 4.1)。
3. 对整份 config 做递归等值替换。
4. `luci.homeproxy_tcping` 使用同一个映射函数查真实 tag。

这样最终产物与“源头直接生成 label tag”一致,但上游核心生成逻辑几乎不动。

否决项:

| 方案 | 否决原因 |
|---|---|
| 改 UCI section id 为 label | label 可能含 emoji/中文/空格/符号,不适合作 UCI section name,且会破坏历史引用 |
| 逐处把 `cfg-...-out` 改成 helper | 触点多,容易漏掉反解、递归、selector/urltest、detour、DNS/ruleset 引用 |
| 只改 `clash_api_proxy.uc` 展示层 | 真实 sing-box tag 不变,WebSocket/SSE/日志/直连 API/tcping 仍会看到旧 tag |

## 3. 已确认约束

### 3.1 rename pass 不会破坏内部反解

`generate_client.uc` 里存在 `/^cfg-(.+)-out$/` 反解逻辑,但它运行在 config 写盘之前,处理的是 UCI 字段或中间计算值。rename pass 发生在所有配置生成完成后,所以不影响这些反解逻辑。

### 3.2 必须全局去重

`node` 和 `routing_node` 的 label 唯一性是分表校验,两张表之间可以同名。两者又都可能生成 visible outbound tag,所以 final tag 必须在同一个命名空间里去重。

重名的真实来源(说明为何 `node` 表也要参与去重):

1. **手动改名**: section id 在创建时由 `md5(label)` 定死,之后不随 `label` 变化。用户在 LuCI 手动编辑某节点 `label`,可能与另一节点当前 `label` 撞车,于是同一张 `node` 表里出现“同 label、不同 section id”。
2. **跨表同名**: `node` 与 `routing_node` 之间。
3. **分组之间**: 多个 `routing_node` 之间。

> 同一订阅导入流程内不会产生同 label 共存——因为 section id = `md5(label)`,同名会落到同一 section(后者覆盖 / 跳过),这部分见 6.1。

### 3.3 `routing_node` 只纳入会生成自身 tag 的项

只纳入:

```text
enabled == '1' && node in ['selector', 'urltest']
```

原因:

| `routing_node.node` | 运行时产物 |
|---|---|
| `urltest` | 生成 `cfg-<routing_node>-out` |
| `selector` | 生成 `cfg-<routing_node>-out` |
| 普通节点 section | 只生成被引用节点的 `cfg-<node>-out`,不生成 routing_node 自身 tag |

如果把所有 `routing_node` 都纳入去重,未启用或直引用型分组可能导致节点 tag 被无意义地加后缀。

### 3.4 ShadowTLS 必须显式映射

当前中间层 tag 是:

```ucode
const shadowtls_tag = tag + '-shadowtls';
```

当旧主 tag 是 `cfg-<section>-out` 时,中间层为 `cfg-<section>-out-shadowtls`。递归替换必须新增一条完整映射:

```text
cfg-<section>-out            -> final_tag
cfg-<section>-out-shadowtls  -> final_tag + '-out-shadowtls'
```

不能依赖子串替换。中间层仍以 `-out-shadowtls` 结尾,所以 `clash_api_proxy.uc` 的隐藏逻辑可保持 0 改动。

### 3.5 `luci.homeproxy_tcping` 必须同步

`luci.homeproxy_tcping` 直连 `clash_api_external_controller` 对应的真实 sing-box Clash API,不经过 `clash_api_proxy.uc`。它当前硬编码 `cfg-<section>-out`,tag 改名后必须用共享映射查 final tag。

### 3.6 空 label 必须回退

`removeBlankAttrs()` 会删除空字符串字段。若 tag 被映射成空字符串,最终 outbound 会丢失 `tag` 字段。因此:

```text
空 label -> cfg-<section>-out
```

rename pass 必须在 `removeBlankAttrs(config)` 之前执行。

## 4. 实现规格

### 4.1 `outbound_tag.uc`:新增共享映射模块

新增导出函数:

```ucode
export function build_outbound_tag_map(uci) { ... }
```

该模块安装为 `/etc/homeproxy/scripts/outbound_tag.uc`,自包含,不依赖 `homeproxy.uc`,以降低核心公共工具文件的上游合并冲突。

调用方负责先加载 `homeproxy` UCI。函数返回:

```text
{ section_id: final_tag }
```

函数内部约定(固定不变,便于两个进程复现同一结果):

- 使用 `uciconfig = 'homeproxy'`、section type `'node'` 与 `'routing_node'`、读取字段 `cfg.label`。
- 调用方只需保证已 `uci.load('homeproxy')`(generate_client 与 tcping 均已加载)。

收集范围:

1. 全部 `node` section。
2. 仅当 `routing_mode == 'custom'` 时,收集 `enabled == '1' && node in ['selector', 'urltest']` 的 `routing_node` section。

#### 4.1.1 sanitize(label)

final tag 原样采用 `label`:sing-box 与 Clash 系面板均支持 UTF-8,emoji / 中文 / 空格 / `+` / `.` / `#` 等可直接作为 tag。tcping 与 `clash_api_proxy.uc` 的 `/group/<name>/delay`、`/proxies/<name>/delay` 路径都已对名字做 urlencode / pathSegment,URL 层安全。

仅做一处最小清洗:**去除控制字符(码位 `< 0x20`)和 `DEL`(`0x7f`)**,避免破坏 JSON 字符串与日志输出。清洗后若为空串,按“空 label”回退。

> 后缀分隔符选用 ` #`(空格 + 井号)。`#` 在 Clash 生态常用作备注分隔,作为显示名可接受;其在 URL 中的 fragment 语义已被上述 urlencode 规避。

#### 4.1.2 确定性去重:section id 排序 + 先到先得

这是保证 generate_client 与 tcping 两个进程结果一致、且增删节点时尽量稳定的核心算法,**必须严格按此实现**:

1. **收集**参与项,每项为 `{ section, label }`(范围见上)。
2. **排序**: 按 `section`(UCI section id 字符串)做**字典序升序**,得到与遍历顺序无关的确定处理次序。
3. **初始化 `used_tags`**: 预占用全部保留 tag 与动态 tag(见 4.2)。
4. **按排序次序逐项分配** final tag:
   - `base = sanitize(label)`;若为空 → `base = 'cfg-' + section + '-out'`,登记入 `used_tags` 后跳过。
   - 若 `base` **命中下列任一冲突条件**,或 `base` 已在 `used_tags` 中 → 改用带后缀形式;否则 `final = base`。
   - 带后缀形式 `final = base + ' #' + substr(section, 0, 6)`;若仍冲突,**逐步增加 section 前缀长度**直到完整 `section`。
   - 若完整 `section` 后缀仍冲突,继续使用确定性数字兜底:`base + ' #' + section + '-2'`、`-3`...直到无冲突。
   - 将 `final` 写入 `used_tags`,并记入返回表。

“先到先得”的含义: 同名 label 的多个 section 中,**section id 字典序最小者最先被处理,拿到无后缀的 `label`**;其余同名项发现已被占用,各自加 `#<自己 section 前缀>`。因此每个 section 的 final tag 只取决于(它自己的 label、它自己的 section id、是否存在字典序更小的同名 section),增删无关节点不改变结果。

冲突条件(命中即必须加后缀):

| 条件 | 说明 |
|---|---|
| `base` 已被 `used_tags` 占用 | 涵盖重名、撞保留 tag、撞动态 tag |
| 匹配 `^cfg-.+-out$` | 避免落回旧 outbound 命名空间 |
| 匹配 `^cfg-.+-out-shadowtls$` | 避免与 ShadowTLS 中间层旧命名空间重叠 |
| 匹配 `^cfg-.+-dns$` | 避免落入内部 DNS server 命名空间 |
| 匹配 `^cfg-.+-rule$` | 避免落入内部 rule_set 命名空间 |
| 以 `-out-shadowtls` 结尾 | 同上,防御性 |

后缀使用 `section` 前缀,不再对 `section` 做二次 `md5()`:订阅节点的 section 本身已是稳定 md5,手动分组 section 也足够稳定。

### 4.2 保留 tag 占用集

初始化 `used_tags` 时必须预占用固定 tag 和动态 tag。这样即使用户把节点 label 命名成这些值,也会自动加后缀。

固定 tag:

```text
direct-out
block-out
GLOBAL
any
main-out
main-udp-out
default-dns
system-dns
main-dns
china-dns
dns-in
mixed-in
redirect-in
tproxy-in
tun-in
direct-domain
proxy-domain
geoip-cn
geosite-cn
geosite-noncn
__homeproxy_delay_test__
```

如果未来代码新增固定 tag,也应加入占用集。

动态 tag:

```text
cfg-<dns_server_section>-dns
cfg-<ruleset_section>-rule
```

这些不是 outbound tag,但最终 JSON 里也会出现为 tag。为了避免跨对象 tag 碰撞,一并预占用。

额外约束:

1. `final tag` 不允许匹配 `^cfg-.+-out$`,避免单次 rename pass 后出现“新 tag 仍落在旧 outbound 命名空间里”的链式映射歧义。
2. `final tag` 不允许匹配 `^cfg-.+-out-shadowtls$`,避免与 ShadowTLS 中间层旧命名空间重叠。
3. `final tag` 不允许以 `-out-shadowtls` 结尾(与 4.1.2 冲突条件一致)。
4. `final tag` 不允许匹配 `^cfg-.+-dns$` / `^cfg-.+-rule$`,把 `cfg-*` 内部 DNS/ruleset 命名空间整体留给 HomeProxy。

> 关于命名空间: sing-box 中 outbound / endpoint 共享同一引用命名空间,而 DNS server、inbound、rule_set 各自独立。严格说把 `*-dns` / `*-in` / `*-rule` 等纳入 `used_tags` 并非全部必需;此处刻意从严预占用,以规避面板展示混淆与未来 sing-box 行为变化,属保守设计,无副作用。

### 4.3 `generate_client.uc`:写盘前 rename pass

新增 import:

```ucode
import { build_outbound_tag_map } from 'outbound_tag';
```

`generate_client.uc` 运行时已有 `/etc/homeproxy/scripts` 模块搜索路径,因此使用模块名导入即可。

在 `removeBlankAttrs(config)` 之前执行:

```ucode
let tag_map = build_outbound_tag_map(uci);
let rename = {};

for (let section in tag_map) {
    let old_tag = 'cfg-' + section + '-out';
    let final_tag = tag_map[section];

    rename[old_tag] = final_tag;
    rename[old_tag + '-shadowtls'] = final_tag + '-out-shadowtls';
}

rename_tags(config, rename);

/* 防御性: rename 后断言 outbound/endpoint tag 全局唯一。
 * 正常情况下 4.1.2 的去重已保证唯一,此处仅兜底,避免万一的 bug
 * 把含重复 tag 的非法配置写盘、覆盖掉上一份可用配置。 */
assert_unique_outbound_tags(config);   /* 命中重复 → reportError */

if (hasErrors()) {
    warn('HomeProxy 配置验证发现以下问题:\n\n' + formatErrors());
    warn('为避免用无效配置覆盖当前可用配置,本次未写入新配置。\n');
    exit(1);
}

system('mkdir -p ' + RUN_DIR);
writefile(RUN_DIR + '/sing-box-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
```

`rename_tags()` 必须是递归等值替换:

```ucode
function rename_tags(value, rename) {
    let t = type(value);

    if (t === 'object') {
        for (let k in value)
            value[k] = rename_tags(value[k], rename);
        return value;
    }

    if (t === 'array')
        return map(value, (v) => rename_tags(v, rename));

    if (t === 'string')
        return (value in rename) ? rename[value] : value;

    return value;
}
```

`assert_unique_outbound_tags()` 收集 `outbounds[].tag` 与 `endpoints[].tag`,发现重复即 `reportError`,交由既有 `hasErrors()` 流程拦截:

```ucode
function assert_unique_outbound_tags(config) {
    let seen = {};
    let all = [ ...(config.outbounds || []), ...(config.endpoints || []) ];

    for (let o in all) {
        let t = (type(o) === 'object') ? o.tag : null;
        if (t == null)
            continue;
        if (seen[t])
            reportError('error',
                sprintf('rename 后出现重复 outbound tag: %s', t),
                '通常意味着去重算法异常;请附带节点 label / section 列表反馈');
        seen[t] = true;
    }
}
```

要求:

1. 只替换与 key 完全相等的字符串,禁止子串替换。
2. 自动覆盖 `outbounds[].tag`、WireGuard `endpoints[].tag`、selector/urltest 成员、`default`、`detour`、`download_detour`、`route.final`、`route.rules[].outbound`、DNS `detour`。
3. 不替换 `cfg-<section>-dns`、`cfg-<section>-rule`、内置 tag、`__homeproxy_delay_test__`。
4. rename pass 之后必须**仍能再次拦截错误**:做一次 final outbound / endpoint tag 唯一性断言,命中重复则 `reportError` 并在写盘前 `hasErrors()` 复检,沿用既有“绝不用坏配置覆盖好配置”策略。

已知权衡:

- 全局递归等值替换是刻意选择的低入侵方案,避免逐字段改生成逻辑时漏掉 selector/urltest、detour、rule_set download_detour、DNS detour 等引用。
- 它只做**完整字符串相等**替换,不做 JSON 字符串级子串替换,因此不会把 `cfg-xxx-out-shadowtls` 误改成 `label-shadowtls`。
- 低概率风险:若某个非 tag 字段的值刚好完整等于旧 tag(例如密码、SNI、header、path 为 `cfg-<section>-out`),也会被替换。当前接受此 trade-off;若未来出现真实误伤,再评估改为字段白名单替换。

### 4.4 `luci.homeproxy_tcping`:复用映射

把 4 处 `'cfg-' + section + '-out'` 改为:

```ucode
import { build_outbound_tag_map } from '/etc/homeproxy/scripts/outbound_tag.uc';

let tag_map = build_outbound_tag_map(hpuci);

function nodeTag(tag_map, section) {
    return tag_map[section] || ('cfg-' + section + '-out');
}
```

导入方式需要真机验证:

1. 首选与生成器一致的公共函数,避免双份算法漂移。
2. rpcd ucode 环境使用绝对路径导入 `/etc/homeproxy/scripts/outbound_tag.uc`,避免依赖模块搜索路径。
3. 只有在目标环境确实无法共享 import 时,才考虑内联同一算法,并必须增加一致性验证。

RPC 入参边界:

- `sections` 必须是数组,且每个元素必须是非空字符串。
- section 只允许 `[A-Za-z0-9_]`,长度不超过 128。
- 重复 section 只处理一次,避免重复测速请求。
- 只接受真实 `node` section;其他 section type 按“节点不存在”处理。

### 4.5 `clash_api_proxy.uc`:不改

只要 ShadowTLS 中间层仍以 `-out-shadowtls` 结尾,现有过滤逻辑继续生效。不要把展示层代理扩展成双向 rename 层。

## 5. 验证清单

### 5.1 静态检查

- [ ] `build_outbound_tag_map()` 对同一份 UCI 在生成器和 tcping 中结果一致。
- [ ] `routing_node` 只在 `routing_mode == 'custom'` 时收集启用的 `selector` / `urltest` 型分组。
- [ ] 空 label 回退到 `cfg-<section>-out`。
- [ ] reserved tag 和动态 `cfg-*-dns` / `cfg-*-rule` 均被预占用。
- [ ] `GLOBAL` / `any` 等 Clash API / sing-box 特殊名被预占用。
- [ ] final tag 不允许命中 `^cfg-.+-out$`。
- [ ] final tag 不允许命中 `^cfg-.+-dns$` / `^cfg-.+-rule$`。
- [ ] final tag 不允许以 `-out-shadowtls` 结尾。
- [ ] final tag 不允许命中 `^cfg-.+-out-shadowtls$`。
- [ ] ShadowTLS 映射使用 `final_tag + '-out-shadowtls'`。
- [ ] rename pass 在 `removeBlankAttrs()` 之前执行。
- [ ] rename pass 只做等值替换。
- [ ] 去重按 section id 字典序排序后先到先得,结果与遍历顺序无关。
- [ ] label 仅清洗控制字符和 `DEL`(`0x7f`),emoji / 中文 / 空格 / `#` 等原样保留;清洗后为空则回退。
- [ ] 后缀短前缀、完整 section 后缀均冲突时,使用 `-2` / `-3` 等确定性兜底且仍保持唯一。
- [ ] rename 后做 final outbound / endpoint tag 全局唯一性断言,重复则纳入 `hasErrors()`。
- [ ] `generate_client.uc` 能通过 `from 'outbound_tag'` 导入共享模块。
- [ ] `luci.homeproxy_tcping` 能通过 `/etc/homeproxy/scripts/outbound_tag.uc` 绝对路径导入共享模块。
- [ ] `luci.homeproxy_tcping` 拒绝非字符串、空字符串、超长、非法字符 section,并只处理真实 `node` section。

### 5.2 运行验证

1. 生成 `/var/run/homeproxy/sing-box-c.json` 并通过 `sing-box check`。
2. 检查 `outbounds[].tag` 和 `endpoints[].tag`,普通节点显示真实 label。
3. 检查所有 tag 无重复。
4. 在 `custom` 模式构造 `node` 与 `routing_node` 同名,确认按 section id 排序:较小者保留原名,较大者加稳定后缀且配置可用。
5. 构造空 label,确认 tag 没被删。
6. 验证 WireGuard endpoint tag 被替换。
7. 验证 ShadowTLS 主节点 detour 与中间层 tag 一致,且中间层仍被 `clash_api_proxy.uc` 隐藏。
8. MetaCubeXD `/proxies`、Connections、节点切换均显示并使用真实 tag。
9. LuCI 节点测速正常返回延迟。
10. 修改 label 后重新生成,确认 tag 跟随变化。
11. 手动把某节点 label 改成与另一节点相同(同 label、不同 section id),确认按 section id 排序:较小者保留原名,较大者加 ` #` 后缀,且两者都可用。
12. 构造含 emoji / 空格 / `#` / `/` 的 label,确认配置可过 `sing-box check`,面板可正常切换与测速。
13. 200+ 节点规模下确认 rename 正确且耗时可接受。
14. 真机比对 `build_outbound_tag_map()` 在 generate_client 与 tcping 两侧对同一 section 的输出逐一一致。
15. 在非 `custom` 模式保留启用的 selector/urltest `routing_node`,确认它不参与去重、不导致真实节点无意义加后缀。
16. 构造恶意 suffix 占用:先占用 `foo`、`foo #<section 前缀>` 到 `foo #<完整 section>`,确认重复节点最终使用 `foo #<完整 section>-2` 等兜底且无重复。

## 6. 用户可见副作用

1. 首次升级后,`bypass_mainland_china` / `custom` 模式下 sing-box cache 中旧的 selector 选中态会失效一次,需要重新选择节点。
2. 依赖旧 `cfg-<section>-out` 的外部脚本需要改用真实 label。

## 6.1 明确不解决的范围

1. 本次改动只解决“已存在于 UCI 的 section 如何映射为可读 runtime tag”,不改变 `UCI section id` 的生成规则。
2. 订阅导入阶段仍按现有逻辑以 `md5(label)` 参与去重与命名；因此“同一订阅导入流程里允许多个同 label 节点共存”不属于本次 rename pass 的解决范围。
3. 如需放宽订阅导入阶段对同 label 的去重,应单独评估 `update_subscriptions.uc` 的数据模型与兼容性,不与本次显示层可读化改动耦合。

## 7. 实施顺序

1. 新增 `outbound_tag.uc`,导出 `build_outbound_tag_map()`。
2. 在 `generate_client.uc` 接入 rename pass 并验证生成配置。
3. 在 `luci.homeproxy_tcping` 接入同一映射并验证测速。
4. 复核 `clash_api_proxy.uc` 保持 0 改动。

## 8. 不变量

```text
UCI section id     = 内部主键,不改
final outbound tag = 当前 label 经全局去重后的结果(section id 排序 + 先到先得)
ShadowTLS tag      = final outbound tag + '-out-shadowtls'
替换方式           = 写盘前递归等值替换
唯一性             = rename 后 outbound / endpoint tag 全局唯一(断言兜底)
共享要求           = generate_client 与 tcping 使用同一映射算法
```
