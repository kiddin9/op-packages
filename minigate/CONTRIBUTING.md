# Contributing to MiniGate

Thanks for considering a contribution. MiniGate is a small OpenWrt LuCI
application, so focused and testable changes are easiest to review.

## Useful Areas

- OpenWrt and ImmortalWrt compatibility fixes
- LuCI UI improvements
- DDNS and ACME reliability
- reverse proxy safety and generated Nginx configuration
- login guard detection, nftables recovery, and ban-list handling
- installation, upgrade, and release packaging
- documentation and screenshots

## Development Notes

Please keep changes compatible with `/bin/sh` on OpenWrt. Avoid Bash-only
syntax in router-side scripts.

Before opening a pull request:

1. Run shell scripts with `sh` where possible.
2. Check that generated configuration paths are explicit and conservative.
3. Test installation or upgrade on an OpenWrt/ImmortalWrt device or VM when the
   change affects runtime behavior.
4. Update README or release notes when user-facing behavior changes.

## Releases

Use the Asia/Shanghai publication date as `YYYY.M.D`. The first release on a
date has no suffix; further releases use `-1`, `-2`, and so on. Tags start with
`v`. Never replace an existing release with different code.

Update `PKG_VERSION` in `Makefile` and `scripts/build-ipk.sh`, and
`CURRENT_VERSION` in `root/usr/lib/minigate/update.sh` together. Add the actual
release notes in `releases/v<VERSION>.md` and update README download examples.
Run `node --test tests/install.test.cjs tests/update.test.cjs` before pushing a commit containing
`[release]` to `main`. The workflow validates the date, next sequence, and
matching versions before building and publishing.

## Pull Requests

Good pull requests usually include:

- a short problem statement
- what changed
- how it was tested
- screenshots for LuCI UI changes
- any compatibility notes for opkg, apk, or SDK builds

Security-sensitive changes should follow `SECURITY.md` and avoid publishing
exploit details before a fix is ready.
