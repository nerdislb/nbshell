#!/usr/bin/env bash
# Verify a built repository (from make-repo.sh) is complete, unmodified
# since it was built, and provenance-backed, before it is ever considered
# publication-ready.
#
# Checks performed (all of them, not just the first failure -- every
# problem found is reported in one run):
#   1. Every [official] + [[custom]] name in MANIFEST.toml has EXACTLY one
#      matching package file in the repo directory (nothing missing, and
#      -- since make-repo.sh wipes the directory on every build -- nothing
#      unmanifested either).
#   2. The repo-add database itself lists exactly that same set (a file
#      sitting in the directory without being indexed, or vice versa, is a
#      failure).
#   3. SHA256SUMS covers every package + database file and matches on disk.
#   4. PROVENANCE.json exists, was generated from the same snapshot the
#      manifest pins, and every official package's recorded sha256 matches
#      the file actually sitting in the repo now.
#   5. Every [[custom]] package's provenance is clean: git-sourced entries
#      recorded the pinned commit; the local (nbshell) entry recorded a
#      real 40-character commit hash with dirty = false.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${MANIFEST:-$PACKAGES_DIR/MANIFEST.toml}"
REPO_NAME="nbshell"
REPO_DIR="${1:-$PACKAGES_DIR/repo/$REPO_NAME/os/x86_64}"

ERRORS=()
fail() { ERRORS+=("$*"); }

