#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# Use Linux tools only, including when invoked from WSL with Windows PATH entries.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

format="${1:-apk}"
case "$format" in
  apk)
    sdk_version=25.12.6
    sdk_file=openwrt-sdk-25.12.6-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst
    sdk_url="https://downloads.openwrt.org/releases/$sdk_version/targets/x86/64/$sdk_file"
    sdk_sha256=1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc
    ;;
  ipk)
    sdk_version=24.10.4
    sdk_file=openwrt-sdk-24.10.4-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst
    sdk_url="https://archive.openwrt.org/releases/$sdk_version/targets/x86/64/$sdk_file"
    sdk_sha256=229e871f734a2cee5ce3ad6a3e98d3836b0899bfdeaea4d9c2c5cc7b1fce1407
    ;;
  *) printf 'Usage: %s [apk|ipk]\n' "$0" >&2; exit 1 ;;
esac

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cache_dir="${BUILD_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/luci-app-tailscale-ng}"
output_dir="${OUTPUT_DIR:-$source_dir/.dev/build-packages/artifacts/$format}"
jobs="${JOBS:-$(nproc)}"

if [[ "$(id -u)" == 0 ]]; then
  printf 'Run the SDK build as a regular Linux user.\n' >&2
  exit 1
fi
if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
  printf 'Commit the source changes first; the build uses an exact Git snapshot.\n' >&2
  exit 1
fi
source_commit="$(git -C "$source_dir" rev-parse HEAD)"

mkdir -p "$cache_dir/downloads" "$output_dir"
cache_dir="$(realpath "$cache_dir")"
output_dir="$(realpath "$output_dir")"
sdk_dir="$cache_dir/sdk-$sdk_version"
archive="$cache_dir/downloads/$sdk_file"
if [[ "$sdk_dir" == *[[:space:]]* ]]; then
  printf 'The SDK cache path must not contain whitespace.\n' >&2
  exit 1
fi

if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "$sdk_url" --output "$archive.part"
  mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$sdk_sha256" "$archive" | sha256sum --check

if [[ ! -f "$sdk_dir/.sdk-ready" ]]; then
  mkdir -p "$sdk_dir"
  tar --zstd -xf "$archive" -C "$sdk_dir" --strip-components=1
  touch "$sdk_dir/.sdk-ready"
fi

# Export only committed source: no deployment credentials or private notes.
package_dir="$sdk_dir/package/luci-app-tailscale-ng"
rm -rf -- "$package_dir"
mkdir -p "$package_dir"
git -C "$source_dir" archive "$source_commit" | tar -xf - -C "$package_dir"
package_version="$(sed -n 's/^PKG_VERSION:=//p' "$package_dir/Makefile")"
package_release="$(sed -n 's/^PKG_RELEASE:=//p' "$package_dir/Makefile")"

cd "$sdk_dir"
# Keep the release SDK's pinned feed revisions instead of tracking moving branches.
if [[ ! -f .feeds-ready ]]; then
  ./scripts/feeds update -a
  touch .feeds-ready
fi
./scripts/feeds uninstall -a
./scripts/feeds install tailscale luci-base

cat > .config <<EOF
CONFIG_ALL_NONSHARED=n
CONFIG_ALL_KMODS=n
CONFIG_ALL=n
CONFIG_AUTOREMOVE=n
CONFIG_SIGNED_PACKAGES=n
CONFIG_PACKAGE_luci-app-tailscale-ng=m
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-tailscale-ng-zh-cn=m
EOF
make defconfig
grep -qx 'CONFIG_PACKAGE_luci-i18n-tailscale-ng-zh-cn=m' .config
make package/luci-app-tailscale-ng/clean
make -j"$jobs" package/luci-app-tailscale-ng/compile V=s

# Require both outputs; a successful app build alone does not deliver a translation.
find "$output_dir" -maxdepth 1 -type f \( \
  -name "luci-app-tailscale-ng[-_]*.$format" -o \
  -name "luci-i18n-tailscale-ng-zh-cn[-_]*.$format" \) -delete
for package in luci-app-tailscale-ng luci-i18n-tailscale-ng-zh-cn; do
  mapfile -t files < <(find bin/packages -type f -name "${package}[-_]${package_version}-r${package_release}[._]*${format}")
  if [[ "${#files[@]}" != 1 ]]; then
    printf 'Expected one %s package, found %s.\n' "$package" "${#files[@]}" >&2
    exit 1
  fi
  cp "${files[0]}" "$output_dir/"
done

{
  printf 'source_commit=%s\n' "$source_commit"
  printf 'sdk_version=%s\nsdk_sha256=%s\nformat=%s\n' "$sdk_version" "$sdk_sha256" "$format"
  cat feeds.conf.default
} > "$output_dir/build-info.txt"
(cd "$output_dir" && sha256sum -- *."$format" > SHA256SUMS)
printf '\nPackages saved to %s\n' "$output_dir"
