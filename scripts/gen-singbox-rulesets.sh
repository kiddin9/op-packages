#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RULESET_DIR="${ROOT_DIR}/clashoo/files/usr/share/clashoo/ruleset"
TMP_DIR="$(mktemp -d)"
GEOSITE_BASE="${GEOSITE_BASE:-https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite}"
GEOIP_BASE="${GEOIP_BASE:-https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip}"
# mihomo .mrs lives on the meta branch (binary, not .srs)
META_GEOSITE_BASE="${META_GEOSITE_BASE:-https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite}"

cleanup() {
	rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

fetch_ruleset() {
	tag="$1"
	base="$2"
	remote_name="${3:-$tag}"
	url="${base}/${remote_name}.srs"
	tmp_file="${TMP_DIR}/${tag}.srs"
	out_file="${RULESET_DIR}/${tag}.srs"

	echo "fetch ${tag}.srs"
	curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$tmp_file"
	[ -s "$tmp_file" ] || {
		echo "empty ruleset: $url" >&2
		exit 1
	}
	mv "$tmp_file" "$out_file"
}

mkdir -p "$RULESET_DIR"
rm -f "${RULESET_DIR}"/*.srs

# Minimal built-in set:
# - geolocation-!cn: required by fake-ip DNS and broad non-CN routing.
# - geosite-cn: local alias for subscription tags geolocation-cn/cn.
# - cn-ip/private-ip: keep China/private IP direct without remote downloads.
fetch_ruleset "geolocation-!cn" "$GEOSITE_BASE"
fetch_ruleset "geosite-cn" "$GEOSITE_BASE" geolocation-cn
fetch_ruleset "private-ip" "$GEOIP_BASE" private
fetch_ruleset "cn-ip" "$GEOIP_BASE" cn

# mihomo cn.mrs replaces geosite:cn in fake-ip-filter so the core skips geosite.dat
echo "fetch cn.mrs"
curl -fsSL --retry 3 --retry-delay 2 "${META_GEOSITE_BASE}/cn.mrs" -o "${TMP_DIR}/cn.mrs"
[ -s "${TMP_DIR}/cn.mrs" ] || {
	echo "empty ruleset: ${META_GEOSITE_BASE}/cn.mrs" >&2
	exit 1
}
mv "${TMP_DIR}/cn.mrs" "${RULESET_DIR}/cn.mrs"

echo "generated sing-box rule sets in ${RULESET_DIR}"
