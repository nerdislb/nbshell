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

sync_accounts() {
    local status_json=$1 account_name unit online
    # Account names are UI identities: a legacy store is displayed as primary,
    # but has no wacli --account configuration. The helper owns that distinction.
    # Validate the complete plan before changing any services.
    jq -e '
        .ok == true and (.accounts | type == "array" and length > 0) and
        all(.accounts[];
            (.account | type == "string") and
            (.account | test("^[A-Za-z0-9_-]*$")) and
            (.unit == "wacli-sync.service" or
                (.account != "" and .unit == ("wacli-sync@" + .account + ".service"))) and
            (.online | type == "boolean")) and
        ([.accounts[].unit] | length == (unique | length))
    ' <<<"$status_json" >/dev/null || {
        echo "Invalid WhatsApp sync service plan." >&2
        return 1
    }
    if ! jq -e 'any(.accounts[]; .unit == "wacli-sync.service")' \
            <<<"$status_json" >/dev/null; then
        systemctl --user disable --now wacli-sync.service >/dev/null 2>&1 || true
    fi
    while IFS=$'\t' read -r unit online account_name; do
        # Repair older nbshell setups that derived @primary from the display
        # name even though this account uses the unconfigured root store.
        if [ "$unit" = wacli-sync.service ] && [ -n "$account_name" ]; then
            systemctl --user disable --now "wacli-sync@${account_name}.service" \
                >/dev/null 2>&1 || true
        fi
        if [ "$online" = false ]; then
            systemctl --user disable --now "$unit" >/dev/null
        else
            systemctl --user enable "$unit" >/dev/null
            systemctl --user restart "$unit"
        fi
    done < <(jq -r '.accounts[] | [.unit, .online, .account] | @tsv' <<<"$status_json")
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
    patch -d "$staged_plugin" -p1 < "$runtime_shell/integrations/omawhatsapp/nbshell-save-media.patch"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/MediaSaveButton.qml" "$staged_plugin/MediaSaveButton.qml"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/save-media.py" "$staged_plugin/save-media.py"
    # Keep the upstream/internal identity stable while presenting this as a
    # normal nbshell WhatsApp client in every user-facing QML string.
    find "$staged_plugin" -type f -name '*.qml' -exec sed -i 's/OmaWhatsApp/WhatsApp/g' {} +
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/manifest.json" "$staged_plugin/manifest.json"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/BarWidget.qml" "$staged_plugin/BarWidget.qml"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/ToggleSwitch.qml" "$staged_plugin/ToggleSwitch.qml"
    install -Dm644 "$runtime_shell/integrations/omawhatsapp/FastScrollHandler.qml" "$staged_plugin/FastScrollHandler.qml"
    install -Dm644 "$source/LICENSE" "$staged_plugin/LICENSE"
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
    sync_accounts "$("$bin_dir/omawhatsapp" status)"
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
