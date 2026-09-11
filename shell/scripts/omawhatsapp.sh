#!/usr/bin/env bash
set -euo pipefail

command_name=${1:-status}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
runtime_shell="$config_home/quickshell/nbshell"
plugin_dir="$config_home/nbshell/plugins/omawhatsapp"
config_file="$config_home/nbshell/config.json"
provider_file="$config_home/nbshell/whatsapp-provider"
unit_dir="$config_home/systemd/user"
bin_dir=${XDG_BIN_HOME:-$HOME/.local/bin}
source_revision=7ee1540f01d4f7fb698d683577fecd57063a9204
source_sha=fbd39edbc26b7661eb929912da9531ebff4fd6c1f9646857f2b2bd5b32a39b30
wacli_version=0.18.1
wacli_amd64_sha=36e8c48065f224f58428db9802767e8c6d9e10c0e847bbb5d9072fac72c272cd
wacli_arm64_sha=e41465ac95baea79586d43ea102adb501abd0aa84f371138a9a1bda625bfc01d

provider() {
    [ -f "$provider_file" ] && tr -d '\n' <"$provider_file" || printf 'prettyzap'
}

install_wacli() (
    if [ -x "$bin_dir/wacli" ] && "$bin_dir/wacli" --version 2>&1 | grep -q "$wacli_version"; then return; fi
    local arch asset checksum stage archive
    arch=$(uname -m)
    case "$arch" in
        x86_64) asset=amd64; checksum=$wacli_amd64_sha ;;
        aarch64|arm64) asset=arm64; checksum=$wacli_arm64_sha ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    stage=$(mktemp -d "${TMPDIR:-/tmp}/nbshell-wacli.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    archive="$stage/wacli.tar.gz"
    curl -fL --retry 3 "https://github.com/openclaw/wacli/releases/download/v${wacli_version}/wacli_${wacli_version}_linux_${asset}.tar.gz" -o "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c -
    tar -xzf "$archive" -C "$stage"
    install -Dm755 "$stage/wacli" "$bin_dir/wacli"
)

switch_config() {
    local selected=$1
    python3 - "$(dirname "${BASH_SOURCE[0]}")/config-write.py" "$selected" <<'PYCODE' || return $?
import runpy, sys
api = runpy.run_path(sys.argv[1])
selected = sys.argv[2]
def transform(data):
    old, new = ("prettyzap", "omawhatsapp") if selected == "omawhatsapp" else ("omawhatsapp", "prettyzap")
    for key in ("collapsedWidgets", "leftWidgets", "centerWidgets", "rightWidgets"):
        values = [str(value) for value in data.get(key, [])]
        values = [new if value in (old, "whatsapp") else value for value in values]
        data[key] = list(dict.fromkeys(values))
    enabled = [str(value) for value in data.get("enabledPlugins", []) if str(value) not in (old, new, "whatsapp")]
    enabled.append(new)
    data["enabledPlugins"] = enabled
    return data
api['update_config'](transform)
PYCODE
    printf '%s\n' "$selected" >"$provider_file"
}

