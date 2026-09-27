# Building — luci-app-substore

## Prerequisites

An OpenWrt / ImmortalWrt SDK or full source tree matching the target firmware version.

## Build

Place this package under the OpenWrt tree:

```bash
cd <openwrt-sdk-or-source>
# copy or symlink the package
cp -r <path>/luci-app-substore package/
make package/luci-app-substore/compile V=s
```

The `.ipk` (or `.apk` on apk-based builds) is produced under
`bin/packages/.../luci-app-substore_*.ipk`.

> NOTE: stage-0 skeleton has not yet been built/verified on a target device.
> This document will be updated once the build chain is validated (see docs/PLAN.md stage 0).