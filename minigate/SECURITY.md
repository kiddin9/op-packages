# Security Policy

MiniGate touches gateway-facing features such as DDNS, ACME certificates,
reverse proxy configuration, LuCI access, login-failure monitoring, and
nftables bans. Please report security issues responsibly.

## Supported Versions

Security fixes are targeted at the latest release published on GitHub
Releases. Users should upgrade to the latest release before reporting issues
that may already be fixed.

## Reporting a Vulnerability

If you find a vulnerability, please do not publish exploit details in a public
issue before it has been reviewed.

Report privately by email:

- tpxcer28@gmail.com

Please include:

- affected MiniGate version
- OpenWrt or ImmortalWrt version
- installation method, such as IPK, source install, or SDK build
- affected feature, such as DDNS, ACME, reverse proxy, login guard, or LuCI UI
- clear reproduction steps
- expected impact

I will try to acknowledge valid reports within 7 days and coordinate a fix or
mitigation in a release when appropriate.

## Scope

In scope:

- command injection or unsafe shell argument handling
- configuration injection in generated Nginx, ACME, DDNS, or nftables files
- authentication or authorization bypass in LuCI pages
- unsafe handling of API tokens, certificates, private keys, or ban records
- issues that weaken direct-IP or unknown-Host rejection behavior

Out of scope:

- vulnerabilities in upstream OpenWrt, ImmortalWrt, LuCI, Nginx, Cloudflare, or
  Let's Encrypt components
- reports that require compromised router root access as the only prerequisite
- denial-of-service reports without a realistic router-facing impact

## Disclosure

Please allow time for investigation and patching before public disclosure. Once
a fix is available, the release notes will mention the security-relevant change
without exposing unnecessary exploit details.
