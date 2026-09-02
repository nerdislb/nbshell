#!/usr/bin/env bash
# Fast, offline, no-network checks that MANIFEST.toml and the PKGBUILDs it
# points at have not drifted apart. Builds nothing.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$TESTS_DIR/.." && pwd)"
BUILD_PACKAGE="$PACKAGES_DIR/scripts/build-package.sh"
MANIFEST="$PACKAGES_DIR/MANIFEST.toml"

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

echo "== test-manifest-consistency.sh =="

# 1. Schema validates.
if python3 "$PACKAGES_DIR/scripts/lib/manifest.py" load "$MANIFEST" >/dev/null 2>&1; then
    ok "MANIFEST.toml parses and passes schema validation"
else
    bad "MANIFEST.toml failed schema validation"
fi

# 2. Every [[custom]] entry's PKGBUILD is pinned to exactly the recorded
#    revision, without building anything.
mapfile -t CUSTOM_NAMES < <(python3 "$PACKAGES_DIR/scripts/lib/manifest.py" load "$MANIFEST" | python3 -c 'import json,sys; [print(e["name"]) for e in json.load(sys.stdin)["custom"]]')
for name in "${CUSTOM_NAMES[@]}"; do
    if "$BUILD_PACKAGE" "$name" --check-only >/dev/null 2>&1; then
        ok "$name: PKGBUILD matches MANIFEST.toml pin"
    else
        bad "$name: PKGBUILD does not match MANIFEST.toml pin (run: $BUILD_PACKAGE $name --check-only)"
    fi
done

# 3. Negative case: a PKGBUILD whose _commit disagrees with the manifest
#    must be rejected. Exercised against an isolated fixture tree, never
#    against the real pkgbuilds/.
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/pkgbuilds/drifted"
cat > "$FIXTURE/MANIFEST.toml" <<'EOF'
[snapshot]
date = "2026/08/01"
archive_base = "file:///nonexistent"
repos = ["core"]
arch = "x86_64"

[official]
packages = ["placeholder"]

[[custom]]
name = "drifted"
pkgbuild = "pkgbuilds/drifted"
source = "https://example.invalid/drifted.git"
revision = "1111111111111111111111111111111111111111"
description = "fixture with an intentionally mismatched pin"
EOF
cat > "$FIXTURE/pkgbuilds/drifted/PKGBUILD" <<'EOF'
pkgname=drifted
_url=https://example.invalid/drifted.git
_commit=2222222222222222222222222222222222222222
pkgver=0.0.0
pkgrel=1
pkgdesc="fixture"
arch=('x86_64')
source=("git+${_url}#commit=${_commit}")
sha256sums=('SKIP')
package() { :; }
EOF

if MANIFEST="$FIXTURE/MANIFEST.toml" "$BUILD_PACKAGE" drifted --check-only >/dev/null 2>&1; then
    bad "build-package.sh accepted a PKGBUILD whose _commit disagrees with MANIFEST.toml"
else
    ok "build-package.sh rejects a PKGBUILD pin that disagrees with MANIFEST.toml"
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
