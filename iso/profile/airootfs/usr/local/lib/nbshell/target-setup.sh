#!/usr/bin/env bash
set -euo pipefail

root="${NBSHELL_TARGET_ROOT:-/}"
systemctl_cmd="${NBSHELL_SYSTEMCTL:-systemctl}"
pacman_conf="${root%/}/etc/pacman.conf"

[[ -f "$pacman_conf" ]] || { echo "missing target pacman.conf" >&2; exit 1; }
# Drop the ISO-only repository section, through the next section header or EOF.
sed -i '/^\[nbshell\]$/,/^\[[^]]\+\]$/{ /^\[nbshell\]$/d; /^\[[^]]\+\]$/!d; }' "$pacman_conf"
if grep -Eq '^\[nbshell\]$|file:///run/archiso/|file:///var/cache/nbshell/repo' "$pacman_conf"; then
    echo "refusing to leave the live ISO repository configured on target" >&2
    exit 1
fi

install -d -m 0700 "${root%/}/var/lib/nbshell"
install -d -m 0755 "${root%/}/etc/nbshell"
"$systemctl_cmd" --root="$root" enable NetworkManager.service
"$systemctl_cmd" --root="$root" enable nbshell-firstboot.service
"$systemctl_cmd" --root="$root" enable greetd.service
