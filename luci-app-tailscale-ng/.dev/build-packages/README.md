# Build Packages

Build installable OpenWrt packages with [build-packages.sh](build-packages.sh), the same script used by [GitHub Actions](../../.github/workflows/releases.yml). No push or release is required.

Run the commands below from the repository root in Bash.

## Requirements

- Ubuntu 24.04 x86_64, including under WSL2, running as a regular user.
- A clean Git working tree, including untracked files. The script builds the current commit.

## Setup

Install the build dependencies once:

```bash
sudo apt-get update
sudo apt-get install -y git build-essential flex bison gawk gcc-multilib g++-multilib gettext libncurses-dev libssl-dev python3-setuptools rsync unzip zlib1g-dev file wget curl zstd
```

Commit the source changes you want to build. SDK versions and checksums are fixed in the script; the SDK is downloaded on first use.

## Usage

Build APK packages for OpenWrt 25.12:

```bash
JOBS=2 bash .dev/build-packages/build-packages.sh apk
```

For IPK packages targeting OpenWrt 24.10:

```bash
JOBS=2 bash .dev/build-packages/build-packages.sh ipk
```

Outputs go to `.dev/build-packages/artifacts/apk/` or `.dev/build-packages/artifacts/ipk/`: the application package, Chinese translation, `SHA256SUMS` and `build-info.txt`. The metadata records the source commit and SDK details.

Packages are architecture independent. Obtain native dependencies such as `tailscale` from the router's own feeds.

## Verification

For an APK build, check the output checksums and source commit:

```bash
cd .dev/build-packages/artifacts/apk
sha256sum --check SHA256SUMS
cat build-info.txt
cd ../../../..
```

Back up the router's Tailscale configuration and authorization state before testing. Transfer both packages and follow the [manual installation instructions](../../README.md#manual-installation). Local APK packages are unsigned and require `--allow-untrusted`.

Check installed versions, preserved settings and login, service operation, and the translated LuCI page. If Software hides the translation package, select **Display LuCI translation packages → all**.

## Configuration

- `BUILD_CACHE_DIR` — SDK download and build cache directory; defaults to `${XDG_CACHE_HOME:-$HOME/.cache}/luci-app-tailscale-ng`.
- `OUTPUT_DIR` — Package and metadata output directory; defaults to `.dev/build-packages/artifacts/<format>/`.
- `JOBS` — Parallel build jobs; defaults to the number of available CPUs.

Keep the SDK cache on a Linux filesystem at a path without spaces. The default output directories are ignored by Git.

## Cleanup

Delete the SDK cache directory for a fresh SDK, or `.dev/build-packages/artifacts/` to discard generated packages.

## CI and Releases

The [workflow](../../.github/workflows/releases.yml) builds both formats for relevant pushes to `main`, pull requests and manual runs. A successful run on `main` publishes a release when `PKG_VERSION` differs from the latest release. Update `PKG_VERSION` for each new release and keep `PKG_RELEASE:=1` fixed. Release tags and titles use `v<PKG_VERSION>`.
