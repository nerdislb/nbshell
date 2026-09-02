#!/usr/bin/env bash
# End-to-end exercise of fetch-official-packages.sh -> build-package.sh ->
# make-repo.sh -> verify-repo.sh against a small, fully offline fixture
# manifest -- never against the real MANIFEST.toml, since that pulls in a
# real Wayland compositor build and a full Arch package set that do not
# belong in a fast test.
#
# Every "official" and "custom" package class in the fixture manifest maps
# 1:1 to a class in the real one (official snapshot packages, a git-pinned
# custom package, a local/dirty-tree-checked custom package), so a failure
# here is a real signal about the real pipeline's logic.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPTS_DIR="$PACKAGES_DIR/scripts"

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

echo "== test-repo-pipeline.sh =="

ROOT="$(mktemp -d)"
trap 'rm -rf -- "$ROOT"' EXIT

# ---------------------------------------------------------------------------
# 1. Build a tiny fixture "Arch Linux Archive" snapshot: two official
#    packages (core + extra) served over file://, so fetch-official-
#    packages.sh's real download/verify/checksum logic runs unmodified.
# ---------------------------------------------------------------------------
ARCHIVE="$ROOT/archive"
SNAP_DATE="2026/08/01"

build_fixture_pkg() {
    local name="$1" builddir="$2"
    mkdir -p "$builddir"
    cat > "$builddir/PKGBUILD" <<EOF
pkgname=$name
pkgver=1.0
pkgrel=1
pkgdesc="fixture package $name"
arch=('x86_64')
license=('MIT')
package() { install -Dm644 /dev/null "\$pkgdir/usr/share/$name/marker"; }
EOF
    ( cd "$builddir" && PKGDEST="$builddir" makepkg --noconfirm >/dev/null 2>&1 )
}

