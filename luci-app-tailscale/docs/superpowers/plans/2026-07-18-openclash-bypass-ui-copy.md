# OpenClash Bypass UI Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OpenClash bypass fallback English with complete Simplified and Traditional Chinese copy that explains the concrete network impact of disabling the protection.

**Architecture:** Keep the existing OpenClash helper, UCI package, RPC method, and four-rule lifecycle unchanged. Update only LuCI msgids, translation catalogs, and tests; then use the Linux/OpenWrt SDK CI artifacts to hot-deploy matching JavaScript and Simplified Chinese LMO to the office router with backup and rollback.

**Tech Stack:** LuCI JavaScript forms, gettext PO/POT catalogs, POSIX shell tests, Node.js tests, GitHub Actions OpenWrt SDK builds, OpenWrt LuCI LMO catalogs.

## Global Constraints

- `OpenClash` remains an untranslated product name.
- The switch must state that disabling it returns Tailscale traffic to OpenClash and removes protection for node connectivity, direct paths, Tailnet DNS, and subnet access.
- Do not change helper behavior, firewall UCI, WAN UDP direct rules, subnet SNAT, Tailscale service state, OpenClash service state, or firewall4 lifecycle.
- Only the office OpenWrt at `192.168.100.1` may be written during deployment verification; `hzsls-openwrt` remains read-only.
- Never source `.env`; read only explicit credential keys.
- Back up the deployed JavaScript and LMO before writing, arm an automatic rollback, and verify page, rules, services, DNS, and logs after deployment.

---

### Task 1: Lock the user-facing contract with failing tests

**Files:**
- Modify: `tests/setting_openclash_bypass_test.js`
- Modify: `tests/package_release_test.sh`
- Test: `tests/setting_openclash_bypass_test.js`
- Test: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: existing `_()` gettext msgids in `setting.js` and `assert_po_entry()` in `package_release_test.sh`.
- Produces: exact required English msgids and Simplified/Traditional Chinese translations for Task 2.

- [ ] **Step 1: Add source-contract assertions to the JavaScript test**

Require these new msgids and reject the old switch copy:

```js
assert(source.includes("_('Protect Tailscale Traffic (Bypass OpenClash)')"), 'toggle must explain that it protects Tailscale traffic');
assert(source.includes("_('Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.')"), 'description must name the protected traffic and disabled impact');
assert(source.includes("_('Enabled; 4 bypass rules are active')"), 'active status must report the concrete rule state');
assert(source.includes("_('Disabled; Tailscale traffic is handled by OpenClash')"), 'disabled status must state the traffic impact');
assert(!source.includes("_('Enable OpenClash Bypass')"), 'old implementation-only toggle copy must be removed');
```

Update runtime expectations from `Enabled and active` to `Enabled; 4 bypass rules are active`.

- [ ] **Step 2: Replace package translation assertions with the new copy**

Require exact PO entries for:

```text
Protect Tailscale Traffic (Bypass OpenClash)
Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.
Enabled; 4 bypass rules are active
Disabled; Tailscale traffic is handled by OpenClash
OpenClash is not installed; bypass is not required
Unsupported; firewall4/nftables is required
```

The exact Simplified Chinese switch description must be:

```text
开启后，Tailscale 控制连接、直连通信、Tailnet DNS 和跨子网流量不会被 OpenClash 接管。关闭后，这些流量将重新经过 OpenClash，节点在线、点对点直连、跨子网访问和 Tailnet DNS 解析不再受本功能保护；如果 OpenClash 规则接管或重定向这些流量，可能导致节点掉线、直连退化为 DERP、跨子网访问或 Tailnet DNS 中断。使用 OpenClash 时必须保持开启。
```

Update `assert_po_entry_mutation_test()` to mutate the new active and disabled translations rather than the removed strings.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```sh
node tests/setting_openclash_bypass_test.js
sh tests/package_release_test.sh
```

Expected: both fail because `setting.js` and PO/POT catalogs still contain the old copy.

- [ ] **Step 4: Commit the test contract**

```sh
git add tests/setting_openclash_bypass_test.js tests/package_release_test.sh
git commit -m "test: clarify OpenClash bypass impact copy"
```

---

### Task 2: Implement the LuCI copy and translations

**Files:**
- Modify: `htdocs/luci-static/resources/view/tailscale/setting.js`
- Modify: `po/templates/tailscale.pot`
- Modify: `po/zh_Hans/tailscale.po`
- Modify: `po/zh_Hant/tailscale.po`
- Test: `tests/setting_openclash_bypass_test.js`
- Test: `tests/package_release_test.sh`

**Interfaces:**
- Consumes: exact msgid/translation contract from Task 1.
- Produces: LuCI-rendered switch label, explanation, and status strings with matching gettext catalogs.

- [ ] **Step 1: Update the status msgids in `renderOpenclashBypassStatus()`**

Use:

