#!/usr/bin/env bash
# Download every [official] package in MANIFEST.toml from a pinned Arch
# Linux Archive snapshot into a cache directory this script fully owns.
#
# Reproducibility: packages come from archive.archlinux.org at the date
# fixed in MANIFEST.toml's [snapshot] table (or a file:// fixture in tests),
# never from the live, moving mirror set -- so re-running this on two
# different days resolves to the exact same files.
#
# Cleanliness: the output directory is wiped at the start of every run. No
# package file from a previous run, a previous snapshot date, or an earlier
# manifest revision can survive into the new cache, so make-repo.sh can
# never pick up a stale duplicate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${MANIFEST:-$PACKAGES_DIR/MANIFEST.toml}"
OUT_DIR="${1:-$PACKAGES_DIR/cache/official}"

die() { printf 'fetch-official-packages.sh: %s\n' "$*" >&2; exit 1; }

command -v bsdtar >/dev/null || die "bsdtar is required"
command -v fakeroot >/dev/null || die "fakeroot is required"
command -v jq >/dev/null || die "jq is required"
command -v pacman >/dev/null || die "pacman is required"
command -v python3 >/dev/null || die "python3 is required"

MANIFEST_JSON="$(python3 "$SCRIPT_DIR/lib/manifest.py" load "$MANIFEST")"

ARCHIVE_BASE="$(jq -r '.snapshot.archive_base' <<<"$MANIFEST_JSON")"
SNAPSHOT_DATE="$(jq -r '.snapshot.date' <<<"$MANIFEST_JSON")"
ARCH="$(jq -r '.snapshot.arch' <<<"$MANIFEST_JSON")"
mapfile -t REPOS < <(jq -r '.snapshot.repos[]' <<<"$MANIFEST_JSON")
mapfile -t WANTED < <(jq -r '.official.packages[]' <<<"$MANIFEST_JSON")

rm -rf -- "$OUT_DIR"
mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

# Resolve the complete dependency closure in an isolated pacman database.
# fakeroot satisfies pacman's root check while every path remains user-owned.
PACMAN_CONF="$WORK/pacman.conf"
SIGLEVEL='Required DatabaseOptional'
[[ "$ARCHIVE_BASE" != file://* ]] || SIGLEVEL='Never'
{
    printf '%s\n' '[options]' "Architecture = $ARCH" \
        "SigLevel = $SIGLEVEL" \
        "DBPath = $WORK/db" "CacheDir = $OUT_DIR" \
        'GPGDir = /etc/pacman.d/gnupg' 'LogFile = /dev/null'
    for repo in "${REPOS[@]}"; do
        printf '\n[%s]\nServer = %s/%s/%s/os/%s\n' \
            "$repo" "$ARCHIVE_BASE" "$SNAPSHOT_DATE" "$repo" "$ARCH"
    done
} > "$PACMAN_CONF"
mkdir -p "$WORK/db" "$WORK/root"
fakeroot pacman --config "$PACMAN_CONF" --root "$WORK/root" -Syw --noconfirm -- "${WANTED[@]}" \
    || die "pacman could not resolve the offline dependency closure"
rm -f -- "$OUT_DIR"/*.part

printf '%s\n' "${WANTED[@]}" > "$WORK/requested.txt"
python3 - "$OUT_DIR" "$WORK/requested.txt" "$SNAPSHOT_DATE" <<'PY'
import hashlib, json, pathlib, subprocess, sys

out = pathlib.Path(sys.argv[1])
requested = {line.strip() for line in pathlib.Path(sys.argv[2]).read_text().splitlines() if line.strip()}
snapshot = sys.argv[3]
resolved = {}
for package in sorted(out.glob("*.pkg.tar.zst")):
    metadata = subprocess.check_output(["bsdtar", "-xOf", str(package), ".PKGINFO"], text=True)
    fields = {}
    for line in metadata.splitlines():
        if " = " in line:
            key, value = line.split(" = ", 1)
            fields.setdefault(key, value)
    name = fields.get("pkgname", "")
    if not name or name in resolved:
        raise SystemExit(f"duplicate or unreadable package metadata: {package.name}")
    resolved[name] = {
        "filename": package.name,
        "version": fields.get("pkgver", ""),
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "snapshot": snapshot,
    }
missing = sorted(requested - resolved.keys())
if missing:
    raise SystemExit("requested packages missing from closure: " + ", ".join(missing))
(out / "RESOLVED.json").write_text(json.dumps(resolved, indent=2, sort_keys=True) + "\n")
print(f"resolved {len(requested)} requested packages to {len(resolved)} signed package files")
PY

printf 'fetch-official-packages.sh: dependency closure from snapshot %s written to %s\n' \
    "$SNAPSHOT_DATE" "$OUT_DIR"
