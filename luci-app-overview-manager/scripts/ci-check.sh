#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/check-version-sync.sh
./scripts/check-readme.sh
./scripts/check-apk-trust.sh
find runtime scripts -type f -name '*.sh' -exec sh -n {} +
find luci -type f -name '*.js' -exec node --check {} +
node ./scripts/test-overview-ui.js
PYTHONPYCACHEPREFIX="$root/build/pycache" \
  python3 -m py_compile scripts/po2lmo.py scripts/test-po2lmo.py
PYTHONPYCACHEPREFIX="$root/build/pycache" \
  python3 ./scripts/test-po2lmo.py
python3 - <<'PY'
import json
from pathlib import Path

for path in Path("luci").glob("*.json"):
    json.loads(path.read_text())
    print(f"json OK: {path}")
PY
./scripts/test-runtime.sh
stage="${BUILD_DIR:-$root/build}/stage"
tree_hash() {
  (cd "$stage" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum)
}
./scripts/stage-package.sh "$stage"
# The staged tree is the payload the APK installs, so check it rather than
# the sources: the build host has GNU coreutils and the router does not.
./scripts/check-busybox-compat.sh "$stage"
first="$(tree_hash)"
./scripts/stage-package.sh "$stage"
second="$(tree_hash)"
[ "$first" = "$second" ]
git diff --check 2>/dev/null || true
printf 'ci-check OK\n'
