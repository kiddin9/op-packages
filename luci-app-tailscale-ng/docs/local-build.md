# Local package builds

Build locally with the same script used by GitHub Actions. No push or release
is needed.

## Prepare

Use Ubuntu 24.04 x86_64, including under WSL2, as a regular user. Run the
commands below in the Linux shell. Install dependencies once:

```sh
sudo apt-get update
sudo apt-get install -y git build-essential flex bison gawk gcc-multilib g++-multilib gettext libncurses-dev libssl-dev python3-setuptools rsync unzip zlib1g-dev file wget curl zstd
```

## Build

Commit the changes to test locally: the script builds the current commit and
requires a clean working tree, including untracked files. From the repository
root, build APK packages for OpenWrt 25.12:

```sh
JOBS=2 bash scripts/build-packages.sh apk
```

For IPK packages targeting OpenWrt 24.10, use:

```sh
JOBS=2 bash scripts/build-packages.sh ipk
```

Outputs go to `artifacts/apk/` or `artifacts/ipk/`: the application package,
Chinese translation, `SHA256SUMS` and `build-info.txt` with the source commit
and SDK details. SDK versions and checksums are fixed in the build script.

The build host must be x86_64; the two output packages are architecture
independent. Obtain native dependencies such as Tailscale from the router's
own feeds.

## Check and test

For an APK build, verify the outputs and source commit:

```sh
cd artifacts/apk
sha256sum --check SHA256SUMS
cat build-info.txt
cd ../..
```

Back up the router's Tailscale configuration and authorization state before
testing. Transfer both packages and install them using the
[manual installation instructions](../README.md#manual-installation).
Local APK packages are unsigned and require `--allow-untrusted`.

Check installed versions, preserved settings and login, service operation,
and the translated LuCI page. If Software hides the translation package,
select **Display LuCI translation packages → all**.

## Cache

The first build is slower; later builds reuse `~/.cache/luci-app-tailscale-ng`.
Keep this cache on a Linux filesystem at a path without spaces. Delete that
directory for a fresh SDK, or `artifacts/` to discard generated packages.
Optional overrides are `BUILD_CACHE_DIR`, `OUTPUT_DIR` and `JOBS`.
