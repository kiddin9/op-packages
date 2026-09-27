# Changelog

All notable changes to `thermal-guard` and `luci-app-thermal-guard`.
Versions follow `Major.Minor.Patch`; both packages are released
together and carry the same number.

## 2.0.0

### Breaking changes

- **Breaking: `trip_dt` is no longer a UCI option.** The daemon used to write
  it into `/etc/config/thermal-guard` from the running process, next to the
  operator's own edits. The device tree trips that `trip_active` was made for
  now live in `/etc/thermal-guard/trip_base`, written on the first cycle with
  `trip_active` set and kept across a sysupgrade. Without `trip_active` the file
  is neither read nor written. The package moves an existing `trip_dt` there
  once (`/etc/uci-defaults/90-thermal-guard-trip-base`) and removes the option;
  a leftover `trip_dt` is ignored. The daemon no longer writes UCI.
- **Breaking: `fan_cooling_device` and `fan_thermal_zone` are gone.** Both
  named a numbered path (`cooling_device0`, `thermal_zone0`), and those numbers
  can change between boots, which is what the detection by type avoids. The
  fan is found by `fan_cooling_device_type`, its zone by the link to it. A
  value left in an old configuration is ignored like any unknown option.

### Notes for operators

- **Syslog filters may need adjusting.** Every line now carries a
  `daemon.*` priority instead of `user.notice`: `crit`, `warning`, `notice`,
  `info` as listed under Changed. A `logread` filter or remote syslog rule
  written for `user.notice` no longer matches.
- **New dependency `jsonfilter`.** `base-files` already ships it on every
  OpenWrt and ImmortalWrt image, so nothing new gets installed there.
- **Update both packages together.** The config page's answer to a changed
  firmware runs `thermal-guard trips-keep`, which needs the daemon and the
  rpcd ACL of this release; the ACL grants exactly that command line.

### Added

- **`thermal-guard trips-keep`** records the device tree trips of the running
  boot as the ones `trip_active` was made for. The config page runs it for both
  answers to the new firmware notice; the ACL grants exactly this command line.

### Changed

- **README: a section on known limitations**: ModemManager and `at_lock`,
  notifications without `curl`, boards that report no temperature, and
  `wifi_off` on radios netifd does not manage.

- **Without `curl`, a notification address with a query string or user info
  is refused.** `uclient-fetch` and `wget` take the address on the command
  line, where every local process can read it in `/proc`, so a token in
  `?token=...` or `user:pass@host` would leak. The check runs when the
  configuration loads and clears `notify_url`, so nothing piles up in the
  outbox; the notify hook still works. An address without `http://` or
  `https://`, or with characters `curl` would misread, and a malformed
  `notify_header` are now rejected at load for the same reason. Each reason is
  logged once, the address itself never. A secret in the path of the address
  (Slack, Discord, a private ntfy topic) cannot be detected and stays visible
  without `curl`; the README says so.
- **A notification post without `curl` has a time limit.** `uclient-fetch` and
  `wget` run under `timeout` (`HTTP_TIMEOUT`, 20 s by default) with `-T 15` for
  the network wait, so a hung DNS lookup or server costs one message instead of
  blocking the loop. The `curl` path keeps its `-m 15`.
- **`wifi_off` is read back.** It was the only built in stage action that
  trusted the exit code of `wifi down`. Now the command is sent up to five times
  with 5 s in between (`WIFI_SETTLE`), and the action succeeds only when
  `ubus call network.wireless status` reports no radio up; the way back after a
  reset waits until every radio that is not disabled is up. Checked against the
  real netifd answers of a Banana Pi R3 Mini (`mt_wifi`) and a GL-X3000, kept as
  test fixtures.
- **Time limits for `wifi`, `ifdown`, `ifup` and every hook.** The commands get
  15 s (`CMD_TIMEOUT`), the `notify`, `stage1` and `stage2` hooks 15 s
  (`HOOK_TIMEOUT`), the `modem-temp` hook 5 s. A hook that ignores TERM is killed
  5 s later. Before, a hung command or hook held the whole loop.