for spec in "core:fixture-core-pkg" "extra:fixture-extra-pkg"; do
    repo="${spec%%:*}"; name="${spec##*:}"
    repo_dir="$ARCHIVE/$SNAP_DATE/$repo/os/x86_64"
    build_fixture_pkg "$name" "$ROOT/build-$name"
    mkdir -p "$repo_dir"
    cp "$ROOT/build-$name/$name"-*.pkg.tar.zst "$repo_dir/"
    ( cd "$repo_dir" && repo-add --quiet "$repo.db.tar.gz" ./*.pkg.tar.zst >/dev/null 2>&1 )
done

# ---------------------------------------------------------------------------
# 2. A fixture "local" source tree (stands in for nbshell): a real git repo
#    so the clean/dirty check exercises real git, not a mock.
# ---------------------------------------------------------------------------
LOCAL_SRC="$ROOT/local-src"
mkdir -p "$LOCAL_SRC"
git -C "$LOCAL_SRC" init -q
git -C "$LOCAL_SRC" config user.email test@example.invalid
git -C "$LOCAL_SRC" config user.name "Test"
echo "hello" > "$LOCAL_SRC/payload.txt"
git -C "$LOCAL_SRC" add payload.txt
git -C "$LOCAL_SRC" commit -q -m "initial"

# ---------------------------------------------------------------------------
# 3. Fixture manifest tying it all together: 2 official + 1 git-pinned
#    custom ("fixture-git", built from *this* real filesystem as its own
#    tiny git repo) + 1 local custom ("fixture-local", from LOCAL_SRC).
# ---------------------------------------------------------------------------
GIT_SRC="$ROOT/git-src"
mkdir -p "$GIT_SRC"
git -C "$GIT_SRC" init -q
git -C "$GIT_SRC" config user.email test@example.invalid
git -C "$GIT_SRC" config user.name "Test"
echo "v1" > "$GIT_SRC/file.txt"
git -C "$GIT_SRC" add file.txt
git -C "$GIT_SRC" commit -q -m "v1"
GIT_COMMIT="$(git -C "$GIT_SRC" rev-parse HEAD)"

MANIFEST_DIR="$ROOT/manifest-root"
mkdir -p "$MANIFEST_DIR/pkgbuilds/fixture-git" "$MANIFEST_DIR/pkgbuilds/fixture-local"

cat > "$MANIFEST_DIR/MANIFEST.toml" <<EOF
[snapshot]
date = "$SNAP_DATE"
archive_base = "file://$ARCHIVE"
repos = ["core", "extra"]
arch = "x86_64"

[official]
packages = ["fixture-core-pkg", "fixture-extra-pkg"]

[[custom]]
name = "fixture-git"
pkgbuild = "pkgbuilds/fixture-git"
source = "file://$GIT_SRC"
revision = "$GIT_COMMIT"
description = "fixture git-sourced package"

[[custom]]
name = "fixture-local"
pkgbuild = "pkgbuilds/fixture-local"
source = "local"
revision = "HEAD"
description = "fixture local-source package"
EOF

cat > "$MANIFEST_DIR/pkgbuilds/fixture-git/PKGBUILD" <<EOF
pkgname=fixture-git
_url=file://$GIT_SRC
_commit=$GIT_COMMIT
pkgver=1.0.r0.g\${_commit:0:8}
pkgrel=1
pkgdesc="fixture git-sourced package"
arch=('x86_64')
source=("git+\${_url}#commit=\${_commit}")
sha256sums=('SKIP')
package() { install -Dm644 /dev/null "\$pkgdir/usr/share/fixture-git/marker"; }
EOF

cat > "$MANIFEST_DIR/pkgbuilds/fixture-local/PKGBUILD" <<'EOF'
pkgname=fixture-local
pkgver=1.0
pkgrel=1
pkgdesc="fixture local-source package"
arch=('x86_64')
source=("fixture-local-src.tar.gz")
sha256sums=('SKIP')
package() {
    install -dm755 "$pkgdir/usr/share/fixture-local"
    cp -a --no-preserve=ownership "$srcdir"/* "$pkgdir/usr/share/fixture-local"/
}
EOF

export MANIFEST="$MANIFEST_DIR/MANIFEST.toml"
export CACHE_OFFICIAL="$ROOT/cache/official"
export CACHE_CUSTOM="$ROOT/cache/custom"
REPO_DIR="$ROOT/repo/nbshell/os/x86_64"

# We need build-package.sh's SRC_ROOT resolution (git rev-parse --show-
# toplevel from the manifest dir) to land on LOCAL_SRC for the "local"
# fixture entry, so run it with the manifest copied alongside that tree
# instead -- simplest is to point MANIFEST_DIR-relative local resolution
# by placing the local pkgbuild lookup under LOCAL_SRC itself.
mkdir -p "$LOCAL_SRC/iso-packages/pkgbuilds/fixture-local"
cp "$MANIFEST_DIR/MANIFEST.toml" "$LOCAL_SRC/iso-packages/MANIFEST.toml"
cp "$MANIFEST_DIR/pkgbuilds/fixture-local/PKGBUILD" "$LOCAL_SRC/iso-packages/pkgbuilds/fixture-local/PKGBUILD"
# fixture-git isn't built from this manifest copy, only fixture-local is;
# point its pkgbuild dir here too so the manifest stays internally valid.
mkdir -p "$LOCAL_SRC/iso-packages/pkgbuilds/fixture-git"
cp "$MANIFEST_DIR/pkgbuilds/fixture-git/PKGBUILD" "$LOCAL_SRC/iso-packages/pkgbuilds/fixture-git/PKGBUILD"
git -C "$LOCAL_SRC" add -A
git -C "$LOCAL_SRC" commit -q -m "add manifest fixtures"

LOCAL_MANIFEST="$LOCAL_SRC/iso-packages/MANIFEST.toml"

# ---------------------------------------------------------------------------
# 4. Run the real pipeline scripts against the fixtures.
# ---------------------------------------------------------------------------
if "$SCRIPTS_DIR/fetch-official-packages.sh" "$CACHE_OFFICIAL" >/tmp/fetch.$$.log 2>&1; then
    ok "fetch-official-packages.sh resolved the fixture snapshot"
else
    bad "fetch-official-packages.sh failed: $(cat /tmp/fetch.$$.log)"
fi
rm -f /tmp/fetch.$$.log

if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/build-package.sh" fixture-git --out "$CACHE_CUSTOM/fixture-git" >/tmp/buildgit.$$.log 2>&1; then
    ok "build-package.sh built the fixture git-sourced package"
else
    bad "build-package.sh (fixture-git) failed: $(cat /tmp/buildgit.$$.log)"
fi
rm -f /tmp/buildgit.$$.log

if MANIFEST="$LOCAL_MANIFEST" "$SCRIPTS_DIR/build-package.sh" fixture-local --out "$CACHE_CUSTOM/fixture-local" >/tmp/buildlocal.$$.log 2>&1; then
    ok "build-package.sh built the fixture local-source package from a clean tree"
else
    bad "build-package.sh (fixture-local, clean tree) failed: $(cat /tmp/buildlocal.$$.log)"
fi
rm -f /tmp/buildlocal.$$.log

if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/make-repo.sh" "$REPO_DIR" >/tmp/makerepo.$$.log 2>&1; then
    ok "make-repo.sh assembled the fixture repository"
else
    bad "make-repo.sh failed: $(cat /tmp/makerepo.$$.log)"
fi
rm -f /tmp/makerepo.$$.log

if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$REPO_DIR" >/tmp/verify.$$.log 2>&1; then
    ok "verify-repo.sh PASSES a complete, clean fixture repository"
else
    bad "verify-repo.sh rejected a complete repository: $(cat /tmp/verify.$$.log)"
fi
rm -f /tmp/verify.$$.log

# ---------------------------------------------------------------------------
# 5. Negative cases -- each one targets exactly one review finding.
# ---------------------------------------------------------------------------

# 5a. Completeness: delete an official package from an otherwise-good repo
#     and confirm verify-repo.sh refuses it.
MISSING_OFFICIAL_DIR="$ROOT/repo-missing-official"
cp -a "$REPO_DIR" "$MISSING_OFFICIAL_DIR"
rm -f "$MISSING_OFFICIAL_DIR"/fixture-core-pkg-*.pkg.tar.zst
if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$MISSING_OFFICIAL_DIR" >/dev/null 2>&1; then
    bad "verify-repo.sh passed a repo missing an official package"
else
    ok "verify-repo.sh rejects a repo missing an official package"
fi

# 5b. Completeness: delete a custom package and confirm rejection too (the
#     class of bug that let Umbriel/portal/nbshell go unverified).
MISSING_CUSTOM_DIR="$ROOT/repo-missing-custom"
cp -a "$REPO_DIR" "$MISSING_CUSTOM_DIR"
rm -f "$MISSING_CUSTOM_DIR"/fixture-local-*.pkg.tar.zst
if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$MISSING_CUSTOM_DIR" >/dev/null 2>&1; then
    bad "verify-repo.sh passed a repo missing a custom package"
else
    ok "verify-repo.sh rejects a repo missing a custom package"
fi

# 5c. Staleness: an unmanifested extra package file sitting in the
#     directory must also fail verification, not just get silently ignored.
EXTRA_DIR="$ROOT/repo-extra-file"
cp -a "$REPO_DIR" "$EXTRA_DIR"
cp "$ROOT/build-fixture-core-pkg/fixture-core-pkg-"*.pkg.tar.zst "$EXTRA_DIR/stale-leftover-1.0-1-x86_64.pkg.tar.zst"
if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$EXTRA_DIR" >/dev/null 2>&1; then
    bad "verify-repo.sh passed a repo with an unmanifested extra package file"
else
    ok "verify-repo.sh rejects a repo with an unmanifested extra package file"
fi

# 5d. make-repo.sh itself must not carry stale files forward: pre-populate
#     the target dir with a leftover file from an old build and confirm the
#     freshly rebuilt repo does not contain it.
rm -f "$REPO_DIR"/stale-from-old-build.pkg.tar.zst
touch "$REPO_DIR/stale-from-old-build.pkg.tar.zst"
MANIFEST="$MANIFEST" "$SCRIPTS_DIR/make-repo.sh" "$REPO_DIR" >/dev/null 2>&1
if [ -f "$REPO_DIR/stale-from-old-build.pkg.tar.zst" ]; then
    bad "make-repo.sh left a stale file from a previous run in the rebuilt repository"
else
    ok "make-repo.sh wipes stale leftovers from a previous run before rebuilding"
fi

# 5e. Dirty tree: build-package.sh must refuse to build the local package
#     when the source tree has uncommitted changes.
echo "uncommitted change" >> "$LOCAL_SRC/payload.txt"
if MANIFEST="$LOCAL_MANIFEST" "$SCRIPTS_DIR/build-package.sh" fixture-local --out "$ROOT/should-not-exist" >/dev/null 2>&1; then
    bad "build-package.sh built the local package from a dirty working tree"
else
    ok "build-package.sh refuses to build the local package from a dirty working tree"
fi
git -C "$LOCAL_SRC" checkout -q -- payload.txt

# 5f. Dirty tree, forced: --allow-dirty must succeed but the resulting
#     provenance must say dirty=true, and verify-repo.sh must then refuse
#     to certify that repository as complete/clean.
echo "uncommitted change" >> "$LOCAL_SRC/payload.txt"
DIRTY_OUT="$ROOT/cache/custom-dirty/fixture-local"
if MANIFEST="$LOCAL_MANIFEST" "$SCRIPTS_DIR/build-package.sh" fixture-local --allow-dirty --out "$DIRTY_OUT" >/tmp/dirty.$$.log 2>&1; then
    dirty_flag="$(jq -r '.dirty' "$DIRTY_OUT/fixture-local.provenance.json" 2>/dev/null)"
    if [ "$dirty_flag" = "true" ]; then
        ok "build-package.sh --allow-dirty records dirty=true in provenance"
    else
        bad "build-package.sh --allow-dirty did not record dirty=true (got: $dirty_flag)"
    fi
else
    bad "build-package.sh --allow-dirty failed: $(cat /tmp/dirty.$$.log)"
fi
rm -f /tmp/dirty.$$.log
git -C "$LOCAL_SRC" checkout -q -- payload.txt

DIRTY_REPO_DIR="$ROOT/repo-dirty"
cp -a "$REPO_DIR" "$DIRTY_REPO_DIR"
cp "$DIRTY_OUT"/fixture-local-*.pkg.tar.zst "$DIRTY_REPO_DIR/" 2>/dev/null
jq --slurpfile p "$DIRTY_OUT/fixture-local.provenance.json" \
    '.custom["fixture-local"] = $p[0]' "$DIRTY_REPO_DIR/PROVENANCE.json" > "$DIRTY_REPO_DIR/PROVENANCE.json.tmp" \
    && mv "$DIRTY_REPO_DIR/PROVENANCE.json.tmp" "$DIRTY_REPO_DIR/PROVENANCE.json"
if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$DIRTY_REPO_DIR" >/dev/null 2>&1; then
    bad "verify-repo.sh passed a repository whose local package provenance is dirty=true"
else
    ok "verify-repo.sh rejects a repository whose local package provenance is dirty=true"
fi

# 5g. Tamper detection: mutate a package file in place after the repo was
#     built (bit rot / tampering) and confirm the sha256 cross-check catches
#     it, independent of the loose SHA256SUMS file.
TAMPER_DIR="$ROOT/repo-tampered"
cp -a "$REPO_DIR" "$TAMPER_DIR"
printf 'x' >> "$TAMPER_DIR"/fixture-core-pkg-*.pkg.tar.zst
if MANIFEST="$MANIFEST" "$SCRIPTS_DIR/verify-repo.sh" "$TAMPER_DIR" >/dev/null 2>&1; then
    bad "verify-repo.sh passed a repository with a tampered package file"
else
    ok "verify-repo.sh rejects a repository with a tampered package file"
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
