#!/usr/bin/env bash
# Build the private nbshell x86_64 UEFI installation ISO.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_ROOT="$ROOT/iso"
PACKAGES="$ISO_ROOT/packages"
PROFILE_SOURCE="$ISO_ROOT/profile"
WORK_ROOT="${NBSHELL_ISO_WORK:-$ISO_ROOT/work}"
OUT_ROOT="${NBSHELL_ISO_OUT:-$ISO_ROOT/out}"
PREPARED="$WORK_ROOT/profile"
ARCHISO_WORK="$WORK_ROOT/archiso"
REPO_SOURCE="$PACKAGES/repo/nbshell/os/x86_64"
INTERNAL=0
SKIP_PACKAGES=0

usage() {
    printf '%s\n' \
        'usage: iso/build.sh [--internal-dirty] [--skip-packages]' \
        '' \
        '  --internal-dirty  package the staged/working nbshell tree and mark the ISO private' \
        '  --skip-packages   reuse an already verified offline repository'
}

while (($#)); do
    case "$1" in
        --internal-dirty) INTERNAL=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

for command in mkarchiso makepkg repo-add bsdtar jq python3 sha256sum fakeroot pacman; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Missing build command: %s\n' "$command" >&2
        exit 1
    }
done

if [[ $INTERNAL == 0 && -n $(git -C "$ROOT" status --porcelain --ignore-submodules=all) ]]; then
    printf '%s\n' 'Publication-style ISO builds require a clean committed tree.' >&2
    printf '%s\n' 'Use --internal-dirty only for the private QEMU/hardware preview.' >&2
    exit 1
fi

"$PROFILE_SOURCE/tests/run.sh"
"$PACKAGES/tests/test-manifest-consistency.sh"

if [[ $SKIP_PACKAGES == 0 ]]; then
    if [[ ! -f $PACKAGES/cache/official/RESOLVED.json ]]; then
        "$PACKAGES/scripts/fetch-official-packages.sh"
    fi
    for package in umbriel xdg-desktop-portal-umbriel nbshell; do
        output="$PACKAGES/cache/custom/$package"
        # The local nbshell payload follows this exact working tree/commit and
        # must never be reused from an older build cache. Pinned upstream
        # packages may be reused because their manifest revisions are stable.
        if [[ $package == nbshell ]] || ! compgen -G "$output/*.pkg.tar.zst" >/dev/null; then
            rm -rf -- "$output"
            args=("$package" --out "$output")
            [[ $package != nbshell || $INTERNAL == 0 ]] || args+=(--allow-dirty)
            "$PACKAGES/scripts/build-package.sh" "${args[@]}"
        fi
    done
    "$PACKAGES/scripts/make-repo.sh"
fi

verify_env=()
[[ $INTERNAL == 0 ]] || verify_env+=(NBSHELL_ISO_ALLOW_DIRTY=1)
env "${verify_env[@]}" "$PACKAGES/scripts/verify-repo.sh" "$REPO_SOURCE"

rm -rf -- "$PREPARED"
if [[ -e $ARCHISO_WORK ]]; then
    if rm -rf -- "$ARCHISO_WORK" 2>/dev/null; then
        :
    else
        printf '%s\n' 'Cleaning root-owned Archiso work directory with sudo.'
        sudo rm -rf -- "$ARCHISO_WORK"
    fi
fi
mkdir -p "$WORK_ROOT" "$OUT_ROOT"
cp -a /usr/share/archiso/configs/releng "$PREPARED"
cp -a "$PROFILE_SOURCE"/. "$PREPARED"/
find "$PREPARED" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$PREPARED" -type f -name '*.pyc' -delete

install -Dm644 "$ISO_ROOT/assets/nbshell-logo.svg" \
    "$PREPARED/airootfs/usr/share/nbshell/branding/nbshell-logo.svg"
install -Dm644 "$ISO_ROOT/assets/nbshell-logo.png" \
    "$PREPARED/airootfs/usr/share/nbshell/branding/nbshell-logo.png"
install -d -m755 "$PREPARED/airootfs/var/cache/nbshell/repo"
cp -a "$REPO_SOURCE"/. "$PREPARED/airootfs/var/cache/nbshell/repo/"
install -d -m755 "$PREPARED/airootfs/etc/nbshell"
printf '%s\n' "$([[ $INTERNAL == 1 ]] && echo internal-dirty || echo release-candidate)" \
    > "$PREPARED/airootfs/etc/nbshell/iso-channel"

BUILD_PACMAN_CONF="$WORK_ROOT/pacman-build.conf"
python3 - "$PREPARED/pacman.conf" "$BUILD_PACMAN_CONF" "$PREPARED/airootfs/var/cache/nbshell/repo" <<'PY'
from pathlib import Path
import sys
source, target, repo = map(Path, sys.argv[1:])
text = source.read_text(encoding="utf-8")
text = text.replace("Server = file:///var/cache/nbshell/repo", f"Server = file://{repo.resolve()}")
target.write_text(text, encoding="utf-8")
PY

rm -f -- "$OUT_ROOT"/nbshell-*.iso "$OUT_ROOT"/nbshell-*.iso.sha256
if [[ $(id -u) == 0 ]]; then
    mkarchiso -v -w "$ARCHISO_WORK" -o "$OUT_ROOT" -C "$BUILD_PACMAN_CONF" "$PREPARED"
else
    printf '%s\n' 'mkarchiso requires root; invoking sudo for the isolated image build.'
    sudo mkarchiso -v -w "$ARCHISO_WORK" -o "$OUT_ROOT" -C "$BUILD_PACMAN_CONF" "$PREPARED"
fi

ISO="$(find "$OUT_ROOT" -maxdepth 1 -type f -name 'nbshell-*.iso' -print -quit)"
[[ -n $ISO ]] || { printf '%s\n' 'mkarchiso produced no nbshell ISO' >&2; exit 1; }
(
    cd "$OUT_ROOT"
    sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256"
    sha256sum -c "$(basename "$ISO").sha256"
)
printf 'nbshell ISO: %s\nchecksum: %s\n' "$ISO" "$ISO.sha256"