- **The config page checks what the daemon will use.** The order of the
  thresholds is checked against the values in the form, not the saved ones,
  and an empty field counts as the daemon's default; before, `cpu_warn` 85 with
  `cpu_crit` left empty passed and made the daemon fall back to all defaults.
  A threshold like `85abc` is refused. `interval` takes whole numbers of 5 and
  more only. `fan_governor` is a list of the four governors the daemon accepts.
- **`fan_governor` only takes a kernel governor that regulates:**
  `step_wise`, `fair_share`, `bang_bang` or `power_allocator`. Before, any
  string went to the zone's `policy` on reset, `user_space` included, which
  leaves nothing regulating the fan. Anything else now means `step_wise` and is
  logged once.
- **Syslog lines carry a priority** instead of the default `user.notice`:
  `daemon.crit` for stages, restored stages, a stage that cannot be persisted
  and failed stage actions (also a modem or interface that does not come back
  after a reset), `daemon.warning` for rejected options, missing tools, a
  sensor that does not read and trips that could not be written,
  `daemon.notice` for cooled down, reset, `trips-keep` and new firmware trips
  that need a decision, `daemon.info` for the rest. The `blind:` message for a
  CPU sensor that stops reading ran through the stage 0 path and would have
  been `crit`; it is a `warning` and is still notified. The event log format
  is unchanged.
- **netifd's answers are read with `jsonfilter`** instead of `sed` and `awk` on
  the text of `ubus` output, which depended on its indentation. Every `ubus
  call` has a time limit of 5 s (`UBUS_TIMEOUT`): netifd answers late while
  `wifi down` runs, and the readback must not hang on exactly what it checks.
  A radio counts as enabled unless netifd reports it `disabled`; the Wi-Fi log
  line counts only those. `jsonfilter` is now in `DEPENDS`; `base-files`
  already pulls it into every image.
- **The configuration is read with one `config_load` per cycle** instead of
  one `uci -q get` per option, about 40 processes every 20 s. The checks on
  the values are unchanged.
- **The detected fan pwm output is logged once as `fan pwm output detected at
  '...'`.** Before it read `fan pwm path '' unusable`, although nothing was
  configured. A configured `pwm_path` that stopped working is still reported
  as unusable, once per replacement.

### Fixed

- **Four help texts on the config page say what the service does** (English
  and German): `fan_governor` applies only when no earlier control mode was
  recorded; `hold_minutes` starts stage 2 of 3 when the temperature has not
  dropped and stage 3 of 3 only while it still rises; the `zone_path` reason
  names the fan's zone, which is no longer configured; `uplink_interface`
  decides whether a message goes out or is queued, not whether the modem is
  switched off, and is the default for the interface action.

- **README, hooks README and the comments in `/etc/config/thermal-guard`
  describe what the code does**: which stage actions can keep a connection
  off after a reboot, what a pwm reset writes back, when `test` shows the
  escalation over time, what a missing hook means per hook, what
  `fan_cooling_device_type` is used for, and that `fan_governor` applies only
  when no earlier governor was recorded.

- **`thermal-guard test` reports the fan mode the daemon would use.** It took
  `fan_mode` as configured, so `auto` without a cooling device or `pwm`
  without `pwm_full` and `pwm_idle` claimed "forcing fan to full speed", while
  the daemon leaves the fan alone in both cases. It now runs the same fan
  detection, which only reads sysfs.

- **A `cpu_temp_path` set in its `/sys/devices` form no longer shows the
  processor among the other sensors.** Paths were compared as written, and
  the sensor loops walk the `/sys/class` links. Such a path is now resolved
  and compared resolved; the default and detected paths are in class form and
  cost nothing extra.

- **`... cannot send a header` is logged once per fetcher.** Without `curl` it
  came with every message and with every retry of the outbox, two minutes
  apart. It is said again when the header was empty in between or another
  fetcher takes over, and forgotten once `curl` is there.

