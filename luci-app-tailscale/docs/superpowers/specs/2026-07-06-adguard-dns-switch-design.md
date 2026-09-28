# AdGuard DNS Auto Switch Design

## Goal

Add an optional AdGuard DNS auto-switch feature to `luci-app-tailscale`.

The feature lets OpenWrt LAN clients use Headscale DNS Records while Tailscale is healthy, and automatically fall back to public DNS behavior while Tailscale DNS is unhealthy. Tailscale itself keeps its official behavior; OpenWrt may run with either `accept_dns=1` or `accept_dns=0` because the switch health check queries `100.100.100.100` directly.

This is intended for setups where OpenWrt runs local AdGuard Home as the LAN DNS entry point.

## Non-Goals

- Do not modify Tailscale's native DNS behavior.
- Do not add or maintain per-service DNS records in OpenWrt.
- Do not introduce a separate DNS server.
- Do not require users to know or edit the AdGuard Home config file path.
- Do not depend on dnsmasq layout, except for user-provided upstream entries such as `[/lan/]127.0.0.1:5353`.

## User Model

Users maintain DNS records in two authoritative places:

- Internal overrides in Headscale DNS Records.
- Public records in public DNS, such as AliDNS.

Each OpenWrt instance only configures a default public upstream list and a small set of Tailnet conditional upstreams.

## Profiles

The switch manages AdGuard Home `upstream_dns`.

### Down Profile

The down profile is the user-configured default upstream list. Example:

```text
[/lan/]127.0.0.1:5353
223.5.5.5
223.6.6.6
119.29.29.29
```

This is used when Tailscale DNS is unhealthy. Example outcomes:

- `sso.litata.com` resolves through public DNS.
- `tailscale.litata.com` resolves through public DNS.
- `deploy.litata.com` resolves through public DNS.
- `code.litata.com` returns public DNS behavior, normally `NXDOMAIN` if no public record exists.

### Up Profile

The up profile is:

```text
default upstreams + tailnet conditional upstreams
```

Example:

```text
[/lan/]127.0.0.1:5353
[/litata.tailnet/]100.100.100.100
[/litata.com/]100.100.100.100
223.5.5.5
223.6.6.6
119.29.29.29
```

This is used when Tailscale DNS is healthy. Example outcomes:

- `sso.litata.com` resolves to the Headscale DNS Record internal IP and avoids public OTP policy.
- `code.litata.com` resolves to the Headscale DNS Record internal IP.
- `deploy.litata.com` falls through Headscale split DNS to public DNS.
- `litata.tailnet` names resolve through MagicDNS.

## Health Check

The switch determines health by querying the configured health check domain through the configured Tailnet DNS server.

Example:

```sh
nslookup sso.litata.com 100.100.100.100
```

The result is healthy only when at least one returned IP equals one of the configured expected IPs, for example `10.10.6.156`.

Recommended hysteresis:

- Switch to up after 2 consecutive successful checks.
- Switch to down after 2 consecutive failed checks.
- Default check interval: 10 seconds.

## Strong Enablement Checks

The feature must not start unless all checks pass:

- AdGuardHome process is running.
- Port 53 is listened by AdGuardHome.
- LAN DHCP explicitly advertises the OpenWrt LAN IP as DNS, for example `6,192.168.100.1`.
- AdGuard API is reachable and writable.
- The Tailnet DNS health check can return the expected IP at least once.

LuCI must show failing checks and block enabling the feature until they pass.

## AdGuard Integration

Use AdGuard Home HTTP API rather than exposing `/etc/AdGuardHome.yaml` in LuCI.

Default API base URL:

```text
http://127.0.0.1:3000
```

The implementation should support authenticated AdGuard instances with username and password. The password must be treated like the Tailscale auth key: do not echo it back in LuCI; show a configured placeholder and keep the existing value when the field is empty.

API operations:

- Read current DNS config.
- Write `upstream_dns` for the selected profile.
- Clear cache after profile changes when configured.

If API write fails, keep the last known profile and log the error.

## Runtime Components

Add an independent script:

```text
/usr/sbin/tailscale_adguard_dns_switch
```

Responsibilities:

- Read UCI configuration.
- Run strong preflight checks.
- Poll health state.
- Apply the up or down AdGuard profile.
- Clear AdGuard cache after profile changes.
- Log state changes and rate-limit repeated failures.

Add a named procd instance under the existing `/etc/init.d/tailscale` service.

Responsibilities:

- Start only when the feature is enabled.
- Run the switch script in loop mode.
- Restart on failure via procd respawn.
- Reload when `tailscale` UCI changes.
- Apply the down profile during Tailscale service stop/reload so persisted AdGuard upstreams do not keep pointing at Tailnet DNS after the watcher stops.

## LuCI Configuration

Add an "AdGuard DNS Auto Switch" section to the existing Tailscale settings page.

Fields:

- Enable AdGuard DNS auto switch.
- Default upstream DNS list.
- Tailnet conditional upstream DNS list.
- Health check domain.
- Expected health check IP list.
- Check interval.
- Success threshold.
- Failure threshold.
- Clear AdGuard cache after switching.
- AdGuard API URL.
- AdGuard username.
- AdGuard password.

The section should include a read-only status panel for the strong enablement checks.

## Cache Policy

Keep AdGuard DNS cache disabled by default for this feature.

If cache is enabled by the user, the switch should clear AdGuard cache after each profile change. Users that want caching should use a short maximum TTL such as 30 seconds and keep optimistic cache disabled.

Tailscale DNS TTL is not controlled by this feature.

## Testing

Add shell tests for the switch script:

- Profile generation from default and Tailnet upstream lists.
- Healthy result detection from `nslookup` output.
- Up transition after configured success threshold.
- Down transition after configured failure threshold.
- AdGuard API payload generation.
- Missing/invalid configuration handling.
- Preflight failure behavior.

Existing `tailscale_keepalive` tests must continue passing.

Manual verification on OpenWrt should cover:

- Up profile makes `sso.litata.com` resolve to the internal Headscale DNS Record IP.
- Down profile makes `sso.litata.com` resolve through public DNS.
- `code.litata.com` fails in down state when no public record exists.
- `deploy.litata.com` resolves through public DNS in both states.
- Tailscale can restart and reconnect without self-bootstrap DNS failure.