setup() (
    install_wacli
    local stage archive source staged_plugin old_plugin
    stage=$(mktemp -d "${TMPDIR:-/tmp}/nbshell-omawhatsapp.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    archive="$stage/source.tar.gz"
    curl -fL --retry 3 "https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/archive/${source_revision}.tar.gz" -o "$archive"
    printf '%s  %s\n' "$source_sha" "$archive" | sha256sum -c -
    tar -xzf "$archive" -C "$stage"
    source="$stage/Omarchy-Whatsapp-$source_revision"
    staged_plugin="$stage/plugin"
    old_plugin="$stage/previous-plugin"
    install -d "$staged_plugin"
    cp -a "$source/plugins/omawhatsapp/." "$staged_plugin/"
    patch -d "$staged_plugin" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-responsive.patch"
    patch -d "$staged_plugin" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-refresh.patch"
    patch -d "$staged_plugin" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-wheel-scroll.patch"
    # Keep the upstream/internal identity stable while presenting this as a
    # normal nbshell WhatsApp client in every user-facing QML string.
    find "$staged_plugin" -type f -name '*.qml' -exec sed -i 's/OmaWhatsApp/WhatsApp/g' {} +
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/manifest.json" "$staged_plugin/manifest.json"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/BarWidget.qml" "$staged_plugin/BarWidget.qml"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/ToggleSwitch.qml" "$staged_plugin/ToggleSwitch.qml"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/FastScrollHandler.qml" "$staged_plugin/FastScrollHandler.qml"
    install -Dm644 "$source/LICENSE" "$staged_plugin/LICENSE"
    patch -d "$source" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-wacli-parity.patch"
    patch -d "$source" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-wacli-parity.patch"
    install -Dm755 "$source/bin/omawhatsapp" "$bin_dir/omawhatsapp"
    install -Dm644 "$source/bin/omawhatsapp_assets.py" "$bin_dir/omawhatsapp_assets.py"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/wacli-sync.service" "$unit_dir/wacli-sync.service"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/wacli-sync@.service" "$unit_dir/wacli-sync@.service"
    bash "$runtime_shell/scripts/plugins.sh" validate "$staged_plugin" >/dev/null
    install -d "$(dirname "$plugin_dir")"
    local defer_shell_restart=0
    if systemctl --user is-active --quiet nbshell.service \
            && grep -Fq '/nbshell.service' /proc/$$/cgroup 2>/dev/null; then
        defer_shell_restart=1
    else
        systemctl --user stop nbshell.service
    fi
    [ ! -e "$plugin_dir" ] || mv "$plugin_dir" "$old_plugin"
    mv "$staged_plugin" "$plugin_dir"
    switch_config omawhatsapp
    systemctl --user daemon-reload
    local status_json account_name unit
    local -a account_names account_units
    status_json=$("$bin_dir/omawhatsapp" status)
    if jq -e '.accounts | length == 1 and .[0].account == ""' <<<"$status_json" >/dev/null; then
        account_names=("")
        account_units=(wacli-sync.service)
    else
        mapfile -t account_names < <(jq -r '.accounts[].account' <<<"$status_json")
        account_units=()
        for account_name in "${account_names[@]}"; do
            account_units+=("wacli-sync@${account_name}.service")
        done
        systemctl --user disable --now wacli-sync.service >/dev/null 2>&1 || true
    fi
    for index in "${!account_units[@]}"; do
        unit=${account_units[$index]}
        account_name=${account_names[$index]}
        if jq -e --arg account "$account_name" \
            '.accounts[] | select(.account == $account) | .online == false' \
            <<<"$status_json" >/dev/null; then
            systemctl --user disable --now "$unit" >/dev/null
        else
            systemctl --user enable "$unit" >/dev/null
            systemctl --user restart "$unit"
        fi
    done
    if [ "$defer_shell_restart" -eq 1 ]; then
        echo "WhatsApp installed. Shell restart deferred until the next external restart or login."
    else
        systemctl --user restart nbshell.service
        echo "WhatsApp installed. Run: nbshell whatsapp auth"
    fi
)

case "$command_name" in
    setup) setup ;;
    provider)
        selected=${2:?expected whatsapp or prettyzap}
        case "$selected" in
            whatsapp|native|omawhatsapp) selected=omawhatsapp ;;
            prettyzap) ;;
            *) exit 2 ;;
        esac
        [ "$selected" != omawhatsapp ] || [ -f "$plugin_dir/manifest.json" ] || { echo "Run setup first." >&2; exit 1; }
        switch_config "$selected"
        systemctl --user restart nbshell.service
        ;;
    auth) exec "$bin_dir/omawhatsapp" auth ;;
    current) provider ;;
    status)
        selected=$(provider)
        [ "$selected" != omawhatsapp ] || selected=whatsapp
        printf 'provider=%s\n' "$selected"
        [ ! -x "$bin_dir/wacli" ] || "$bin_dir/wacli" --version
        [ ! -x "$bin_dir/omawhatsapp" ] || "$bin_dir/omawhatsapp" status
        ;;
    *) echo "Usage: nbshell whatsapp setup|auth|status|provider whatsapp|prettyzap" >&2; exit 2 ;;
esac