- **Trip messages are said once each.** They shared one memory, which every
  successful trip write cleared, so `device tree trips are now ...` came back
  after each change of the trips. Each message now has its own, cleared when
  its cause is gone: the zone found, `trip_active` valid again, the firmware
  trips recorded, a write that worked.

- **The 1.2.0 entry on notifications overstated the config file.** Only `curl`
  reads `notify_url` and `notify_header` from a file; `uclient-fetch` and
  `wget` take the address on their command line. Since this release such an
  address is refused when it carries a query string or user info (see
  Changed).

- **`at_lock` is checked where it is used, not only when the configuration
  loads.** 1.2.0 said every UCI path is checked again at its use site; for
  `at_lock` that was not so, `tg_at` handed it to `flock` as it was. Now a path
  the guard refuses falls back to `/var/lock/modem-at.lock` there as well.

- **The processor no longer shows up among the other sensors under another
  name.** It was left out only when its sensor was called `cpu_thermal`. A
  processor zone with another type, or a hwmon input such as `coretemp`, was
  listed a second time. Now its own sensor is skipped by path, and where it is
  a thermal zone, the hwmon node the kernel mirrors it as is skipped by the
  zone's type. The other inputs of the same chip stay listed.

- **A `modem-temp` hook stopped at its time limit gives no reading.** Its
  output was used whatever the exit status, so a hook that printed a value
  and then hung still counted. Now the output is dropped when `timeout`
  reports the limit (124) or the hook died of a signal (above 128: the KILL
  for a hook that ignored TERM, or a BusyBox `timeout`, which reports 143),
  as the hooks README already said.

- **A reading missing at stage entry no longer counts as 0.** The reference
  for "no drop" and "still climbing" was stored as 0 when that reading was
  missing, and a state file from before the references existed loaded them as
  0. Any later reading then counted as a rise, and stage 3 of 3 could start
  without one. A missing reference now stays empty, the comparison counts only
  channels with a reading and a reference, and the first reading after the gap
  becomes the reference, so the channel compares again as "risen since it came
  back".

- **`thermal-guard test` shows what the readings would trigger, and only on
  stdout.** It ran one cycle, while every stage needs two readings in a row, so
  it never showed a stage. What it could do was write a `cooled down` line
  (notice) into syslog and the event log when a stage was active. Now it runs
  two cycles at the same moment and prints each message it would send as
  `would notify (<priority>): ...`; syslog, the event log and the outbox stay
  untouched.

- **Without `ip`, messages were never delivered from stage 2 of 3 on.** The
  uplink check found no route, so every message went to the outbox, and the
  outbox waited for a route it could never see. Nothing was logged. Now a
  missing `ip` means the uplink is unknown and the message goes out at once,
  with `no ip command, cannot tell whether another uplink exists, sending at
  once` logged once as a warning. A missing `flock` is logged once as well
  (`no flock command, AT queries run without the shared lock`); the queries
  still run.

- **A stage restored after a reboot reports an action that fails.** The
  restore reapplied the stage actions without looking at the result, so a
  modem that stayed on or Wi-Fi that stayed up went unreported. Now each
  failure is logged as crit (`stage N action '...' failed after the reboot`),
  and the one restore message, sent after the actions, names what failed. The
  event log gets `restoring stage N after a reboot` before the actions start,
  so a daemon that dies halfway leaves a trace.
- **Handing a pwm fan back is read back.** Reset wrote the saved mode and duty
  cycle without checking them. Both are read back now and a mismatch is logged
  as crit. In automatic mode the duty cycle is no longer written at all: the
  chip sets it itself, the value from before the takeover means nothing there,
  and some drivers refuse it.

- **The status page no longer says a board without a sensor takes no action.**
  The note read "The service stays idle and takes no action", while the modem
  thresholds keep working as long as the modem reports a temperature. It now
  says that the processor is not watched and the modem thresholds still apply
  (English and German).

