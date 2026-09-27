# Development

## Checks

```sh
./scripts/ci-check.sh
```

## Building

The IPK for OpenWrt 24.10 is written to `dist/` by `scripts/build-ipk.sh`. The
APK for OpenWrt 25.12 needs a compatible SDK:

```sh
OPENWRT_SDK_DIR=/path/to/openwrt-sdk-25.12.5-mediatek-filogic \
  ./scripts/build-apk.sh
```

A release APK is signed with the shared publisher key by
`scripts/build-apk-release.sh`, which reads the key from
`OPENWRT_APK_SIGNING_KEY`.

The private half of the publisher key is not stored in any repository. This
repository builds and signs only its own package and publishes it as a release
asset; the index is assembled by
[Nikitid/openwrt-feed](https://github.com/Nikitid/openwrt-feed). See
[Joining the shared feed](https://github.com/Nikitid/openwrt-feed/blob/main/docs/MEMBER_INTEGRATION.md).

## Release

Push a `vX.Y.Z` tag matching the version in `release.env`. The release workflow
checks the tag, runs `scripts/ci-check.sh`, builds and signs the APK with the
pinned OpenWrt SDK, and publishes the release with notes made by
`scripts/release-notes.sh` from the commit subjects since the previous tag.
