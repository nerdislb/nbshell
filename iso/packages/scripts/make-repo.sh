#!/usr/bin/env bash
# Assemble the local pacman repository nbshell's offline installer points
# at: every [official] package from cache/official/ (fetch-official-
# packages.sh) plus every [[custom]] package from cache/custom/<name>/
# (build-package.sh), indexed with repo-add, checksummed, and recorded in
# PROVENANCE.json.
#
# The repo directory is wiped and rebuilt from scratch every run -- nothing
# survives from a previous run -- so the resulting repository always
# contains exactly the manifest's package set, never a stale superset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${MANIFEST:-$PACKAGES_DIR/MANIFEST.toml}"
REPO_NAME="nbshell"

CACHE_OFFICIAL="${CACHE_OFFICIAL:-$PACKAGES_DIR/cache/official}"
CACHE_CUSTOM="${CACHE_CUSTOM:-$PACKAGES_DIR/cache/custom}"
REPO_DIR="${1:-$PACKAGES_DIR/repo/$REPO_NAME/os/x86_64}"

die() { printf 'make-repo.sh: %s\n' "$*" >&2; exit 1; }

command -v repo-add >/dev/null || die "repo-add is required"
command -v jq >/dev/null || die "jq is required"
command -v python3 >/dev/null || die "python3 is required"
command -v sha256sum >/dev/null || die "sha256sum is required"

MANIFEST_JSON="$(python3 "$SCRIPT_DIR/lib/manifest.py" load "$MANIFEST")"
mapfile -t CUSTOM_NAMES < <(jq -r '.custom[].name' <<<"$MANIFEST_JSON")

RESOLVED_JSON="$CACHE_OFFICIAL/RESOLVED.json"
[ -f "$RESOLVED_JSON" ] || die "$RESOLVED_JSON missing; run fetch-official-packages.sh first"
mapfile -t RESOLVED_NAMES < <(jq -r 'keys[]' "$RESOLVED_JSON")

rm -rf -- "$REPO_DIR"
mkdir -p "$REPO_DIR"
PROV_WORK="$(mktemp -d)"
trap 'rm -rf -- "$PROV_WORK"' EXIT

copied=0

for name in "${RESOLVED_NAMES[@]}"; do
    filename="$(jq -r --arg n "$name" '.[$n].filename' "$RESOLVED_JSON")"
    [ -n "$filename" ] && [ "$filename" != "null" ] || die "no resolved filename for official package '$name' in $RESOLVED_JSON"
    src="$CACHE_OFFICIAL/$filename"
    [ -f "$src" ] || die "resolved file for '$name' missing on disk: $src"
    cp -- "$src" "$REPO_DIR/"
    [ ! -f "$src.sig" ] || cp -- "$src.sig" "$REPO_DIR/"
    copied=$((copied + 1))
done

for name in "${CUSTOM_NAMES[@]}"; do
    src_dir="$CACHE_CUSTOM/$name"
    [ -d "$src_dir" ] || die "no build output directory for custom package '$name': $src_dir (run build-package.sh $name --out $src_dir)"

    mapfile -t pkg_files < <(find "$src_dir" -maxdepth 1 -type f -name '*.pkg.tar.zst' ! -name '*-debug-*')
    [ ${#pkg_files[@]} -eq 1 ] || die "expected exactly one built package for '$name' in $src_dir, found ${#pkg_files[@]}"
    cp -- "${pkg_files[0]}" "$REPO_DIR/"
    copied=$((copied + 1))

    prov="$src_dir/$name.provenance.json"
    [ -f "$prov" ] || die "missing provenance sidecar for custom package '$name': $prov"
    cp -- "$prov" "$PROV_WORK/$name.json"
done

expected=$(( ${#RESOLVED_NAMES[@]} + ${#CUSTOM_NAMES[@]} ))
[ "$copied" -eq "$expected" ] || die "copied $copied package files but manifest expects $expected"

( cd "$REPO_DIR" && repo-add --quiet "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst )

( cd "$REPO_DIR" && sha256sum -- *.pkg.tar.zst "$REPO_NAME".db* "$REPO_NAME".files* > SHA256SUMS )

GENERATOR_COMMIT="$(git -C "$PACKAGES_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
    --slurpfile official "$RESOLVED_JSON" \
    --arg snapshot_date "$(jq -r '.snapshot.date' <<<"$MANIFEST_JSON")" \
    --arg archive_base "$(jq -r '.snapshot.archive_base' <<<"$MANIFEST_JSON")" \
    --arg generator_commit "$GENERATOR_COMMIT" \
    --arg generated_at "$GENERATED_AT" \
    --argjson custom "$(jq -s 'map({(.name): .}) | add // {}' "$PROV_WORK"/*.json 2>/dev/null || echo '{}')" \
    '{
        snapshot: {date: $snapshot_date, archive_base: $archive_base},
        generator_commit: $generator_commit,
        generated_at: $generated_at,
        official: $official[0],
        custom: $custom
    }' > "$REPO_DIR/PROVENANCE.json"

printf 'make-repo.sh: %s packages indexed into %s\n' "$copied" "$REPO_DIR"