- **`wifi_off` no longer counts as done when netifd manages no radio.** An
  empty `network.wireless` status used to confirm the action: nothing was up,
  because nothing was there, and the stage reported Wi-Fi off on a device whose
  radios netifd does not see. Now the action fails (`netifd manages no Wi-Fi
  radio, wifi_off switched nothing off`, crit) and is notified like any failed
  action. Bringing Wi-Fi back after a reset still passes, there is nothing to
  bring back. The daemon also warns once when it loads a configuration that
  uses `wifi_off` on such a device, so the mistake shows before the box runs
  hot; a ubus error there is left to the action.

- **`thermal-guard selftest` says why it stops** when it cannot create its
  scratch directory, instead of ending with 1 and no word. The
  `cooling-levels` case skips on a host without `hexdump` rather than failing.

- **Handing the zone back on reset is checked.** `tg_fan_release` wrote the
  governor to the zone's `policy` without reading it back. A governor the
  kernel was built without, such as `power_allocator` on the Filogic kernel,
  was refused by the kernel, and the zone stayed on `user_space` with the fan
  at full speed and nobody told. Now a governor missing from
  `available_policies` becomes `step_wise` (logged as warning), and a zone that
  still reports another policy afterwards is logged as crit.

- **A deleted option kept its last value until the daemon restarted.**
  Removing `notify_url` went on sending notifications, removing a threshold
  kept the old threshold. Every option now returns to its default within one
  cycle.

- **A persisted stage could be lost to a power cut, and a failed persist went
  unnoticed.** Writing `/etc/thermal-guard/state` on a stage change and removing
  it on reset now end with `sync`. A persist that cannot be written, for example
  on a full or read only overlay, is logged once (`could not persist stage N to
  ..., it will not survive a reboot`) instead of being treated as done. The
  per cycle path writes only to `/var/run` and does not sync.

## 1.5.0

### Added

- **Wi-Fi temperatures with the proprietary MediaTek driver.** `mt_wifi`, used
  by the MTK vendor images of the Banana Pi R3 Mini, registers no hwmon sensor,
  so the status page showed no Wi-Fi readings although the LuCI overview did.
  The extra sensors now also read `CurrentTemperature` from
  `iwpriv <interface> stat` for `ra0`, `rax0` and the other `mt_wifi`
  interfaces, only while they are up and bounded by `timeout`, the same way
  ImmortalWrt's `autocore` does it. Shown as Wi-Fi 1, Wi-Fi 2, for display only.

## 1.4.0

Where the kernel drives the fan, thermal-guard can now lower its trip points
for a hot modem instead of competing with it. Package release `1.4.0-r2`,
deployed and checked on the GL-X3000 and both Banana Pi R3 Mini.

### Added

- **Trip management (`trip_boost`, `trip_active`, `trip_boost_offset`,
  `trip_dt`).** With `trip_boost 'modem'` the daemon lowers the active trips of
  the thermal zone that drives the fan by `(modem - offset) - cpu`, rounded up
  to 5 K and capped at 40 K, so the kernel regulator spins the fan up for a hot
  modem it cannot see. Trips only ever go below the baseline, `hot` and
  `critical` are never written, a missing reading holds the trips and raising
  them needs three cool readings in a row. Stopping the daemon leaves them where
  they are. Nothing is written unless `trip_boost` or `trip_active` is set, so
  boards with a kernel-driven fan such as the GL-X3000 keep their trips. New
  module `/usr/share/thermal-guard/trips.sh`, selftest cases against a planted
  sysfs tree.
- **`THERMAL_ROOT`** environment variable, default `/sys/class/thermal`, for
  tests only. UCI cannot change it.
- **`/var/run/thermal-guard/modem-temp`**: one line `<degrees> <unix time>
  <source>`, written atomically after every good modem reading. Other programs
  read the value here instead of querying the modem over AT themselves. A
  missing reading leaves the file alone, so its age shows the outage.
