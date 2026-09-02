#!/usr/bin/env bash
set -euo pipefail

systemctl_cmd="${NBSHELL_SYSTEMCTL:-systemctl}"
required=(umbriel quickshell nbshell)
for binary in "${required[@]}"; do
    if ! command -v "$binary" >/dev/null 2>&1; then
        echo "nbshell first boot: missing required binary: $binary" >&2
        "$systemctl_cmd" disable greetd.service
        exit 1
    fi
done

install_user_file=/etc/nbshell/install-user
[[ -r "$install_user_file" ]] || { echo "nbshell first boot: install user is missing" >&2; exit 1; }
install_user="$(cat "$install_user_file")"
[[ "$install_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "nbshell first boot: invalid install user" >&2; exit 1; }
install_home="$(getent passwd "$install_user" | cut -d: -f6)"
[[ -d "$install_home" ]] || { echo "nbshell first boot: home is missing for $install_user" >&2; exit 1; }

runuser -u "$install_user" -- env \
    HOME="$install_home" \
    XDG_CONFIG_HOME="$install_home/.config" \
    XDG_DATA_HOME="$install_home/.local/share" \
    XDG_STATE_HOME="$install_home/.local/state" \
    XDG_CACHE_HOME="$install_home/.cache" \
    XDG_BIN_HOME="$install_home/.local/bin" \
    NBSHELL_INSTALL_DEFER_RESTART=1 \
    /usr/share/nbshell/install.sh

[[ -f "$install_home/.config/quickshell/nbshell/shell.qml" ]] \
    || { echo "nbshell first boot: user runtime was not installed" >&2; exit 1; }

install -m 0644 /usr/share/nbshell/shell/lock/nbshell-lock.pam /etc/pam.d/nbshell-lock
cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "agreety --cmd start-umbriel"
user = "greeter"
EOF

install -d -m 0700 /var/lib/nbshell
touch /var/lib/nbshell/firstboot-complete
chmod 0600 /var/lib/nbshell/firstboot-complete
"$systemctl_cmd" disable nbshell-firstboot.service
