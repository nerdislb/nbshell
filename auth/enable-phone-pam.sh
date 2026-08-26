#!/usr/bin/env bash
# Enable or disable instant consumption of pre-approved phone grants.
set -euo pipefail

action="${1:-}"
service="${2:-}"
line='auth            sufficient      pam_exec.so quiet seteuid /usr/lib/nbshell/nbshell_pam_auth.sh'
legacy_line='auth            sufficient      pam_exec.so quiet /usr/lib/nbshell/nbshell_pam_auth.sh'

usage() {
    echo "Usage: $0 enable|disable sudo|polkit-1" >&2
    exit 2
}

[[ $(id -u) -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ $action == enable || $action == disable ]] || usage
[[ $service == sudo || $service == polkit-1 ]] || usage

target="/etc/pam.d/$service"
backup="$target.nbshell-before-phone-grant"
[[ -f $target ]] || { echo "Missing PAM service: $target" >&2; exit 1; }

if [[ $action == disable ]]; then
    [[ -f $backup ]] || { echo "Missing recovery backup: $backup" >&2; exit 1; }
    install -o root -g root -m 0644 "$backup" "$target"
    echo "Disabled phone grants for $service."
    exit 0
fi

[[ -x /usr/lib/nbshell/nbshell_pam_auth.sh ]] || {
    echo "Missing installed nbshell PAM helper." >&2
    exit 1
}

if grep -Fqx "$line" "$target"; then
    echo "Phone grants are already enabled for $service."
    exit 0
fi

[[ -f $backup ]] || install -o root -g root -m 0644 "$target" "$backup"
temporary="$(mktemp "/etc/pam.d/.${service}.nbshell.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
if grep -Fqx "$legacy_line" "$target"; then
    sed "s|^${legacy_line}$|${line}|" "$target" > "$temporary"
    install -o root -g root -m 0644 "$temporary" "$target"
    echo "Updated phone grants for $service to privileged grant consumption."
    echo "Recovery: $0 disable $service"
    exit 0
fi
awk -v insertion="$line" '
    !inserted && $1 == "auth" { print insertion; inserted=1 }
    { print }
    END { if (!inserted) exit 1 }
' "$target" > "$temporary"
install -o root -g root -m 0644 "$temporary" "$target"
echo "Enabled one-time phone grants for $service."
echo "Recovery: $0 disable $service"
