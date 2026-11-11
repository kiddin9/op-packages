#!/bin/sh

set -eu

PKG_NAME="luci-app-tailscale-ng"
REPO="vad-b/luci-app-tailscale-ng"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
DOWNLOAD_TIMEOUT=15

log() {
	echo "[install.sh] $*"
}

fail() {
	echo "[install.sh] ERROR: $*" >&2
	exit 1
}

fetch_url() {
	if wget -q -T "${DOWNLOAD_TIMEOUT}" -O "$2" "$1"; then
		return 0
	fi
	rm -f "$2"
	log "wget failed or timed out; trying curl"

	if ! command -v curl >/dev/null 2>&1; then
		log "Installing curl with ${PKG_MGR}"
		if [ "${PKG_MGR}" = "apk" ]; then
			apk update || fail "failed to update package indexes for curl"
			apk add curl || fail "failed to install curl"
		else
			opkg update || fail "failed to update package indexes for curl"
			opkg install curl || fail "failed to install curl"
		fi
	fi

	curl -fLsS --max-time "${DOWNLOAD_TIMEOUT}" -o "$2" "$1"
}

command -v wget >/dev/null 2>&1 || fail "wget is required but not found"

if command -v apk >/dev/null 2>&1; then
	PKG_EXT="apk"
	PKG_MGR="apk"
elif command -v opkg >/dev/null 2>&1; then
	PKG_EXT="ipk"
	PKG_MGR="opkg"
else
	fail "no supported package manager found (apk/opkg)"
fi

TMP_JSON="/tmp/${PKG_NAME}-latest.json"
PKG_FILE=''

cleanup() {
	rm -f "${TMP_JSON}"
	if [ -n "${PKG_FILE}" ]; then
		rm -f "${PKG_FILE}"
	fi
}
trap cleanup EXIT

log "Detected package manager: ${PKG_MGR} (expecting .${PKG_EXT})"
log "Fetching latest release metadata"
fetch_url "${API_URL}" "${TMP_JSON}" || fail "failed to fetch release metadata"

DOWNLOAD_URL="$(grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' "${TMP_JSON}" \
	| sed -E 's/.*"([^"]+)"/\1/' \
	| grep -E "/${PKG_NAME}[^/]*\.${PKG_EXT}$" \
	| head -n 1 || true)"

[ -n "${DOWNLOAD_URL}" ] || fail "no .${PKG_EXT} asset found in latest release"

PKG_FILE="/tmp/$(basename "${DOWNLOAD_URL}")"

log "Downloading ${PKG_FILE}"
fetch_url "${DOWNLOAD_URL}" "${PKG_FILE}" || fail "failed to download package"

log "Installing ${PKG_FILE}"
if [ "${PKG_MGR}" = "apk" ]; then
	apk add --allow-untrusted --upgrade "${PKG_FILE}" || fail "apk install failed"
else
	opkg install "${PKG_FILE}" || fail "opkg install failed"
fi

log "Done"
