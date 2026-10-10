#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
PACKAGE_JSON="$ROOT_DIR/frontend/package.json"
LOCK_JSON="$ROOT_DIR/frontend/package-lock.json"
TS_CONFIG="$ROOT_DIR/frontend/tsconfig.json"
SRC="$ROOT_DIR/frontend/src"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# npm ci requires the manifest and lockfile to describe the same exact version.
jq -e '.dependencies.preact == "11.0.1" and .devDependencies["@preact/preset-vite"] == "2.10.6"' \
  "$PACKAGE_JSON" >/dev/null || fail 'Preact 11.0.1 and the supported Vite preset must be pinned'
jq -e '.lockfileVersion == 3 and .packages[""].dependencies.preact == "11.0.1" and .packages["node_modules/preact"].version == "11.0.1" and .packages["node_modules/preact"].resolved == "https://registry.npmjs.org/preact/-/preact-11.0.1.tgz"' \
  "$LOCK_JSON" >/dev/null || fail 'the lockfile must resolve the same Preact 11.0.1 tarball'
jq -e '.compilerOptions.jsx == "react-jsx" and .compilerOptions.jsxImportSource == "preact"' \
  "$TS_CONFIG" >/dev/null || fail 'the Preact JSX transform must remain enabled'

# Preact 11 moved these types from JSX to the top-level preact namespace.
if grep -R -E -q 'JSX\.(CSSProperties|SVGAttributes|Targeted(Event|KeyboardEvent|SubmitEvent))' "$SRC"; then
  fail 'legacy JSX namespace types cannot be used with Preact 11'
fi

for check in \
  'components/CustomSelect.tsx:CSSProperties' \
  'components/Icons.tsx:SVGAttributes' \
  'login/LoginApp.tsx:TargetedKeyboardEvent' \
  'login/LoginApp.tsx:TargetedSubmitEvent' \
  'pages/ConnectedDevicesPage.tsx:TargetedEvent' \
  'pages/InitialPasswordSetupPage.tsx:TargetedKeyboardEvent' \
  'pages/LanPage.tsx:TargetedSubmitEvent' \
  'pages/SafeShieldRulesPage.tsx:TargetedEvent' \
  'pages/WanPage.tsx:TargetedSubmitEvent' \
  'pages/WifiPage.tsx:TargetedSubmitEvent'; do
  file=${check%%:*}
  type=${check#*:}
  grep -Fq "$type" "$SRC/$file" || fail "$file must use Preact 11's $type"
done


# Preact 11 checks each input type against a distinct accessible-input union.
# Keep the password visibility branches as literal-valued discriminated props.
assert_password_visibility() {
  path=$1
  condition=$2
  expected=$3
  count=$(grep -Fc "{...($condition ? { type: 'text' as const } : { type: 'password' as const })}" "$SRC/$path" || true)
  [ "$count" -eq "$expected" ] || fail "$path must use literal-preserving input type branches ($expected expected, got $count)"
}

assert_password_visibility 'login/LoginApp.tsx' showPassword 1
assert_password_visibility 'pages/InitialPasswordSetupPage.tsx' showPassword 2
assert_password_visibility 'pages/SettingsPage.tsx' visible 1
assert_password_visibility 'pages/WanPage.tsx' showPassword 1

# Keep the main landmark semantic; put live region roles on the inner card.
grep -Fq '<main class="ssh-initial-setup-probe">' "$SRC/app/AuthenticatedEntry.tsx" \
  || fail 'the initial setup probe must preserve the main landmark'
grep -Fq '<div class="ssh-initial-setup-probe-card" role={phase === '\''error'\'' ? '\''alert'\'' : '\''status'\''}>' \
  "$SRC/app/AuthenticatedEntry.tsx" \
  || fail 'the setup probe card must announce status/error updates'

echo 'PASS: Preact 11 accessible input types and setup status roles are compatible'
