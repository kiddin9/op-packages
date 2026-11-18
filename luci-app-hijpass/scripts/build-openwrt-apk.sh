#!/usr/bin/env bash
set -euo pipefail

export IS_TTY=0

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p -- "${1:?Usage: build-openwrt-apk.sh OUTPUT_DIR}"
output_dir=$(cd -- "$1" && pwd -P)
build_dir=$(mktemp -d /tmp/hijpass-sdk.XXXXXX)
trap 'rm -rf -- "$build_dir"' EXIT

sdk_version=25.12.6
sdk_name=openwrt-sdk-$sdk_version-x86-64_gcc-14.3.0_musl.Linux-x86_64
sdk_sha256=1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc
sdk_dir="$build_dir/$sdk_name"
feeds_dir="$build_dir/feeds"

cd "$build_dir"
curl -fLSs --retry 3 -o "$sdk_name.tar.zst" \
    "https://downloads.openwrt.org/releases/$sdk_version/targets/x86/64/$sdk_name.tar.zst"
printf '%s  %s\n' "$sdk_sha256" "$sdk_name.tar.zst" | sha256sum -c -
tar -I zstd -xf "$sdk_name.tar.zst"

fetch_feed() {
    local feed=$1 repository=$2 revision
    revision=$(awk -v feed="$feed" 'NF >= 3 && $(NF - 1) == feed { sub(/.*\^/, "", $NF); print $NF }' \
        "$sdk_dir/feeds.conf.default")
    if [[ ! $revision =~ ^[0-9a-f]{40}$ ]]; then
        printf 'Missing SDK revision for feed %s\n' "$feed" >&2
        return 1
    fi
    mkdir -p "$feeds_dir/$feed"
    curl -fLSs --retry 3 -o "$feed.tar.gz" \
        "https://codeload.github.com/openwrt/$repository/tar.gz/$revision"
    tar -xzf "$feed.tar.gz" -C "$feeds_dir/$feed" --strip-components=1
}

fetch_feed base openwrt
fetch_feed packages packages
fetch_feed luci luci

# OpenWrt 25.12.6's official feeds do not ship these runtime packages.
immortalwrt_revision=e93a938c63124832d549c41da3157e2ec40fbe05
for package in geoview chinadns-ng; do
    recipe_dir="$feeds_dir/packages/net/$package"
    mkdir -p "$recipe_dir"
    curl -fLSs --retry 3 -o "$recipe_dir/Makefile" \
        "https://raw.githubusercontent.com/immortalwrt/packages/$immortalwrt_revision/net/$package/Makefile"
done

mkdir "$feeds_dir/hijpass"
ln -s "$project_dir" "$feeds_dir/hijpass/luci-app-hijpass"

cd "$sdk_dir"
cat > feeds.conf <<EOF
src-link base $feeds_dir/base/package
src-link packages $feeds_dir/packages
src-link luci $feeds_dir/luci
src-link hijpass $feeds_dir/hijpass
EOF
./scripts/feeds update -a
./scripts/feeds install -p hijpass luci-app-hijpass

cat > .config <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_ALL is not set
CONFIG_PACKAGE_luci-app-hijpass=m
EOF
make defconfig

# Build LuCI's host-side translation compiler and package only this app.
luci_src=feeds/luci/modules/luci-base/src
make -C "$luci_src" po2lmo
install -m 0755 "$luci_src/po2lmo" staging_dir/host/bin/
# Translation packages are hidden in Kconfig and normally selected by luci-base.
make -j"$(nproc)" package/feeds/hijpass/luci-app-hijpass/compile NO_DEPS=1 V=s \
    CONFIG_PACKAGE_luci-i18n-hijpass-zh-cn=m

shopt -s nullglob
app_packages=(bin/packages/x86_64/hijpass/luci-app-hijpass-*.apk)
translation_packages=(bin/packages/x86_64/hijpass/luci-i18n-hijpass-zh-cn-*.apk)
if (( ${#app_packages[@]} != 1 || ${#translation_packages[@]} != 1 )); then
    printf 'Expected one HiJpass APK and one Simplified Chinese translation APK\n' >&2
    exit 1
fi
staging_dir/host/bin/apk --allow-untrusted verify "${app_packages[@]}" "${translation_packages[@]}"
install -m 0644 "${app_packages[@]}" "${translation_packages[@]}" "$output_dir/"
