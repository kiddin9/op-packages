# Manual UI Testing Plan

1. xx

## 0. Authentication

- [x] **0.1** Navigate to `http://<router>/cgi-bin/luci` → Redirected to login page
- [x] **0.2** Submit correct credentials → Redirected to LuCI dashboard
- [x] **0.3** Navigate to `/admin/podman` → Overview page loads without re-auth
- [x] **0.4** Open browser Console tab → No JS errors

---

## 1. Overview (`/admin/podman`)

- [x] **1.1** Load overview → Page loads; all counters visible (0 is fine)
- [x] **1.2** Podman version string visible → Not empty, not "undefined"
- [ ] **1.3** System status indicator visible → Shows running (socket available)
- [x] **1.4** Note all current counts → Baseline for comparison after later steps

### 1a. Auto-update modal - live progress

Prereq: at least one container with label `io.containers.autoupdate=registry`.

- [ ] **1.5** Click "Check for Updates" → Spinner per container → "Apply Updates" modal lists candidates
- [ ] **1.6** Tick a container with an actually-newer image upstream → Click Update → Modal switches to log view with `Update image: 1/N - <name>` header, spinner running, Close button **disabled**
- [ ] **1.7** Log shows `Pulling <ref>`, then live `Trying to pull...`, `Copying blob ...` lines - progress lines with CR overwrite the previous line (no flood of "Copying blob X 50%, 51%, 52%, ...")
- [ ] **1.8** After pull, log shows stage markers: `→ Stopping container`, `→ Removing container`, `→ Creating container`, `→ Starting container`, `→ Reinstating init script`, `✓ Updated to <id-short>`
- [ ] **1.9** Multi-container update: each container delimited by `━━ <name> ━━`; previous container's log remains visible above current one
- [ ] **1.10** After loop ends, counter shows `Done.`, spinner stops, Close button **enabled**
- [ ] **1.11** Click Close → modal dismisses → summary alert appears (`Containers updated successfully` for full success, list of failures otherwise)
- [ ] **1.12** Pull failure (rename the container's image to a non-existent registry before running, or change tag to bogus): log shows `✗ <error>`, run continues to next container, summary marks failed
- [ ] **1.13** Mid-flight failure (SSH `podman run -d --name <same-name> alpine sleep 3600` between Stop and Create, or simulate by other means): log shows `✗ Create failed: ...` for that container, summary marks failed
- [ ] **1.14** Old-image cleanup: after successful update of one container, log shows `━━ Cleaning up old images... ━━` then either `✓ Removed old image <id>` or `! Old image <name> could not be removed - still in use by another container`
- [ ] **1.15** Modal scroll: when log overflows visible area, content auto-scrolls to bottom on append; scroll up manually → new lines append at bottom but viewport stays where the user put it (sticky-scroll)
- [ ] **1.16** Long pull crossing uhttpd `script_timeout` (~55s): server-side connection rotates transparently (auto-reconnect in `Model._stream`); log keeps growing, no spurious error

---

## 2. Images (`/admin/podman/images`)

- [x] **2.1** Load images list → Page loads (may be empty)
- [x] **2.2** Click "Pull Image" → Form/modal appears with name input
- [x] **2.3** Submit empty form → Validation error, no request sent
- [x] **2.4** Pull nonexistent image (e.g. `this-does-not-exist:fake`) → Error notification shown, list unchanged
- [x] **2.5** Pull `alpine:latest` → Progress indicator → success notification → `alpine` appears in list
- [ ] **2.6** Pull `alpine:latest` again (already exists) → Graceful result (no crash, may show "already up to date")
- [x] **2.7** Click inspect on `alpine` → Modal opens with JSON image data
- [x] **2.8** Return to overview → Image count incremented by 1

---

## 3. Containers (`/admin/podman/containers`)

*Requires `alpine:latest` from step 2.5.*

### 3a. Create

- [x] **3.1** Load containers list → Page loads (may be empty)
- [x] **3.2** Click "Create Container" → Form modal opens
- [x] **3.3** Submit empty form → Validation errors on required fields
- [x] **3.4** Fill name: `test-alpine`, image: `alpine:latest`, no other changes → Submit → Container created; `test-alpine` visible in list
- [x] **3.5** Return to overview → Container count incremented

### 3b. List operations

- [x] **3.6** Verify `test-alpine` row shows correct Name, Image, State
- [x] **3.7** Select `test-alpine` checkbox → Only that row selected
- [x] **3.8** Click top "select all" checkbox → All rows selected
- [x] **3.9** Click top checkbox again → All deselected

### 3c. Start / Stop / Restart

- [x] **3.10** If container is stopped: select → Start → State changes to `Running`; success notification
- [x] **3.11** Select running container → Stop → State changes to `Exited`; success notification
- [x] **3.12** Select stopped container → Restart → State changes to `Running`

### 3d. Detail view - Info tab

- [x] **3.13** Click `test-alpine` name link → Navigates to container detail page
- [x] **3.14** Name, image, state displayed → Matches list view
- [x] **3.15** Edit container name to `test-alpine-renamed` → Save → Name updated; notification shown
- [x] **3.16** Change restart policy to `always` → Save → Policy updated; success notification
- [x] **3.17** Init script auto-generated → Auto-start indicator shows enabled
- [x] **3.18** Click "Show Init Script" → Modal with script content; script references `test-alpine-renamed`
- [x] **3.19** Toggle init script disabled → Indicator changes
- [x] **3.20** Toggle init script enabled again → Indicator reverts
- [x] **3.21** Change restart policy to `no` → Save → Init script removed/disabled
- [x] **3.22** Navigate back to list → Name shown as `test-alpine-renamed`

### 3e. Detail view - Resources tab

- [x] **3.23** Click Resources tab → Tab activates; current limits shown
- [ ] **3.24** Set CPU limit to `0.5` → Save → After page reload, Resources tab is active (tab persistence)
- [x] **3.25** Set Memory limit to `64m` → Save → Value persisted
- [x] **3.26** Enter invalid CPU value (e.g. `abc`) → Save → Validation error; no save

### 3f. Detail view - Stats tab

- [x] **3.27** Start container (if stopped)
- [x] **3.28** Click Stats tab → CPU%, Memory, Net I/O data appears
- [x] **3.29** Stop container; click Stats tab → Graceful empty/zero state, no JS crash

### 3g. Detail view - Logs tab

- [x] **3.30** Click Logs tab → Log output area visible (may be empty for alpine)
- [x] **3.31** Change line count to `50` → Apply → Fetches last 50 lines
- [ ] **3.32** Enable live streaming toggle → Toggle activates
- [x] **3.33** Disable live streaming → Streaming stops, toggle off
- [x] **3.34** Click Clear → Log area clears

### 3h. Detail view - Processes tab

- [x] **3.35** Start container; click Processes tab → Process table appears
- [x] **3.36** Stop container; click Processes tab → Graceful empty/error state, no JS crash

### 3i. Network management (on detail page)

- [x] **3.37** Note current networks attached → Baseline
- [x] **3.38** Disconnect default network → Network removed from list
- [x] **3.39** Reconnect the network → Network added back
- [x] **3.40** Connect a network with valid static IP → Network added with IP shown
- [x] **3.41** Connect a network with invalid IP → Validation error

### 3j. Pause / Unpause

- [ ] **3.42** List view: select a running container → click ⏸⏸ Pause → state changes to `paused`; success notification
- [ ] **3.43** List view: same paused container selected → click ▶ Start → state changes back to `running` (Start polymorphically unpauses paused containers)
- [ ] **3.44** Detail view: container is running → ▶ Start is highlighted as active, ⏸⏸ Pause is clickable
- [ ] **3.45** Detail view: click Pause → reload → state is `paused`, ⏸⏸ Pause is now highlighted, ▶ Start is clickable
- [ ] **3.46** Detail view: click Start while paused → reload → state is `running`, ▶ Start highlighted again
- [ ] **3.47** Detail view: streams (stats / logs / processes) stop before pause fires (no reconnect storm in DevTools Network panel)
- [ ] **3.48** Multi-select on list: mix of running + paused → click ▶ Start → running stays running, paused becomes running (per-container dispatch)

---

## 4. Volumes (`/admin/podman/volumes`)

- [x] **4.1** Load volumes list → Page loads (may be empty)
- [x] **4.2** Click "Create Volume" → Form appears
- [x] **4.3** Submit empty form → Name will be generated
- [x] **4.4** Create volume named `test-vol` → Appears in list with name, driver, created date
- [x] **4.5** Click inspect on `test-vol` → JSON modal shows volume data
- [x] **4.6** Return to overview → Volume count incremented
- [x] **4.7** Select `test-vol` → Delete → Confirmation modal → confirm → removed from list
- [ ] **4.8** Create volume `test-vol-prune` and leave it → Used in prune test (step 8.2)

---

## 5. Networks (`/admin/podman/networks`)

- [x] **5.1** Load networks list → Default `podman` network visible
- [x] **5.2** Note OpenWrt column for default network → Status icon shown
- [x] **5.3** Click "Create Network" → Form opens
- [x] **5.4** Submit empty form → Validation error
- [x] **5.5** Create `test_net`, subnet `10.220.0.0/24`, gateway `10.220.0.1`, OpenWrt integration checked → Network created; OpenWrt column shows `✓`
- [x] **5.6** Verify UCI config created → SSH: `uci show network.test_net` returns values
- [x] **5.7** Create `test_net_b` with no subnet, integration unchecked → Network created; OpenWrt column shows `-`
- [x] **5.8** If any network shows `X` (incomplete integration): click it → setup → icon changes to `✓`
- [x] **5.9** Return to overview → Network count incremented
- [x] **5.10** Select `test_net` → Delete → Confirmation mentions OpenWrt cleanup → confirm → network removed; UCI config removed
- [x] **5.11** Select `test_net_bare` → Delete → Removed cleanly (no UCI to clean up)

---

## 6. Secrets (`/admin/podman/secrets`)

- [x] **6.1** Load secrets list → Page loads (may be empty)
- [x] **6.2** Click "Create Secret" → Form with name + value fields
- [x] **6.3** Submit empty form → Validation error
- [x] **6.4** Create secret name `test-secret`, value `hunter2` → Appears in list; value NOT shown anywhere
- [x] **6.5** Click inspect on `test-secret` → Modal shows metadata; `SecretData` field hidden
- [x] **6.6** Delete `test-secret` → Removed from list

---

## 7. Pods (`/admin/podman/pods`)

*Requires `alpine:latest` from step 2.5. If a user-defined network exists from section 5, note its name as `<usernet>`.*

### 7a. List view

- [x] **7.1** Load pods list → Page loads with empty/populated table; no "Work in progress…" stub
- [x] **7.2** Toolbar visible → Create / Delete / Reload / ▶ / ■ / ⟳ / ⏸ / ⏵ buttons present
- [x] **7.3** Click Reload with empty list → No error, indicator appears briefly

### 7b. Create - minimal

- [x] **7.4** Click "Create" → Pod form modal opens with default fields populated
- [x] **7.5** Submit empty form → No validation error (name auto-generates); pod appears with generated name
- [x] **7.6** Create pod name `pod-min`, all other defaults → Modal closes, success notification, `pod-min` row appears
- [x] **7.7** Verify SSH `podman pod inspect pod-min` → Pod exists with one infra container
- [x] **7.8** Containers column shows `1 ▸` for `pod-min`

### 7c. Create - full options

- [x] **7.9** Open Create form → Name `pod-full`, Hostname `pod-full-host`, Shared Namespaces `cgroup,ipc,net,uts`, Infra ON, Network `<usernet>`, DNS Servers `1.1.1.1` and `9.9.9.9`, DNS Search `lan`, CPU Limit `1.0`, CPU Set `0-1`, Memory `256m`, Labels `app=demo\nenv=test` → Submit
- [x] **7.10** SSH `podman pod inspect pod-full | jq '.Hostname'` → `pod-full-host`
- [x] **7.11** SSH `podman pod inspect pod-full | jq '.InfraConfig.NetworkOptions'` → contains DNS server + search entries
- [x] **7.12** SSH `podman pod inspect pod-full | jq '.Labels'` → `app: demo`, `env: test`
- [x] **7.13** Networks column for `pod-full` → shows `<usernet>`

### 7d. Status badges

- [x] **7.14** New pod → Status badge `Created` (gray)
- [x] **7.15** After Start → Badge `Running` (green)
- [x] **7.16** After Pause → Badge `Paused` (orange)
- [x] **7.17** After Stop → Badge `Exited` or `Stopped` (red)

### 7e. Lifecycle - single select

- [x] **7.18** Tick `pod-min`, click ▶ Start → Loading "Starting pod: 1/1", refresh shows `Running`
- [x] **7.19** Click ■ Stop → Status `Exited`/`Stopped`
- [x] **7.20** Click ⟳ Restart → Status `Running`
- [x] **7.21** Click ⏸ Pause → Status `Paused`
- [x] **7.22** Click ⏵ Unpause → Status `Running`

### 7f. Lifecycle - multi-select

- [ ] **7.23** Create `pod-a` and `pod-b` (defaults), select both → ▶ Start
- [ ] **7.24** Loading modal shows "Starting pod: 1/2" then "2/2"
- [ ] **7.25** Both pods end up `Running`
- [ ] **7.26** No JS console errors during multi-action

### 7g. Detail page navigation (from list)

- [ ] **7.27** Click pod **Name** in list → Navigates to `/admin/podman/pod/<id>` (no more inspect modal)
- [ ] **7.28** Browser back button → Returns to pods list with state preserved

### 7h. Containers expand modal

- [x] **7.29** SSH `podman run -d --pod pod-min --name pod-min-c1 alpine sleep 3600` → container created in pod
- [x] **7.30** Reload pods list → `pod-min` Containers column shows `2 ▸`
- [x] **7.31** Click `2 ▸` link → Modal "Containers in pod pod-min" opens with 2 rows (infra + new)
- [x] **7.32** Each row shows Name, truncated ID, Status badge, Restarts count
- [x] **7.33** Click container ID link in modal → Navigates to `/admin/podman/container/<id>` detail view

### 7i. Pod removal

- [ ] **7.34** Stop `pod-min` first → Status `Exited`
- [ ] **7.35** Tick `pod-min` → Delete → Confirm
- [ ] **7.36** SSH `podman pod ls` → `pod-min` gone
- [ ] **7.37** SSH `podman ps -a` → `pod-min-c1` also gone (cascade delete via force)

### 7j. Container form integration

- [x] **7.38** Navigate **Podman → Containers → Create** → Form shows new **Pod** ListValue (after Image) with "(none)" + existing pod names
- [x] **7.39** Select Pod = `pod-full` → Network, Hostname, Port Mappings, Expose Ports fields hide
- [x] **7.40** Select Pod = "(none)" → Hidden fields reappear
- [x] **7.41** Create container with Pod `pod-full`, Image `alpine:latest`, Command `sleep 3600`, Start ON → Success
- [x] **7.42** SSH `podman ps --filter pod=pod-full` → New container listed
- [x] **7.43** Pods list `pod-full` Containers column → count incremented

### 7k. Edge cases

- [ ] **7.44** Create pod with name `Bad Name!` → Validation error (uciname constraint)
- [ ] **7.45** Toggle "Create Infra Container" OFF → Network/DNS/Infra Image fields hide
- [ ] **7.46** Submit pod with Infra OFF → Pod created without infra container; SSH `podman pod inspect` confirms
- [ ] **7.47** Try Stop on already-stopped pod → No JS error (graceful handling of API 304/409)
- [ ] **7.48** Try Pause on stopped pod → Error notification, no JS crash

### 7l. Regression - non-pod container create

- [ ] **7.49** Create container with Pod = "(none)", port mapping `8080:80`, network `<usernet>`, hostname `freebee` → Success
- [ ] **7.50** SSH inspect → port mapping, network and hostname present (confirms `if (!data.pod)` guards don't break the non-pod path)

### 7m. Cleanup

- [ ] **7.51** SSH `podman pod rm -f pod-full pod-a pod-b` → All test pods removed
- [ ] **7.52** SSH `podman ps -a` → No leftover test containers
- [ ] **7.53** Reload pods list → Empty/clean state

### 7n. Detail page - load & header (`/admin/podman/pod/<id>`)

- [ ] **7.54** Direct URL `/admin/podman/pod/<podId>` → Detail page loads, no console errors
- [ ] **7.55** Header shows pod name and back-arrow button → back button returns to pods list
- [ ] **7.56** Lifecycle buttons visible: ▶ Start, ■ Stop, ⟳ Restart, ⏸ Pause, ⏵ Unpause, 🗑 Delete
- [ ] **7.57** "Active" highlight reflects current state: Running pod → ▶ highlighted, Paused pod → ⏸ highlighted, Exited pod → ■ highlighted (semantic: button describes current state, not "available action")
- [ ] **7.58** Tabs visible: Info, Stats, Processes, Inspect

### 7o. Detail page - Info tab

- [ ] **7.59** Basic Information section: Name, ID (full 64-char), Status badge, Created date populated
- [ ] **7.60** Configuration section: Hostname, Cgroup parent, Exit policy, Restart policy, Shared namespaces (comma-joined), Infra container (clickable link to `/admin/podman/container/<infraId>`)
- [ ] **7.61** Resources section: CPU period (µs), CPU quota (µs or "Unlimited"), CPU shares, CPU set, Memory limit (formatted bytes or "Unlimited"). Description note "Resources are set at pod creation and cannot be edited here." present
- [ ] **7.62** Network section: Networks, Static IPv4, Static MAC, DNS servers, DNS search, DNS options, Extra hosts, Host network (Yes/No)
- [ ] **7.63** Containers section: table with Name, truncated ID (clickable → container detail), Status badge - one row per container including infra
- [ ] **7.64** Labels section: only rendered if pod has labels; otherwise omitted
- [ ] **7.65** All empty fields show `-` placeholder

### 7p. Detail page - Stats tab (pod running)

- [ ] **7.66** Switch to Stats tab → Table with headers: Container, CID, CPU %, Memory, Memory %, Net I/O, Block I/O, PIDs
- [ ] **7.67** Rows update live (humanized strings from `PodStatsReport`: e.g. "75.5%", "12mb / 24mb")
- [ ] **7.68** Container name column resolves from pod's containers map (not the pod-name value the API returns)
- [ ] **7.69** Switch to another tab → Stream stops (verify in DevTools Network: stream connection closes)
- [ ] **7.70** Switch back to Stats → Stream restarts
- [ ] **7.71** Pod is stopped → Stats tab shows "Pod is not running" warning, no stream attempt

### 7q. Detail page - Processes tab (pod running)

- [ ] **7.72** Switch to Processes tab → Table with columns Podman's `pod top` returns (USER, PID, ..., CMD) plus a CONTAINER column (native to pod top)
- [ ] **7.73** Rows update live as processes change
- [ ] **7.74** Switch away → Stream stops
- [ ] **7.75** Pod is stopped → Shows "Pod is not running" warning

### 7r. Detail page - Inspect tab

- [ ] **7.76** Switch to Inspect tab → Renders full raw JSON of `podman pod inspect`
- [ ] **7.77** Same content as old list-view inspect modal (sanity check no fields are lost)

### 7s. Detail page - lifecycle actions

- [ ] **7.78** Running pod → click ⏸ Pause → confirmation/loading → reload → status `Paused`, ⏸ now highlighted as active
- [ ] **7.79** Paused pod → click ⏵ Unpause → reload → status `Running`
- [ ] **7.80** Running pod → click ■ Stop → reload → status `Exited`, ■ highlighted
- [ ] **7.81** Stopped pod → click ▶ Start → reload → status `Running`
- [ ] **7.82** Click ⟳ Restart → reload → status briefly cycles to Running
- [ ] **7.83** Click 🗑 Delete → confirm dialog → confirm → redirects to `/admin/podman/pods`, pod gone
- [ ] **7.84** Before Stop/Pause/Restart, verify in DevTools Network: stats/processes streams close BEFORE the action fires (no reconnect storm)

### 7t. Detail page - edge cases

- [ ] **7.85** Pod with no containers (rare - infra-less or just created): Containers section shows "No containers in this pod"
- [ ] **7.86** Pod with no labels: Labels section is absent (not just empty)
- [ ] **7.87** Pod with `RestartPolicy` unset: Configuration shows `-`
- [ ] **7.88** Pod with `memory_limit: 0` or unset: Resources shows "Unlimited"
- [ ] **7.89** Pod with `cpu_quota: -1`: Resources shows "Unlimited"
- [ ] **7.90** Invalid pod ID in URL → Redirects to pods list (no crash)
- [ ] **7.91** Refresh page while stats stream active → No duplicate streams (Network panel shows single connection)

---

## 8. Modals

### Prune Modal

- [x] **8.1** Open prune modal → Options shown: containers, images, volumes, networks
- [ ] **8.2** Select only "Volumes" → Prune → Only unused volumes pruned (e.g. `test-vol-prune` from step 4.8); containers/images untouched
- [ ] **8.3** Select "Containers" → Prune → Only stopped/exited containers removed

### Auto-Update Modal

- [x] **8.4** Open auto-update modal → Container list shown with current digest info
- [x] **8.5** Click "Check for Updates" → Digest comparison runs; up-to-date containers marked
- [x] **8.6** If outdated container detected → Update → Pulls new image, recreates container

---

## 9. Error Handling

- [ ] **9.1** Stop Podman socket (`/etc/init.d/podman stop`), load any list view → Clear RPC error message; no JS crash, no blank page
- [x] **9.2** Navigate to `/admin/podman/container/nonexistent-id` → Graceful error, not a blank page
- [ ] **9.3** Start Podman again (`/etc/init.d/podman start`); reload → Normal operation resumes
- [x] **9.4** Trigger two operations quickly in succession → No race-condition crash or duplicate requests

---

## 10. Cleanup Verification

- [x] **10.1** Delete any remaining test containers (e.g. `test-alpine-renamed`)
- [x] **10.2** Delete `alpine` image
- [x] **10.3** Containers list → Empty (or back to pre-test state)
- [x] **10.4** Images list → Empty (or back to pre-test state)
- [x] **10.5** Overview counters → Match baseline from step 1.4
