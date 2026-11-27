# Review

A breakage in this package:

- The apk does not build with the OpenWrt 25.12 SDK or does not install with `apk add` on 25.12.
- A file of the staged tree or a maintainer script in the `Makefile` is lost, renamed or no longer runs under BusyBox `ash`.
- The LuCI view fails to load, saves to the wrong UCI section, or loses settings on upgrade.
- `scripts/ci-check.sh` stops covering a file that reaches the router.
- Documentation points to a script or path that no longer exists.

Skip: `dist/`, `.claude/`, wording of comments.
