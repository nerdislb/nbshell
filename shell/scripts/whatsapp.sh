#!/usr/bin/env bash
# nbshell WhatsApp bridge installer/launcher.
# The bridge is pinned and checksum-verified; nbshell only talks to its local
# owner-only Unix socket. Credentials never enter the nbshell config tree.

set -euo pipefail

commit="f9cf8d825ccbd6a62171b557ce5d6c55d430b505"
archive_sha="1b5a03ad8f12a2afe5a76fee93938d165083630d4d447953653029c59270a71c"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/whatsapp"
source_dir="$data_dir/source"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nbshell-whatsapp"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nbshell-whatsapp/media"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
socket="$runtime_dir/nbshell-whatsapp.sock"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$unit_dir/nbshell-whatsapp.service"

die() { printf 'nbshell whatsapp: %s\n' "$*" >&2; exit 1; }

node_bin="$(command -v node 2>/dev/null || true)"
[[ -n $node_bin ]] || die "Node.js fehlt (mindestens Version 20)"
node_major="$($node_bin -p 'process.versions.node.split(".")[0]')"
(( node_major >= 20 )) || die "Node.js $node_major ist zu alt (mindestens 20)"

install_bridge() {
    command -v curl >/dev/null || die "curl fehlt"
    command -v tar >/dev/null || die "tar fehlt"
    command -v npm >/dev/null || die "npm fehlt"
    mkdir -p "$data_dir" "$state_dir" "$cache_dir" "$unit_dir"
    chmod 700 "$state_dir" "${cache_dir%/media}" "$cache_dir"

    if [[ ! -f $source_dir/.nbshell-revision ]] || [[ $(<"$source_dir/.nbshell-revision") != "$commit" ]]; then
        local stage archive unpacked
        stage="$(mktemp -d "$data_dir/.install.XXXXXX")"
        archive="$stage/source.tar.gz"
        curl -fL "https://github.com/srineshr1/omarchy-whatsapp/archive/$commit.tar.gz" -o "$archive"
        printf '%s  %s\n' "$archive_sha" "$archive" | sha256sum --check --status \
            || die "WhatsApp bridge archive checksum mismatch"
        tar -xzf "$archive" -C "$stage"
        unpacked="$stage/omarchy-whatsapp-$commit"
        [[ -d $unpacked/daemon ]] || die "Bridge-Archiv ist unvollstaendig"
        if [[ -d $source_dir ]]; then
            mv "$source_dir" "$data_dir/source.previous"
        fi
        mv "$unpacked" "$source_dir"
        printf '%s\n' "$commit" > "$source_dir/.nbshell-revision"
    fi

    # Baileys 6.7.24 pins libsignal to an exact Git commit. npm 12 blocks all
    # Git dependencies by default, therefore opt in for this lockfile-bound
    # install only; the user's global npm policy remains untouched.
    (cd "$source_dir/daemon" && npm ci --allow-git=all --omit=dev --no-audit --no-fund)

    cat > "$unit" <<EOF
[Unit]
Description=WhatsApp bridge for nbshell
Documentation=https://github.com/srineshr1/omarchy-whatsapp
After=graphical-session.target network-online.target
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory=$source_dir/daemon
ExecStart=$node_bin $source_dir/daemon/index.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=OMARCHY_WHATSAPP_STATE=$state_dir
Environment=OMARCHY_WHATSAPP_MEDIA=$cache_dir
Environment=OMARCHY_WHATSAPP_SOCKET=$socket
NoNewPrivileges=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
MemoryHigh=400M

[Install]
WantedBy=graphical-session.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now nbshell-whatsapp.service
    printf 'WhatsApp bridge installed. Open the WA module and choose "Connect device".\n'
}

open_webapp() {
    if command -v gtk-launch >/dev/null 2>&1; then
        gtk-launch webapp-whatsapp >/dev/null 2>&1 &
    elif command -v brave >/dev/null 2>&1; then
        brave --class=webapp-whatsapp --app=https://web.whatsapp.com >/dev/null 2>&1 &
    else
        xdg-open https://web.whatsapp.com >/dev/null 2>&1 &
    fi
}

case "${1:-status}" in
    setup|install) install_bridge ;;
    start) systemctl --user start nbshell-whatsapp.service ;;
    restart) systemctl --user restart nbshell-whatsapp.service ;;
    status) systemctl --user --no-pager --full status nbshell-whatsapp.service ;;
    open) open_webapp ;;
    *) die "Usage: whatsapp.sh setup|start|restart|status|open" ;;
esac