- Deployment findings for 1.2.0 on real hardware, one section per device,
  taken into the development repository unchanged.

### Changed

- **AT queries have a time limit.** `timeout 10 flock <lock> timeout 5
  sms_tool …`: the outer limit covers the wait for the lock, which BusyBox
  `flock` cannot bound itself, the inner one the query. Before, a hung modem or
  a program sitting on the lock stopped the whole loop, stages and trip
  management included. A timeout counts as a missing reading. New dependency
  `coreutils-timeout`; the selftest fails where `timeout` is missing.
- **Web interface.** System → Thermal Guard, tab Fan: `trip_boost`, the
  modem allowance and the switching temperatures (`trip_active`, checked with
  the same rules as the service), the state of the trip management, the
  `cooling-levels` from the device tree with their duty cycle, and after an
  image with other device tree trips a notice with "use the firmware values" and
  "keep my values". The status page shows the current trips and by how much
  they are lowered. 31 new strings, German catalogue complete.
- Status file: `trip_state`, `trip_reason` (a fixed code the page translates),
  `trip_zone`, `trip_base`, `trip_now`, `trip_dt`, `trip_delta`,
  `trip_dt_changed`, `trip_limit`, `fan_levels`.
- Docs: README covers trip management, `modem-temp` and the dependency.
  The internal deployment documents follow the new layout of the build
  repositories.
- `luci-app-thermal-guard` 1.4.0, same number as the daemon.
- **`/lib/upgrade/keep.d/thermal-guard`** keeps `/etc/thermal-guard/` across a
  `sysupgrade`. Before, only `/etc/config/thermal-guard` survived: the hooks
  an operator placed over ssh, `matrix.env` for `matrix-notify`, and the
  persisted stages were lost with every flash. Stages persisted at the time of
  a flash now come back after it, the same as after a reboot; clear them before
  flashing if the cause is fixed.
- The shipped configuration leaves `trip_boost` unset, which means off. An
  image can then switch it on for its board at first boot with a uci-defaults
  script that only sets missing options, without overriding an own setting.
- Integration tests for trip management, the hung modem and the held lock run
  the daemon against a planted sysfs tree. The suite now takes about two
  minutes.
- README: why this package exists, and screenshots of the status page, the
  overview block and the configuration tabs on a Banana Pi R3 Mini and a
  GL-X3000, in `screenshots/`.
- CI installs shellcheck 0.11.0 from its release, checked against a pinned
  SHA256, instead of the Ubuntu package. Ubuntu 24.04 ships 0.9.0, which does
  not know the busybox dialect, so the lint job failed on its first run on
  GitHub without looking at a single line.

### Fixed

- **A package upgrade left the old daemon running.** procd keeps an instance
  whose command line did not change, and `thermal-guard daemon` never does, so
  after `apk add` the previous version went on running while `thermal-guard -V`
  already showed the new one. Found on the GL-X3000 with 1.4.0-r1. The package
  now restarts the service after an upgrade on a running system, only if it was
  running. Package release `1.4.0-r2`.

## 1.3.2

### Fixed

- **`thermal-guard selftest` failed on boards with a fan chip.** The case
  "nothing to read, nothing shown" assumed no hwmon fan exists; on the GL-X3000
  the real `pwm-fan` is found by name and read, which is correct. The case now
  runs only where no fan chip is present.

## 1.3.1

### Fixed

