# Upstream submission

Target: `openwrt/luci`, branch `master`, directory
`applications/luci-app-device-manager/`.

The independent repository retains development tests, SDK build workflows and
SSH deployment tooling. They are not copied to the upstream repository root.
The configuration initializer lives under `tools/` for source deployments;
packages ship `/etc/config/device_manager` directly. The exported README uses
official-feed installation commands, while standalone build instructions stay
in the independent repository.
Export reviewed package files into a fresh LuCI feature branch:

```sh
git clone https://github.com/openwrt/luci.git /tmp/luci-device-manager-upstream
git -C /tmp/luci-device-manager-upstream switch -c add-device-manager
git -C /tmp/luci-device-manager-upstream config user.name "zhiyong zhang"
git -C /tmp/luci-device-manager-upstream config user.email "zhang747@126.com"
python3 -B tools/prepare-upstream.py /tmp/luci-device-manager-upstream
git -C /tmp/luci-device-manager-upstream diff --check
```

The exporter refuses an existing application directory and does not change
Git history, commit or push. It uses the standard relative `luci.mk` include
and exports only package sources, PO files, licenses and package documentation.

Suggested commit title:

```text
luci-app-device-manager: add LAN device management
```

Suggested commit body:

```text
Add a JavaScript LuCI view for LAN device discovery and metadata management.
Combine host hints, DHCP leases, wireless associations and kernel neighbors.
Save names, remarks, groups and manual type overrides by MAC address.

Unlike the existing host list, this application maintains custom device
metadata and groups, including saved devices that are currently offline.

Render the page before discovery completes and cache snapshots per session.
Confirm unknown devices with bounded sequential Pings to known hosts.
Provide a separate write-authorized scan limited to configured netifd
interfaces and their actual IPv4 prefixes, with bounded concurrency,
duration and a shared scan cooldown.

Use native LuCI message extraction and separately built translation packages.
Include pinned Material Design Icons attribution and Apache-2.0 notices.

Signed-off-by: zhiyong zhang <zhang747@126.com>
```

Submission commits use `zhiyong zhang <zhang747@126.com>` for the author,
committer and Signed-off-by identity. Configure this identity locally in the
LuCI checkout before committing, as shown above. Existing contributor
attribution must be preserved; these tools do not rewrite historical commits.

Suggested PR description:

```text
Add a LAN device manager with MAC-keyed custom names, remarks, groups and
manual device types. Discovery combines native LuCI host/lease/wireless RPCs
with kernel neighbor data and distinguishes online, offline and unknown.

Render the interface before discovery and show list loading and retry states.
Cache snapshots for five minutes per browser tab, session and access level.
Refresh live data in the background and confirm unknown devices with known
IP addresses using sequential Pings, capped at 16 checks and about 12 seconds
per pass. Unanswered Pings remain unknown; stale replies are ignored.

An explicit Scan LAN operation requires write permission and scopes ICMP
probes to configured netifd interfaces and actual prefixes.
Chinese translations are built by luci.mk; other languages use native LuCI
catalogues and English fallback.

Validation:
- 124 Node and 8 Python regression tests passed.
- Official LuCI message extraction, gettext checks and ESLint passed.
- Chromium fixture checks covered cold and expired-cache loading, background
  refresh, online confirmation, empty-state timing and notification dismissal.

Targeted compatibility patches were applied to an OpenWrt 23.05.5 router.
Full-package upgrade, account enforcement and a new SDK build remain to be
verified for this revision. Earlier SDK results are recorded separately in
the independent repository's docs/validation.md.
```

Review the recorded validation results before sending the PR.
Local tests do not certify real-router or upstream acceptance.
