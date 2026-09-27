#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"
./scripts/check-version-sync.sh
./scripts/check-readme.sh
./scripts/check-apk-trust.sh
find scripts -type f -name '*.sh' -exec sh -n {} +
find luci -type f -name '*.js' -exec node --check {} +
node ./scripts/test-shared.js
node ./scripts/test-overview-ui.js
python3 -m py_compile scripts/pack-ipk.py
python3 - <<'PY'
import json
from pathlib import Path
for path in Path('luci').glob('*.json'):
    json.loads(path.read_text())
    print('json OK:', path)
PY
./scripts/build-ipk.sh
if find "${BUILD_DIR:-$root/build/ipk}/stage" -type f -name '._*' | grep -q .; then
  printf 'AppleDouble metadata leaked into staged package\n' >&2
  exit 1
fi
first="$(sha256sum dist/*.ipk | awk '{print $1}')"
./scripts/build-ipk.sh
second="$(sha256sum dist/*.ipk | awk '{print $1}')"
[ "$first" = "$second" ]
git diff --check 2>/dev/null || true
printf 'ci-check OK\n'