command -v jq >/dev/null || { echo "verify-repo.sh: jq is required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "verify-repo.sh: python3 is required" >&2; exit 2; }
command -v bsdtar >/dev/null || { echo "verify-repo.sh: bsdtar is required" >&2; exit 2; }

MANIFEST_JSON="$(python3 "$SCRIPT_DIR/lib/manifest.py" load "$MANIFEST")" || exit 2

if [ ! -d "$REPO_DIR" ]; then
    echo "verify-repo.sh: $REPO_DIR does not exist" >&2
    exit 1
fi

mapfile -t REQUESTED_NAMES < <(jq -r '.official.packages[]' <<<"$MANIFEST_JSON")
mapfile -t CUSTOM_NAMES < <(jq -r '.custom[].name' <<<"$MANIFEST_JSON")
PROV_FILE="$REPO_DIR/PROVENANCE.json"
if [ -f "$PROV_FILE" ]; then
    mapfile -t CLOSURE_NAMES < <(jq -r '.official | keys[]' "$PROV_FILE")
else
    CLOSURE_NAMES=()
fi
EXPECTED_NAMES=("${CLOSURE_NAMES[@]}" "${CUSTOM_NAMES[@]}")
declare -A EXPECTED=()
for n in "${EXPECTED_NAMES[@]}"; do EXPECTED["$n"]=1; done
declare -A CLOSURE=()
for n in "${CLOSURE_NAMES[@]}"; do CLOSURE["$n"]=1; done
for n in "${REQUESTED_NAMES[@]}"; do
    [[ -v CLOSURE[$n] ]] || fail "requested manifest package is absent from resolved closure: $n"
done

pkg_name_of() {
    bsdtar -xOf "$1" .PKGINFO 2>/dev/null | awk -F' = ' '/^pkgname/{print $2; exit}'
}

# 1. Exactly-once check against loose package files in the directory.
declare -A FOUND_FILE=()
shopt -s nullglob
for f in "$REPO_DIR"/*.pkg.tar.zst; do
    name="$(pkg_name_of "$f")"
    [ -n "$name" ] || { fail "could not read pkgname from $f"; continue; }
    if [[ -v FOUND_FILE[$name] ]]; then
        fail "duplicate package file for '$name': ${FOUND_FILE[$name]} and $f"
    fi
    FOUND_FILE["$name"]="$f"
done
shopt -u nullglob

for n in "${EXPECTED_NAMES[@]}"; do
    [[ -v FOUND_FILE[$n] ]] || fail "missing from repository: $n"
done
for n in "${!FOUND_FILE[@]}"; do
    [[ -v EXPECTED[$n] ]] || fail "unmanifested package present in repository: $n (${FOUND_FILE[$n]})"
done

# 2. Cross-check the repo-add database lists the same set.
DB_FILE="$REPO_DIR/$REPO_NAME.db.tar.gz"
if [ ! -f "$DB_FILE" ]; then
    fail "$DB_FILE does not exist"
else
    DB_WORK="$(mktemp -d)"
    bsdtar -xf "$DB_FILE" -C "$DB_WORK" 2>/dev/null
    declare -A DB_NAMES=()
    while IFS= read -r -d '' desc; do
        n="$(awk '/^%NAME%$/{getline; print; exit}' "$desc")"
        [ -n "$n" ] && DB_NAMES["$n"]=1
    done < <(find "$DB_WORK" -type f -name desc -print0)
    rm -rf -- "$DB_WORK"

    for n in "${EXPECTED_NAMES[@]}"; do
        [[ -v DB_NAMES[$n] ]] || fail "indexed database is missing entry for: $n"
    done
    for n in "${!DB_NAMES[@]}"; do
        [[ -v EXPECTED[$n] ]] || fail "indexed database has unmanifested entry: $n"
    done
fi

# 3. SHA256SUMS covers every file on disk and matches.
SUMS_FILE="$REPO_DIR/SHA256SUMS"
if [ ! -f "$SUMS_FILE" ]; then
    fail "$SUMS_FILE does not exist"
else
    sha256_log="$(mktemp)"
    (cd "$REPO_DIR" && sha256sum -c --quiet SHA256SUMS) >"$sha256_log" 2>&1 \
        || fail "SHA256SUMS verification failed: $(cat "$sha256_log")"
    rm -f "$sha256_log"
fi

# 4 & 5. PROVENANCE.json: snapshot pin, per-package checksums, custom pins.
if [ ! -f "$PROV_FILE" ]; then
    fail "$PROV_FILE does not exist"
else
    manifest_date="$(jq -r '.snapshot.date' <<<"$MANIFEST_JSON")"
    manifest_base="$(jq -r '.snapshot.archive_base' <<<"$MANIFEST_JSON")"
    prov_date="$(jq -r '.snapshot.date' "$PROV_FILE")"
    prov_base="$(jq -r '.snapshot.archive_base' "$PROV_FILE")"
    [ "$manifest_date" = "$prov_date" ] || fail "PROVENANCE.json snapshot.date ($prov_date) does not match MANIFEST.toml ($manifest_date)"
    [ "$manifest_base" = "$prov_base" ] || fail "PROVENANCE.json snapshot.archive_base ($prov_base) does not match MANIFEST.toml ($manifest_base)"

    while IFS= read -r name; do
        recorded_sha="$(jq -r --arg n "$name" '.official[$n].sha256 // empty' "$PROV_FILE")"
        filename="$(jq -r --arg n "$name" '.official[$n].filename // empty' "$PROV_FILE")"
        if [ -z "$filename" ]; then
            fail "PROVENANCE.json has no official entry for: $name"
            continue
        fi
        actual_path="$REPO_DIR/$filename"
        if [ ! -f "$actual_path" ]; then
            fail "PROVENANCE.json references $filename for '$name' but it is not in the repository"
        elif [ -n "$recorded_sha" ]; then
            actual_sha="$(sha256sum "$actual_path" | cut -d' ' -f1)"
            [ "$actual_sha" = "$recorded_sha" ] || fail "checksum drift for '$name': PROVENANCE.json says $recorded_sha, file is now $actual_sha"
        fi
    done < <(jq -r '.official | keys[]' "$PROV_FILE")

    while IFS= read -r entry; do
        name="$(jq -r '.name' <<<"$entry")"
        source="$(jq -r '.source' <<<"$entry")"
        revision="$(jq -r '.revision' <<<"$entry")"
        prov_commit="$(jq -r --arg n "$name" '.custom[$n].commit // empty' "$PROV_FILE")"
        prov_dirty="$(jq -r --arg n "$name" '.custom[$n].dirty' "$PROV_FILE")"

        if [ -z "$prov_commit" ]; then
            fail "PROVENANCE.json has no custom entry for: $name"
            continue
        fi
        if ! [[ "$prov_commit" =~ ^[0-9a-f]{40}$ ]]; then
            fail "'$name' provenance commit is not a 40-character git hash: $prov_commit"
        fi
        if [ "$source" = "local" ]; then
            if [ "$prov_dirty" != "false" ] && [ "${NBSHELL_ISO_ALLOW_DIRTY:-0}" != 1 ]; then
                fail "'$name' was built from a dirty working tree (dirty=$prov_dirty); publication builds must be clean"
            fi
        else
            [ "$prov_commit" = "$revision" ] || fail "'$name' provenance commit ($prov_commit) does not match MANIFEST.toml revision ($revision)"
            [ "$prov_dirty" = "false" ] || fail "'$name' provenance marked dirty=$prov_dirty for a pinned git source, which should never happen"
        fi
    done < <(jq -c '.custom[]' <<<"$MANIFEST_JSON")
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    printf 'verify-repo.sh: FAIL (%d issue(s)) for %s\n' "${#ERRORS[@]}" "$REPO_DIR" >&2
    for e in "${ERRORS[@]}"; do printf '  - %s\n' "$e" >&2; done
    exit 1
fi

printf 'verify-repo.sh: PASS -- %d packages verified complete against %s\n' "${#EXPECTED_NAMES[@]}" "$MANIFEST"
