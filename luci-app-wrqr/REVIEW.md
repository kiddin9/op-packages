# Review

A breakage in this package:

- The apk does not build with the OpenWrt 25.12 SDK or does not install with `apk add` on 25.12.
- `CONTROL/postinst` or `CONTROL/prerm` is lost from the staged tree or leaks into the payload.
- The QR page fails to load, shows a wrong network or leaks a key it should not show.
- `scripts/ci-check.sh` stops covering a file that reaches the router.
- Documentation points to a script or path that no longer exists.

Skip: `dist/`, `.claude/`, wording of comments.
