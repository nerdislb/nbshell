#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/.calendar-backend-test.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/config/khal"
export XDG_CONFIG_HOME="$WORK/config"
export PATH="$WORK/bin:$PATH"
export KHAL_ARGS="$WORK/khal-args"
TOOL="$ROOT/shell/scripts/calendar.sh"

cat >"$WORK/bin/khal" <<'EOF'
#!/usr/bin/env bash
set -eu
: >"$KHAL_ARGS"
for arg in "$@"; do printf '%s\n' "$arg" >>"$KHAL_ARGS"; done
EOF
chmod +x "$WORK/bin/khal"

cat >"$XDG_CONFIG_HOME/khal/config" <<'EOF'
[locale]
dateformat = %d.%m.%Y
timeformat = %H:%M

[calendars]
[[Personal calendar]]
path = /does/not/matter/personal

[[Company]]
path = /does/not/matter/company
readonly = true

[[Case insensitive]]
path = /does/not/matter/case
readonly = FALSE
EOF

assert_fails_with() {
	local expected="$1"
	shift
	local output
	if output="$("$@" 2>&1)"; then
		echo "expected command to fail: $*" >&2
		exit 1
	fi
	[[ "$output" == *"$expected"* ]] || {
		echo "expected error containing '$expected', got: $output" >&2
		exit 1
	}
}

expected_calendars=$'Personal calendar\nCase insensitive'
actual_calendars="$(bash "$TOOL" writable-calendars)"
[[ "$actual_calendars" = "$expected_calendars" ]]

title='Planning; touch HACKED $(printf injected) `id` & done'
bash "$TOOL" create "Personal calendar" "2026-09-02T09:15" "2026-09-02T10:45" "$title"
mapfile -t args <"$KHAL_ARGS"
[[ "${#args[@]}" -eq 6 ]]
[[ "${args[0]}" = new ]]
[[ "${args[1]}" = --calendar ]]
[[ "${args[2]}" = "Personal calendar" ]]
[[ "${args[3]}" = "02.09.2026 09:15" ]]
[[ "${args[4]}" = "02.09.2026 10:45" ]]
[[ "${args[5]}" = "$title" ]]
[[ ! -e "$ROOT/HACKED" && ! -e "$WORK/HACKED" ]]

assert_fails_with "not configured as writable" bash "$TOOL" create Company "2026-09-02T09:00" "2026-09-02T10:00" Meeting
assert_fails_with "valid local ISO" bash "$TOOL" create "Personal calendar" nonsense "2026-09-02T10:00" Meeting
assert_fails_with "after start" bash "$TOOL" create "Personal calendar" "2026-09-02T11:00" "2026-09-02T10:00" Meeting
assert_fails_with "event title" bash "$TOOL" create "Personal calendar" "2026-09-02T09:00" "2026-09-02T10:00" '   '

echo "calendar backend tests passed"
