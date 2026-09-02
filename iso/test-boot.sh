#!/usr/bin/env bash
# Boot-smoke a built nbshell ISO in QEMU without permitting persistent disk writes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-}"
[[ -n "$ISO" && -f "$ISO" ]] || {
    printf 'usage: iso/test-boot.sh path/to/nbshell.iso\n' >&2
    exit 2
}
ISO="$(realpath "$ISO")"
for command in qemu-system-x86_64 qemu-img sha256sum; do
    command -v "$command" >/dev/null 2>&1 || { echo "Missing: $command" >&2; exit 1; }
done

OVMF_CODE="${NBSHELL_OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}"
OVMF_VARS="${NBSHELL_OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}"
[[ -r "$OVMF_CODE" && -r "$OVMF_VARS" ]] || { echo "OVMF firmware is missing" >&2; exit 1; }

RUNS="$ROOT/iso/test-runs"
mkdir -p "$RUNS"
RUN="$(mktemp -d "$RUNS/boot.XXXXXX")"
DISK="$RUN/target.qcow2"
VARS="$RUN/OVMF_VARS.fd"
SERIAL="$RUN/serial.log"
PID=""
cleanup() {
    [[ -z "$PID" ]] || kill "$PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

case "$(realpath "$RUN")" in "$RUNS"/*) ;; *) echo "Unsafe test directory" >&2; exit 1 ;; esac
qemu-img create -q -f qcow2 "$DISK" 32G
cp -- "$OVMF_VARS" "$VARS"
BEFORE="$(sha256sum "$DISK" | cut -d' ' -f1)"

accel=tcg
[[ -r /dev/kvm && -w /dev/kvm ]] && accel=kvm
cmd=(
    qemu-system-x86_64
    -machine "q35,accel=$accel"
    -cpu max -smp 2 -m 4096
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$VARS"
    -drive "file=$DISK,if=virtio,format=qcow2,snapshot=on"
    -drive "file=$ISO,media=cdrom,readonly=on"
    -boot d -nic none -display none -monitor none
    -serial "file:$SERIAL" -no-reboot
)

# Guard against accidental host block-device attachment in future edits.
printf '%s\n' "${cmd[@]}" | grep -Eq '(^|[=,])/dev/' && {
    echo "Refusing QEMU command containing a host /dev path" >&2
    exit 1
}

"${cmd[@]}" >"$RUN/qemu.log" 2>&1 &
PID=$!
found=0
for _ in $(seq 1 360); do
    if grep -Fq 'NBSHELL_ISO: dry-run-complete' "$SERIAL" 2>/dev/null; then
        found=1
        break
    fi
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.5
done
kill "$PID" >/dev/null 2>&1 || true
wait "$PID" 2>/dev/null || true
PID=""

[[ $found == 1 ]] || {
    echo "nbshell ISO did not reach the installer dry-run marker" >&2
    echo "Artifacts: $RUN" >&2
    exit 1
}
AFTER="$(sha256sum "$DISK" | cut -d' ' -f1)"
[[ "$BEFORE" == "$AFTER" ]] || {
    echo "Boot smoke modified the disposable base disk despite QEMU snapshot mode" >&2
    exit 1
}
printf 'ISO boot smoke passed; base disk remained byte-identical.\nArtifacts: %s\n' "$RUN"
