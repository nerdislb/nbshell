#!/usr/bin/env bash
# Install the dedicated PAM service used by the native in-session locker.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${NBSHELL_LOCK_PAM_SOURCE:-$ROOT/shell/lock/nbshell-lock.pam}"
TEST_ROOT="${NBSHELL_LOCK_TEST_ROOT:-}"
HELPER="${NBSHELL_LOCK_ROOT_HELPER:-sudo}"
[[ $HELPER == sudo || $HELPER == pkexec ]] || { echo "NBSHELL_LOCK_ROOT_HELPER must be sudo or pkexec" >&2; exit 2; }
[[ -f $SOURCE ]] || { echo "Missing PAM payload: $SOURCE" >&2; exit 1; }
if [[ -n $TEST_ROOT ]]; then
    [[ $TEST_ROOT == /* ]] || { echo "NBSHELL_LOCK_TEST_ROOT must be absolute" >&2; exit 2; }
    install -Dm644 "$SOURCE" "$TEST_ROOT/etc/pam.d/nbshell-lock"
elif [[ $HELPER == pkexec ]]; then
    pkexec install -Dm644 "$SOURCE" /etc/pam.d/nbshell-lock
else
    sudo install -Dm644 "$SOURCE" /etc/pam.d/nbshell-lock
fi
echo "Native locker PAM service installed: nbshell-lock"
