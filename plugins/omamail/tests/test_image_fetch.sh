#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/image-fetch.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/omamail-image-fetch-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM HUP
failures=0

ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); }
contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1"; fi
}
missing() {
  if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1"; else ok "$1"; fi
}
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
config=$(cat)
printf '%s' "$config" > "$CURL_STUB_DUMP"
output=$(printf '%s\n' "$config" | sed -n 's/^output = "\(.*\)"$/\1/p')
printf '\211PNG\r\n\032\nbytes' > "$output"
printf '200 image/png'
STUB
chmod +x "$work/bin/curl"
cat > "$work/bin/python3" <<'STUB'
#!/bin/sh
printf '%s\n' 'cdn.example.com:443:203.0.113.10'
STUB
chmod +x "$work/bin/python3"

answer=$(printf '%s\n' "$(b64 'https://cdn.example.com/a.png?token=x y')" |
  CURL_STUB_DUMP="$work/config" PATH="$work/bin:$PATH" sh "$script")
config=$(cat "$work/config")

printf 'image-fetch.sh\n'
contains "the URL reaches curl through its config" "$config" 'url = "https://cdn.example.com/a.png?token=x y"'
contains "the validated address is pinned against DNS rebinding" "$config" 'resolve = "cdn.example.com:443:203.0.113.10"'
contains "redirects are refused" "$config" 'max-redirs = 0'
contains "the download is bounded" "$config" 'max-filesize = 5242880'
contains "the exchange has a deadline" "$config" 'max-time = 20'
missing "curl is never told to follow" "$config" 'location'
contains "a validated image returns as a data URI" "$answer" 'data:image/png;base64,'

set +e
printf '%s\n' "$(b64 'file:///etc/passwd')" | PATH="$work/bin:$PATH" sh "$script" >/dev/null 2>&1
code=$?
set -e
if [ "$code" -ne 0 ]; then ok "a non-network URL is refused"; else bad "a non-network URL is refused"; fi

if python3 "$root/scripts/resolve-public-url.py" 'http://127.0.0.1/private' >/dev/null 2>&1; then
  bad "the resolver refuses loopback destinations"
else
  ok "the resolver refuses loopback destinations"
fi

[ "$failures" -eq 0 ]