```js
const labels = {
	active: _('Enabled; 4 bypass rules are active'),
	waiting: _('Enabled; waiting for OpenClash nftables chains'),
	disabled: _('Disabled; Tailscale traffic is handled by OpenClash'),
	absent: _('OpenClash is not installed; bypass is not required'),
	unsupported: _('Unsupported; firewall4/nftables is required'),
	error: _('Configuration error')
};
```

- [ ] **Step 2: Update the form label and description**

Use:

```js
o = s.taboption('openclash', form.Flag, 'openclash_bypass_enabled', _('Protect Tailscale Traffic (Bypass OpenClash)'),
	_('Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.'));
```

- [ ] **Step 3: Replace matching POT and PO entries**

Update all removed msgids in the template and both language catalogs. Use these Simplified Chinese status strings:

```text
已开启，4 条绕过规则已生效
已开启，正在等待 OpenClash 创建 nftables 链
已关闭，Tailscale 流量将由 OpenClash 处理
未安装 OpenClash，无需绕过
当前系统不支持，仅支持 firewall4/nftables
```

The exact Traditional Chinese switch description must be:

```text
開啟後，Tailscale 控制連線、直連通訊、Tailnet DNS 和跨子網流量不會被 OpenClash 接管。關閉後，這些流量將重新經過 OpenClash，節點在線、點對點直連、跨子網存取和 Tailnet DNS 解析不再受本功能保護；如果 OpenClash 規則接管或重新導向這些流量，可能導致節點離線、直連退化為 DERP、跨子網存取或 Tailnet DNS 中斷。使用 OpenClash 時必須保持開啟。
```

Use these Traditional Chinese status strings:

```text
已開啟，4 條繞過規則已生效
已開啟，正在等待 OpenClash 建立 nftables 鏈
已關閉，Tailscale 流量將由 OpenClash 處理
未安裝 OpenClash，無需繞過
目前系統不支援，僅支援 firewall4/nftables
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```sh
node tests/setting_openclash_bypass_test.js
sh tests/package_release_test.sh
```

Expected: both pass.

- [ ] **Step 5: Run the complete local verification suite**

Run the same behavior, syntax, JSON, and translation checks as `.github/workflows/release.yml`. Expected: all shell and JavaScript tests pass; syntax, JSON, and `msgfmt --check-format` produce no errors.

- [ ] **Step 6: Commit the implementation**

```sh
git add htdocs/luci-static/resources/view/tailscale/setting.js po/templates/tailscale.pot po/zh_Hans/tailscale.po po/zh_Hant/tailscale.po
git commit -m "fix: explain OpenClash bypass impact"
```

---

### Task 3: Review, CI build, and office hot deployment

**Files:**
- Read: `.github/workflows/release.yml`
- Deploy from CI artifact: `/www/luci-static/resources/view/tailscale/setting.js`
- Deploy from CI artifact: `/usr/lib/lua/luci/i18n/tailscale.zh-cn.lmo`

**Interfaces:**
- Consumes: reviewed commits from Tasks 1 and 2 and successful `ipk` CI artifact.
- Produces: a merged source change and an office router page using matching JavaScript and Simplified Chinese LMO.

- [ ] **Step 1: Request an independent code review**

Review `origin/main...HEAD` for translation completeness, status accuracy, accidental helper behavior changes, and missing tests. Resolve every actionable finding and rerun the complete suite.

- [ ] **Step 2: Push and create a PR**

Push `codex/clarify-openclash-bypass-ui`, create a PR against `main`, and wait for Behavior and syntax tests, Build ipk, and Build apk to finish successfully.

- [ ] **Step 3: Extract exact deployment files from the successful ipk artifact**

Download the `luci-app-tailscale-ipk` Actions artifact for the PR head. Extract the main package and `luci-i18n-tailscale-zh-cn` package, then obtain:

```text
/www/luci-static/resources/view/tailscale/setting.js
/usr/lib/lua/luci/i18n/tailscale.zh-cn.lmo
```

Verify the JavaScript contains the new msgids and the LMO contains the new Simplified Chinese strings before connecting to the router.

- [ ] **Step 4: Back up and arm rollback on the office router**

Create a timestamped directory under `/root/`, copy the current JavaScript and LMO into it, record SHA-256 hashes, and install a five-minute rollback watchdog. The rollback restores both files and removes LuCI index/module caches.

- [ ] **Step 5: Deploy the matching JavaScript and LMO**

Copy both files into place with their existing owner and mode, remove LuCI cache files, and do not restart Tailscale, OpenClash, firewall4, or network.

- [ ] **Step 6: Verify and disarm rollback**

Verify:

```text
The LuCI source and LMO contain the new strings.
The page renders the Chinese switch, explanation, and active status.
openclash_bypass_status reports state=active and rules_present=4.
Tailscale and OpenClash are running.
Tailnet DNS, public DNS, public web access, and cross-subnet reachability work.
No new related errors appear in logread.
```

Disarm the watchdog only after every check passes. If any check fails, run rollback and repeat the same read-only verification.

- [ ] **Step 7: Merge only after CI and office validation**

Squash-merge the PR after all checks and office validation pass. Do not create the `v1.2.8` tag or upgrade the installed package in this task.
