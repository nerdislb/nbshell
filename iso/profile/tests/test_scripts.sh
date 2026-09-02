#!/usr/bin/env bash
set -euo pipefail

profile="$(cd "$(dirname "$0")/.." && pwd)"
target_setup="$profile/airootfs/usr/local/lib/nbshell/target-setup.sh"
firstboot="$profile/airootfs/usr/local/lib/nbshell/firstboot.sh"
installer_service="$profile/airootfs/etc/systemd/system/nbshell-installer.service"
installer_wants="$profile/airootfs/etc/systemd/system/multi-user.target.wants/nbshell-installer.service"
archiso_mkinitcpio="$profile/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
work="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-profile-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

# The installer must be enabled through a real systemd symlink without an
# ordering cycle against the target that pulls it in. The initramfs keeps all
# optical/PXE Archiso hooks but omits the unavailable memdisk helper.
test -L "$installer_wants"
test "$(readlink "$installer_wants")" = ../nbshell-installer.service
! grep -q '^After=multi-user.target$' "$installer_service"
grep -q '^Before=getty@tty1.service$' "$installer_service"
grep -q 'archiso_pxe_common.*archiso_pxe_nbd.*archiso_pxe_http.*archiso_pxe_nfs' "$archiso_mkinitcpio"
! grep -Eq '(^|[=([:space:]])memdisk([)[:space:]]|$)' "$archiso_mkinitcpio"

mkdir -p "$work/target/etc" "$work/bin"
cat >"$work/target/etc/pacman.conf" <<'EOF'
[options]
SigLevel = Required
[nbshell]
SigLevel = Optional TrustAll
Server = file:///var/cache/nbshell/repo
[core]
Include = /etc/pacman.d/mirrorlist
EOF
cat >"$work/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NBSHELL_SYSTEMCTL_LOG"
EOF
chmod +x "$work/bin/systemctl"
export NBSHELL_SYSTEMCTL="$work/bin/systemctl"
export NBSHELL_SYSTEMCTL_LOG="$work/systemctl.log"
NBSHELL_TARGET_ROOT="$work/target" "$target_setup"
if grep -q '^\[nbshell\]$\|file:///run/archiso\|file:///var/cache/nbshell/repo' "$work/target/etc/pacman.conf"; then
    echo "target setup left the live repository configured" >&2
    exit 1
fi
grep -q -- '--root=.* enable NetworkManager.service' "$work/systemctl.log"
grep -q -- '--root=.* enable nbshell-firstboot.service' "$work/systemctl.log"
test "$(stat -c %a "$work/target/var/lib/nbshell")" = 700

# A malformed/live repository reference must fail loudly.
printf '[options]\nServer = file:///run/archiso/bad\n' >"$work/target/etc/pacman.conf"
if NBSHELL_TARGET_ROOT="$work/target" "$target_setup" 2>/dev/null; then
    echo "target setup accepted a live repository" >&2
    exit 1
fi

# Missing desktop binary disables greetd and enters the unit's recovery path.
: >"$work/systemctl.log"
if PATH="$work/bin:/usr/bin:/bin" "$firstboot" 2>/dev/null; then
    echo "firstboot accepted missing desktop binaries" >&2
    exit 1
fi
grep -q '^disable greetd.service$' "$work/systemctl.log"
