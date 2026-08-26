#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-memory-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.config" "$WORK/bin"

cat >"$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" is-active systemd-oomd.service "*) echo active ;;
    *" show nbshell.service "*) echo session.slice ;;
    *" show app.slice "*)
        case "$*" in
            *ManagedOOMMemoryPressureLimit*) echo 60% ;;
            *ManagedOOMMemoryPressureDurationUSec*) echo 20s ;;
            *ManagedOOMMemoryPressure*) echo kill ;;
            *ManagedOOMSwap*) echo kill ;;
        esac
        ;;
    *) : ;;
esac
EOF
cat >"$WORK/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "true" ]; then exit 0; fi
[ "${1:-}" = "-n" ] && shift
exec "$@"
EOF
chmod +x "$WORK/bin/systemctl" "$WORK/bin/sudo"

export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$WORK/bin:/usr/bin:/bin"
TOOL="$ROOT/shell/scripts/memory-guard.sh"

bash "$TOOL" status --json | jq -e '.configured == false and .protected == false' >/dev/null
bash "$TOOL" setup >/dev/null
DROPIN="$XDG_CONFIG_HOME/systemd/user/app.slice.d/90-nbshell-memory-guard.conf"
test -f "$DROPIN"
grep -Fq 'ManagedOOMMemoryPressureLimit=60%' "$DROPIN"
grep -Fq 'ManagedOOMMemoryPressureDurationSec=20s' "$DROPIN"
bash "$TOOL" status --json | jq -e '
    .configured == true and .protected == true and
    .shellSlice == "session.slice" and .appPressure == "kill"
' >/dev/null
bash "$TOOL" remove >/dev/null
test ! -e "$DROPIN"

echo "Memory guard lifecycle: OK"
