#!/usr/bin/env bash
# Build one [[custom]] package from MANIFEST.toml, or with --check-only,
# just verify its PKGBUILD is still pinned to the exact revision the
# manifest records (no clone, no build, no network).
#
# Two invariants this script enforces before it will produce a package:
#   * git-sourced entries: the PKGBUILD's _commit must equal
#     MANIFEST.toml's revision for that entry, byte for byte.
#   * source = "local" entries (nbshell): the working tree must be clean
#     (git status --porcelain empty) unless --allow-dirty is passed, and
#     the resolved commit + dirty flag are always written to a provenance
#     sidecar next to the built package for verify-repo.sh to check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${MANIFEST:-$PACKAGES_DIR/MANIFEST.toml}"

die() { printf 'build-package.sh: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: build-package.sh <name> --out DIR [--check-only] [--allow-dirty]
EOF
}

NAME=""
OUT_DIR=""
CHECK_ONLY=0
ALLOW_DIRTY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        --check-only) CHECK_ONLY=1; shift ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) [ -z "$NAME" ] || die "unexpected extra argument: $1"; NAME="$1"; shift ;;
    esac
done
[ -n "$NAME" ] || { usage >&2; exit 2; }
[ $CHECK_ONLY -eq 1 ] || [ -n "$OUT_DIR" ] || die "--out DIR is required unless --check-only"
if [ -n "$OUT_DIR" ]; then
    OUT_DIR="$(realpath -m "$OUT_DIR")"
fi

command -v jq >/dev/null || die "jq is required"
command -v python3 >/dev/null || die "python3 is required"

MANIFEST_JSON="$(python3 "$SCRIPT_DIR/lib/manifest.py" load "$MANIFEST")"
ENTRY="$(jq -c --arg name "$NAME" '.custom[] | select(.name == $name)' <<<"$MANIFEST_JSON")"
[ -n "$ENTRY" ] || die "no [[custom]] entry named '$NAME' in $MANIFEST"

# pkgbuild paths in the manifest are relative to the manifest file itself
# (not to this script's location), so a test can point --manifest at an
# isolated fixture tree without touching the real iso/packages/pkgbuilds.
MANIFEST_DIR="$(cd "$(dirname "$MANIFEST")" && pwd)"

PKGBUILD_REL="$(jq -r '.pkgbuild' <<<"$ENTRY")"
SOURCE="$(jq -r '.source' <<<"$ENTRY")"
REVISION="$(jq -r '.revision' <<<"$ENTRY")"
PKGBUILD_DIR="$MANIFEST_DIR/$PKGBUILD_REL"
PKGBUILD_FILE="$PKGBUILD_DIR/PKGBUILD"
[ -f "$PKGBUILD_FILE" ] || die "$PKGBUILD_FILE does not exist"

pkgbuild_var() {
    # Extract a plain `_name=value` assignment from a PKGBUILD without
    # sourcing it (PKGBUILDs are trusted content, but a targeted grep keeps
    # this script's own environment untouched either way).
    local var="$1"
    sed -n "s/^${var}=\"\\?\\([^\"[:space:]]*\\)\"\\?[[:space:]]*$/\\1/p" "$PKGBUILD_FILE" | head -n1
}

if [ "$SOURCE" = "local" ]; then
    SRC_ROOT="$(git -C "$MANIFEST_DIR" rev-parse --show-toplevel)"
    expected_source="${NAME}-src.tar.gz"
    grep -qF "source=(\"$expected_source\")" "$PKGBUILD_FILE" \
        || die "$PKGBUILD_FILE must declare source=(\"$expected_source\") for a local-source package named '$NAME'"

    if [ $CHECK_ONLY -eq 1 ]; then
        printf 'build-package.sh: %s: local source, PKGBUILD present, nothing to build (--check-only)\n' "$NAME"
        exit 0
    fi

    if [ $ALLOW_DIRTY -eq 0 ]; then
        dirty="$(git -C "$SRC_ROOT" status --porcelain --ignore-submodules=all)"
        [ -z "$dirty" ] || die "$SRC_ROOT has uncommitted changes; a publication build must come from a clean commit. Pass --allow-dirty only for local iteration, never for a published repository."
    fi
    COMMIT="$(git -C "$SRC_ROOT" rev-parse HEAD)"
    DIRTY_FLAG=$([ -n "$(git -C "$SRC_ROOT" status --porcelain --ignore-submodules=all)" ] && echo true || echo false)

    WORK="$(mktemp -d)"
    trap 'rm -rf -- "$WORK"' EXIT
    cp -a "$PKGBUILD_DIR" "$WORK/build"
    if [ "$DIRTY_FLAG" = true ]; then
        # Internal preview only: package the current tracked working files so
        # the ISO can exercise staged changes. Provenance remains dirty=true
        # and publication verification rejects it unless the explicit internal
        # override is set.
        git -C "$SRC_ROOT" ls-files -z \
            | tar -C "$SRC_ROOT" --null --verbatim-files-from -T - -czf "$WORK/build/$expected_source"
    else
        git -C "$SRC_ROOT" archive --format=tar.gz -o "$WORK/build/$expected_source" "$COMMIT"
    fi

    mkdir -p "$OUT_DIR"
    ( cd "$WORK/build" && PKGDEST="$OUT_DIR" makepkg --noconfirm --clean )

    jq -n --arg name "$NAME" --arg commit "$COMMIT" --arg dirty "$DIRTY_FLAG" --arg source local \
        '{name: $name, source: $source, commit: $commit, dirty: ($dirty == "true")}' \
        > "$OUT_DIR/$NAME.provenance.json"
else
    pkgbuild_commit="$(pkgbuild_var _commit)"
    pkgbuild_url="$(pkgbuild_var _url)"
    [ -n "$pkgbuild_commit" ] || die "$PKGBUILD_FILE has no _commit= assignment"
    [ -n "$pkgbuild_url" ] || die "$PKGBUILD_FILE has no _url= assignment"
    [ "$pkgbuild_commit" = "$REVISION" ] || die "$PKGBUILD_FILE _commit=$pkgbuild_commit does not match MANIFEST.toml revision=$REVISION for '$NAME'"
    [ "$pkgbuild_url" = "$SOURCE" ] || die "$PKGBUILD_FILE _url=$pkgbuild_url does not match MANIFEST.toml source=$SOURCE for '$NAME'"

    if [ $CHECK_ONLY -eq 1 ]; then
        printf 'build-package.sh: %s: PKGBUILD pin matches MANIFEST.toml (%s) (--check-only)\n' "$NAME" "$REVISION"
        exit 0
    fi

    mkdir -p "$OUT_DIR"
    ( cd "$PKGBUILD_DIR" && PKGDEST="$OUT_DIR" makepkg --noconfirm --clean )

    jq -n --arg name "$NAME" --arg commit "$REVISION" --arg source "$SOURCE" \
        '{name: $name, source: $source, commit: $commit, dirty: false}' \
        > "$OUT_DIR/$NAME.provenance.json"
fi

printf 'build-package.sh: built %s -> %s\n' "$NAME" "$OUT_DIR"
