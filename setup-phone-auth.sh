#!/usr/bin/env bash
# Install the optional nbOS biometric approval broker. PAM remains untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE=nbshell-phone-auth.service

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }

[ "$(id -u)" != 0 ] || die "Run this installer as your normal user, not root."
command -v openssl >/dev/null || die "OpenSSL is required."

if ! getent group nbshell-auth >/dev/null; then
    sudo groupadd --system nbshell-auth
fi
if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq nbshell-auth; then
    sudo usermod -aG nbshell-auth "$USER"
fi

sudo install -d -o root -g root -m 755 /usr/lib/nbshell
sudo install -o root -g root -m 755 "$ROOT/auth/nbshell_phone_auth.py" /usr/lib/nbshell/nbshell_phone_auth.py
sudo install -o root -g root -m 755 "$ROOT/auth/nbshell_pam_auth.sh" /usr/lib/nbshell/nbshell_pam_auth.sh
sudo install -o root -g root -m 755 "$ROOT/auth/enable-phone-pam.sh" /usr/lib/nbshell/enable-phone-pam.sh
sudo install -o root -g root -m 644 "$ROOT/auth/$SERVICE" "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
# Python services keep the imported source in memory. An already active unit
# must be restarted after every code update; enable --now alone is a no-op.
sudo systemctl restart "$SERVICE"

sudo systemctl is-active --quiet "$SERVICE"
sudo test -S /run/nbshell-auth/control.sock
ok "nbshell phone authentication broker is running."
printf '%s\n' \
    "PAM has not been changed." \
    "Log out and back in once if nbshell-auth was newly added to your groups." \
    "Create and display a pairing QR code with:" \
    "  /usr/lib/nbshell/nbshell_phone_auth.py pair" \
    "Approve the next sudo or Polkit action with:" \
    "  /usr/lib/nbshell/nbshell_phone_auth.py authorize-next" \
    "Optional PAM activation (test one service at a time):" \
    "  sudo /usr/lib/nbshell/enable-phone-pam.sh enable sudo"