- **`thermal-guard selftest` worked in the live state directory.** It saved
  test stages into `/var/run/thermal-guard/state` under a running daemon, which
  then saw a changed `GEN` and dropped its decision ("reset during this
  cycle"), placed test hooks there, and wrote its test messages to syslog. The
  1.3.0 cases also emptied the event log, the incident history the status page
  shows. The deployment runbook runs the selftest on every board. It now works
  in a temporary directory and logs nothing. Found on the GL-MT300N-V2 right
  after installing 1.3.0.

## 1.3.0

The daemon no longer touches a fan it has not been told about. Found in the
first buildroot build: a package install starts the service at once, and on a
board without a configuration the shipped `auto` could resolve to `pwm` with an
assumed polarity of `255`/`0`, which on an inverted board stops the fan in the
stage meant to force it.

### Changed

- **`fan_mode` defaults to `none`**, in the shipped configuration and in the
  daemon when the option is missing. Most boards with a fan already regulate it,
  and this package is a protection layer, not a regulator.
- **`pwm_full` and `pwm_idle` have no default.** `fan_mode=pwm` needs both; with
  either missing the daemon logs it once and leaves the fan alone. The
  configuration page requires both when `pwm` is selected.
- **`auto` never resolves to `pwm`**, only to `cooling_device` or `none`. The
  cooling device carries its polarity in the device tree; a raw pwm output
  needs it from the operator.
- An upgrade keeps the existing configuration. Affected is only a board that set
  `auto` without a cooling device, or `pwm` without both values; the deployment
  runbook lists the cases.

### Added

- **Stage actions are read back instead of assumed.** `modem_radio_off` asks the
  modem `AT+CFUN?` afterwards and resends up to three times, because a
  collision on the AT port swallows a command without an error. A modem that
  does not confirm fails the stage, which is notified. Switching it back on at
  a reset is checked the same way.
- **`modem_radio_off_at`**: `AT+CFUN=4` (flight mode, default) or `AT+CFUN=0`
  (minimum function) for a modem that does not take 4. Nothing else is
  accepted, because the configuration page can write every option and a free
  AT command would let it reset or disable the modem.
- **`interface_down` as a stage action.** Takes `action_interface` down, or
  `uplink_interface` when that is unset, and waits for netifd to report it
  down. A reset brings it back up. Interface names are checked as UCI section
  names, in the daemon and on the page, since they reach `ifdown` and a ubus
  path; `uplink_interface` is now checked the same way.
- **The fan is shown even where another program drives it.** `fan_mode` says
  what the daemon may write, the new `fan_view` in the status file what it
  reads. Under `none` it reads the raw pwm output where `pwm_full` and
  `pwm_idle` are set, otherwise the cooling device, otherwise the raw output
  without a percentage. The raw output comes first because the kernel derives
  a cooling device's `cur_state` assuming ascending `cooling-levels`; the Banana
  Pi R3 Mini's descend (`<255 96 0>`), so full speed reads as state 0. The status
  page and the overview show the fan whenever `fan_view` names something.

### Fixed

- **A reset only undid `modem_radio_off` at stage 2 of 3 and `wifi_off` at
  stage 3**, so either action configured for the other stage stayed applied
  after a clear. Each stage's configured action is now reversed.
- **The overview block showed a pwm fan as "fan step 140 of 1"** on an inverted
  board, because it used the raw value against `pwm_full` as the maximum. It
  now shows the percentage the daemon computes, and `fan_max` is only reported
  for pwm when both polarity values are set.
- **Stage 1 of 3 promised a fan at full speed under `fan_mode=none`**, in the
  notification, on the status page and in two descriptions on the configuration
  page, and logged "could not force the fan" as if the stage had failed. It now
  says the fan is left to its own controller and logs nothing about it.

### Translations

- German: new `Leave the fan alone` (replaces `No fan`) and `Stage 1 of 3 active:
  warning, fan left to its own controller`; reworded the descriptions of the fan
  mode, `pwm_full`, `pwm_idle`, `cpu_warn` and the Actions tab.
- German: `Switch the modem radio off` (replaces `Switch the modem off
  (AT+CFUN=4)`, since the level is now configurable), and new `Take a network
  interface down`, `network interface down`, `How the modem is switched off`
  with its description, `Flight mode (AT+CFUN=4)`, `Minimum function
  (AT+CFUN=0)`, `Interface to take down` with its description.

## 1.2.0

Hardening pass over the whole package, plus the corrections that came out of
testing on a Banana Pi R3 Mini, a GL-X3000 and a GL-MT300N-V2.

### Fixed

- **One-shot commands narrated the configuration into the event log.** Every
  entry point runs the same validation, so `status`, `reset` and `test` each
  repeated whatever it found: three `thermal-guard status` calls on a board
  without a sensor produced three identical lines. The event log keeps the last
  50 entries, so a monitoring check calling `status` in a loop flushed the
  record of an actual incident out of it within the hour. Only the daemon
  reports these now. Found during deployment on a GL-MT300N-V2.
- **A reset could be undone by the cycle it interrupted.** Reading the modem
  over AT takes seconds, and a reset landing in that window was overwritten
  when the cycle saved. In the worst shape the fan was forced again right after
  being handed back, leaving it at full speed while the state said idle, with
  no way to clear it: the release was guarded by `stage >= 0`. Resets are now
  counted in `GEN` and the count is checked before acting and before saving,
  and `thermal-guard reset` releases the fan unconditionally.
- **Turning `enabled` off removed the guard instead of pausing it.**
  `start_service` registered no instance, so stages stayed applied, the fan
  stayed forced and the status file froze with its last values while the page
  kept showing an active stage. The instance now always runs and the daemon
  pauses itself.
- **The fan was addressed by hwmon number.** `hwmon2` today is `hwmon1` after
  an NVMe moves or a kernel changes, and the daemon would then write a duty
  cycle to a different chip and report success. The fan chip is looked up by
  its hwmon name.
- **`tg_fan_release` did nothing in pwm mode** unless `fan_release_command` was
  set, so the fan stayed on manual full speed after a reset.
- **A failing stage action reported success.** `tg_run_action` ended in an
  unconditional `return 0`, so a modem that could not be reached still counted
  as switched off. It now returns what the action returned, an unknown action
  name is logged, and a failed stage is notified.
- **`tg_cfg` skipped path validation and sensor detection** entirely when `uci`
  was absent.
- CI checked `70_thermal-guard.js`, which was renamed to `11_` some releases
  ago, so the `luci-syntax` job had been failing on a missing file.
- The rpcd ACL named the status file and the reset command but not the ubus
  `file` object they are reached through, nor the `/tmp/run` path that `/var`
  resolves to. Both reads and the clear button were denied for every session
  that was not root.
- **Installing `luci-app-thermal-guard` as a package did not load its ACL**
  (`1.2.0-r2`). The package's own `postinst` replaced the one `luci.mk`
  provides, which is the one that reloads rpcd, so the pages were refused until
  rpcd restarted. The own `postinst` is gone; the default drops the menu caches
  as well. Found in the first buildroot build of either package.

### Added

- **Protection stages survive a reboot.** A stage change is mirrored to
  `/etc/thermal-guard/state` and reapplied at startup. The state used to live
  only in `/var/run`, which is tmpfs, so any reboot silently cleared the
  stages and the box came back with the modem enabled and the same broken fan.
- **`pwm_idle`**, the raw value meaning slowest, as the counterpart to
  `pwm_full`. The pair carries the polarity, which several boards run inverted
  (`1` full speed, `255` stopped). The fan percentage on the status page is
  computed from it instead of assuming a rising scale.
- **A SoC sensor is looked for** when `cpu_temp_path` does not read, covering
  ramips and x86 boards that report through hwmon rather than a thermal zone.
- **"This device reports no temperature at all"** as a state of its own, told
  apart from a wrong path and shown on the status page. Some boards, the
  GL-MT300N-V2 among them, expose no sensor whatsoever.
- **A second fan controller is detected.** When a value the daemon wrote has
  been replaced, it logs which `fan_mode` avoids the fight, reasserts and
  reports it to the page.
- The status file carries `now`, `interval`, `enabled`, `no_sensor`,
  `fan_percent`, `fan_foreign` and `cpu_src`, which lets the page tell running,
  paused and stopped apart instead of showing a stale snapshot as current.
- `tests/run-integration.sh`, exercising reset, the reboot restore, a garbled
  state file and the collectd filter through the real scripts.

### Changed

- **Notifications go out over HTTP.** `notify_url` is posted to with `curl`
  where present and `uclient-fetch` otherwise; `notify_header` carries an
  authorisation token where `curl` is installed. Both go through a config file
  rather than the command line, because `/proc/*/cmdline` is readable by every
  local process, and both are rejected if they contain anything that could
  turn that config file into further directives.
- **Custom code lives in `/etc/thermal-guard/hooks/`** as executables, not in
  UCI as strings. The rpcd ACL grants write access to every option in this
  configuration, so a shell command stored there was a way for anyone who
  could reach the configuration page to run code as root. `sh -c` no longer
  appears in the package at all.
- Paths taken from UCI are checked against the subtree they belong to, in
  `tg_cfg` and again at each use site, and the config view validates the same
  prefixes.
- `thermal-guard-collectd` passes status values through an integer filter
  before building a `PUTVAL` line.
- A cooling device that no thermal zone binds is usable; the zone is only
  needed to take the device away from a governor. `cooling_device` is preferred
  where available because `max_state` means maximum cooling whichever way the
  device tree runs its `cooling-levels`, so that mode cannot get the polarity
  wrong.
- Reload is a no-op. `tg_cfg` runs every cycle, so a changed option is live
  within one interval, and restarting would drop a stage action in flight.
- The stage banner names the configured action instead of the default, so a
  box with `stage1_action=wifi_off` no longer claims the modem was switched
  off.
- German catalogue regenerated: 124 entries, 34 of them new, 11 stale ones
  removed.

### Documented

- **What this package is for.** It is a protection layer, not a fan controller,
  and where a board already has one `fan_mode=none` is the normal setting
  rather than a workaround. The built-in fan handling is for boards with
  nothing else.
- **Sharing the modem's AT port.** Overlapping AT queries return nothing
  useful and neither side reports a fault. Deploying next to a fan controller
  that queried the modem without a lock garbled that controller's reading,
  collapsed its control temperature and left the fan at its minimum on a board
  at 68 °C. The symptom was at the fan, the cause at the serial port.
- **`fan_mode=pwm` is not a regulator**, now a warning in the deployment
  runbook. Below the thresholds it writes nothing to the fan. Pausing the Banana
  Pi's `fan-control` in favour of it left `pwm1` at a stale minimum while the
  SoC climbed from 58 to 68 °C.
- **Deployment runbook, gaps found on hardware.** Check for an installed
  package (`apk info -e` / `opkg status`) and remove it through the package
  manager before deleting files by hand; the Banana Pi carried 1.1.0 as apk
  packages. The migration now lists the options this repository removed in
  1.2.0 (`notify_command` and the other `*_command` options) with their
  replacements, not only the BananaWRT variant's. `pwm_idle='255'` is set on
  the Banana Pi, and the runbook separates what a missing value does:
  `fan_percent` pinned at 100 % under `fan_mode=pwm`, empty under
  `fan_mode=none`.
- **Whether there is a kernel backstop at all.** Preferring `cooling_device`
  used to be justified by the kernel continuing to regulate while the guard is
  idle. That only holds where a thermal zone actually binds the cooling device,
  which several boards do not do, and the README now says how to check.

### Removed

- `notify_command`, `stage1_command`, `stage2_command`, `modem_temp_command`
  and `fan_release_command`. The first is replaced by `notify_url`, the next
  three by hooks of the same name, and the last by recording what the pwm chip
  was set to before the takeover and writing it back on release.

## 1.1.0

- Configuration page under System, clear button on the status page
- Other board temperature sensors reported alongside SoC and modem
- Fan mode no longer reset to `auto` on every cycle

## 1.0.0

- Staged overheating protection: force the fan, modem radio off, Wi-Fi off
- Status page, overview block and collectd feed
