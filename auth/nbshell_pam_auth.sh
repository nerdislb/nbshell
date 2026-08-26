#!/usr/bin/env bash
# PAM bridge: consume an already approved, short-lived phone grant immediately.
# A miss must return without waiting so native fingerprint/password PAM follows.
set -u

service="${PAM_SERVICE:-unknown}"
# sudo authenticates the invoking user while PAM_USER is commonly the target
# account (root). PAM_RUSER is not populated by every sudo invocation, notably
# non-interactive ones, so fall back to sudo's real process UID.
user="${PAM_RUSER:-}"
if [[ $service == sudo ]]; then
    user=""
    ancestor="$PPID"
    for _ in 1 2 3 4 5 6; do
        [[ -r /proc/$ancestor/status ]] || break
        read -r real_uid < <(awk '/^Uid:/ { print $2; exit }' "/proc/$ancestor/status")
        if [[ $real_uid =~ ^[0-9]+$ && $real_uid -ne 0 ]]; then
            user="$(getent passwd "$real_uid" | cut -d: -f1)"
            break
        fi
        read -r ancestor < <(awk '/^PPid:/ { print $2; exit }' "/proc/$ancestor/status")
        [[ $ancestor =~ ^[0-9]+$ && $ancestor -gt 1 ]] || break
    done
fi
user="${user:-${PAM_USER:-}}"
[[ -n $user ]] || exit 1

exec /usr/lib/nbshell/nbshell_phone_auth.py consume-grant \
    --service "$service" --user "$user" >/dev/null 2>&1
