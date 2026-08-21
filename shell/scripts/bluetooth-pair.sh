#!/usr/bin/env bash
set -euo pipefail

address="${1:-}"
name="${2:-Bluetooth device}"

if [[ ! $address =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
	printf 'Invalid Bluetooth address: %s\n' "$address" >&2
	exit 64
fi

command -v bluetoothctl >/dev/null 2>&1 || {
	printf 'bluetoothctl is not installed\n' >&2
	exit 69
}

# Quickshell exposes BlueZ devices but does not implement a pairing agent.
# Keep one bluetoothctl session alive for pairing *and* the service
# authorization that follows it. A one-shot `bluetoothctl --agent ... pair`
# exits too early on BlueZ 5.87 and leaves A2DP authorization without an agent.
runtime=$(mktemp -d)
fifo="$runtime/input"
log="$runtime/output"
mkfifo "$fifo"
bt_pid=""
cleanup() {
	[[ -z $bt_pid ]] || kill "$bt_pid" >/dev/null 2>&1 || true
	rm -rf -- "$runtime"
}
trap cleanup EXIT

bluetoothctl --agent NoInputNoOutput < "$fifo" > "$log" 2>&1 &
bt_pid=$!
exec 3> "$fifo"
printf '%s\n' 'default-agent' 'scan on' >&3

available=false
for _ in $(seq 1 30); do
	if bluetoothctl info "$address" >/dev/null 2>&1; then
		available=true
		break
	fi
	if ! kill -0 "$bt_pid" 2>/dev/null; then
		break
	fi
	sleep 1
done

if [[ $available != true ]]; then
	tail -20 "$log" >&2
	exit 1
fi

printf '%s\n' "pair $address" >&3

paired=false
for _ in $(seq 1 45); do
	if bluetoothctl info "$address" 2>/dev/null | grep -q 'Paired: yes'; then
		paired=true
		break
	fi
	if ! kill -0 "$bt_pid" 2>/dev/null; then
		break
	fi
	sleep 1
done

if [[ $paired != true ]]; then
	tail -20 "$log" >&2
	exit 1
fi

# `yes` answers a pending audio-profile authorization. If there is no prompt,
# bluetoothctl treats it as an unknown command and continues harmlessly.
printf '%s\n' 'yes' "trust $address" "connect $address" 'scan off' >&3
sleep 3
printf '%s\n' 'quit' >&3
exec 3>&-
wait "$bt_pid" || true
bt_pid=""

if ! bluetoothctl info "$address" 2>/dev/null | grep -q 'Paired: yes'; then
	printf 'BlueZ did not retain the pairing for %s\n' "$name" >&2
	exit 1
fi

printf 'Paired %s\n' "$name"
