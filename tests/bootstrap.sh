#!/usr/bin/env bash
#
# Test suite for nbshell bootstrap.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-bootstrap-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

pass() {
	printf '\033[32mPASS\033[0m: %s\n' "$1"
	passed=$((passed + 1))
}

fail() {
	printf '\033[31mFAIL\033[0m: %s\n' "$1"
	printf '  Detail: %s\n' "${2:-none}" >&2
	failed=$((failed + 1))
}

# ── Fixture Creation ────────────────────────────────────────────────────────
MOCK_DIR="$WORK/fixtures"
mkdir -p "$MOCK_DIR/build" "$MOCK_DIR/assets" "$WORK/bin"
cat >"$WORK/bin/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${NBSHELL_TEST_COSIGN_FAIL:-0}" != "1" ] || exit 1
[[ "$*" == *"verify-blob"* && "$*" == *"--bundle"* && "$*" == *"release.yml@refs/tags/v"* ]]
EOF
chmod +x "$WORK/bin/cosign"
export PATH="$WORK/bin:$PATH"

build_mock_release() {
	local version="$1"
	local tree_dir="$MOCK_DIR/build/nbshell-$version"
	mkdir -p "$tree_dir"
	cat >"$tree_dir/setup.sh" <<EOF
#!/usr/bin/env bash
echo "$version" > "$WORK/executed_version.log"
echo "\$*" > "$WORK/executed_args.log"
exit 0
EOF
	chmod +x "$tree_dir/setup.sh"
	printf '%s\n' "$version" > "$tree_dir/VERSION"

	local archive="$MOCK_DIR/assets/nbshell-$version.tar.gz"
	tar -czf "$archive" -C "$MOCK_DIR/build" "nbshell-$version"
	sha256sum "$archive" | awk '{print $1 "  " $2}' > "$archive.sha256"
	printf '{"fixture":true}\n' > "$archive.sigstore.json"
}

build_mock_release "0.0.9"
build_mock_release "0.1.0-beta.6"
build_mock_release "0.1.0-beta.7"

cat >"$MOCK_DIR/releases.json" <<EOF
[
  {
    "tag_name": "v0.1.0-beta.7",
    "draft": false,
    "prerelease": true,
    "html_url": "https://github.com/nerdislb/nbshell/releases/tag/v0.1.0-beta.7",
    "assets": [
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.7.tar.gz"
      },
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz.sha256",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.7.tar.gz.sha256"
      },
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz.sigstore.json",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.7.tar.gz.sigstore.json"
      }
    ]
  },
  {
    "tag_name": "v0.1.0-beta.6",
    "draft": false,
    "prerelease": true,
    "html_url": "https://github.com/nerdislb/nbshell/releases/tag/v0.1.0-beta.6",
    "assets": [
      {
        "name": "nbshell-0.1.0-beta.6.tar.gz",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.6.tar.gz"
      },
      {
        "name": "nbshell-0.1.0-beta.6.tar.gz.sha256",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.6.tar.gz.sha256"
      },
      {
        "name": "nbshell-0.1.0-beta.6.tar.gz.sigstore.json",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.1.0-beta.6.tar.gz.sigstore.json"
      }
    ]
  },
  {
    "tag_name": "v0.0.9",
    "draft": false,
    "prerelease": false,
    "html_url": "https://github.com/nerdislb/nbshell/releases/tag/v0.0.9",
    "assets": [
      {
        "name": "nbshell-0.0.9.tar.gz",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.0.9.tar.gz"
      },
      {
        "name": "nbshell-0.0.9.tar.gz.sha256",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.0.9.tar.gz.sha256"
      },
      {
        "name": "nbshell-0.0.9.tar.gz.sigstore.json",
        "browser_download_url": "file://$MOCK_DIR/assets/nbshell-0.0.9.tar.gz.sigstore.json"
      }
    ]
  }
]
EOF

# ── Test 1: Help option ─────────────────────────────────────────────────────
set +e
out="$("$ROOT/bootstrap.sh" --help 2>&1)"
status=$?
set -e
if [ $status -eq 0 ] && [[ "$out" == *"bootstrap.sh -- download, verify, and run"* ]]; then
	pass "Help output"
else
	fail "Help output" "status=$status out=$out"
fi

# ── Test 2: Invalid channel validation ──────────────────────────────────────
set +e
out="$("$ROOT/bootstrap.sh" --channel nightly 2>&1)"
status=$?
set -e
if [ $status -eq 2 ] && [[ "$out" == *"Invalid channel"* ]]; then
	pass "Reject invalid channel"
else
	fail "Reject invalid channel" "status=$status out=$out"
fi

# ── Test 3: Unknown option validation ───────────────────────────────────────
set +e
out="$("$ROOT/bootstrap.sh" --unknown-option 2>&1)"
status=$?
set -e
if [ $status -eq 2 ] && [[ "$out" == *"Unknown option"* ]]; then
	pass "Reject unknown option"
else
	fail "Reject unknown option" "status=$status out=$out"
fi

# ── Test 4: Missing channel argument ────────────────────────────────────────
set +e
out="$("$ROOT/bootstrap.sh" --channel 2>&1)"
status=$?
set -e
if [ $status -eq 2 ] && [[ "$out" == *"requires an argument"* ]]; then
	pass "Reject missing channel argument"
else
	fail "Reject missing channel argument" "status=$status out=$out"
fi

# ── Test 5: Missing version argument ────────────────────────────────────────
set +e
out="$("$ROOT/bootstrap.sh" --version 2>&1)"
status=$?
set -e
if [ $status -eq 2 ] && [[ "$out" == *"requires an argument"* ]]; then
	pass "Reject missing version argument"
else
	fail "Reject missing version argument" "status=$status out=$out"
fi

# ── Test 6: Beta channel release selection ──────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel beta 2>&1)"
status=$?
set -e
if [ $status -eq 0 ] && [ -f "$WORK/executed_version.log" ] && [ "$(cat "$WORK/executed_version.log")" = "0.1.0-beta.7" ]; then
	pass "Beta channel selection"
else
	fail "Beta channel selection" "status=$status out=$out executed=$(cat "$WORK/executed_version.log" 2>/dev/null || echo none)"
fi

# ── Test 7: Stable channel release selection ────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel stable 2>&1)"
status=$?
set -e
if [ $status -eq 0 ] && [ -f "$WORK/executed_version.log" ] && [ "$(cat "$WORK/executed_version.log")" = "0.0.9" ]; then
	pass "Stable channel selection (excludes prereleases)"
else
	fail "Stable channel selection" "status=$status out=$out executed=$(cat "$WORK/executed_version.log" 2>/dev/null || echo none)"
fi

# ── Test 8: Explicit version selection ──────────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --version 0.1.0-beta.6 2>&1)"
status=$?
set -e
if [ $status -eq 0 ] && [ -f "$WORK/executed_version.log" ] && [ "$(cat "$WORK/executed_version.log")" = "0.1.0-beta.6" ]; then
	pass "Explicit version selection"
else
	fail "Explicit version selection" "status=$status out=$out executed=$(cat "$WORK/executed_version.log" 2>/dev/null || echo none)"
fi

# ── Test 9: Argument forwarding to setup.sh ─────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel beta --full --yes --no-aur 2>&1)"
status=$?
set -e
args="$(cat "$WORK/executed_args.log" 2>/dev/null || echo "")"
if [ $status -eq 0 ] && [[ "$args" == *"--full"* ]] && [[ "$args" == *"--yes"* ]] && [[ "$args" == *"--no-aur"* ]]; then
	pass "Argument forwarding to setup.sh"
else
	fail "Argument forwarding to setup.sh" "status=$status args=$args out=$out"
fi

# ── Test 10: Checksum mismatch rejection ────────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
CORRUPT_DIR="$WORK/corrupt"
mkdir -p "$CORRUPT_DIR"
cp "$MOCK_DIR/releases.json" "$CORRUPT_DIR/releases.json"
mkdir -p "$CORRUPT_DIR/assets"
cp "$MOCK_DIR/assets"/* "$CORRUPT_DIR/assets/"
# Corrupt the sha256 checksum file
printf '0000000000000000000000000000000000000000000000000000000000000000  nbshell-0.1.0-beta.7.tar.gz\n' > "$CORRUPT_DIR/assets/nbshell-0.1.0-beta.7.tar.gz.sha256"
sed -i "s|$MOCK_DIR/assets|$CORRUPT_DIR/assets|g" "$CORRUPT_DIR/releases.json"

set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$CORRUPT_DIR/releases.json" "$ROOT/bootstrap.sh" --channel beta 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [ ! -f "$WORK/executed_version.log" ] && [[ "$out" == *"Checksum verification failed"* ]]; then
	pass "Reject corrupted archive on checksum mismatch"
else
	fail "Reject corrupted archive on checksum mismatch" "status=$status out=$out executed=$(test -f "$WORK/executed_version.log" && echo yes || echo no)"
fi

# ── Test 11: Unsafe path traversal rejection ────────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
UNSAFE_DIR="$WORK/unsafe"
mkdir -p "$UNSAFE_DIR/build" "$UNSAFE_DIR/assets"
cat >"$UNSAFE_DIR/build/setup.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$UNSAFE_DIR/build/setup.sh"
(
	cd "$UNSAFE_DIR/build"
	tar -czf "$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz" --transform 's|^|../escape/|' setup.sh
)
sha256sum "$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz" | awk '{print $1 "  " $2}' > "$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz.sha256"
printf '{}\n' > "$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz.sigstore.json"

cat >"$UNSAFE_DIR/releases.json" <<EOF
[
  {
    "tag_name": "v0.2.0",
    "draft": false,
    "prerelease": false,
    "assets": [
      {
        "name": "nbshell-0.2.0.tar.gz",
        "browser_download_url": "file://$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz"
      },
      {
        "name": "nbshell-0.2.0.tar.gz.sha256",
        "browser_download_url": "file://$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz.sha256"
      },
      {
        "name": "nbshell-0.2.0.tar.gz.sigstore.json",
        "browser_download_url": "file://$UNSAFE_DIR/assets/nbshell-0.2.0.tar.gz.sigstore.json"
      }
    ]
  }
]
EOF

set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$UNSAFE_DIR/releases.json" "$ROOT/bootstrap.sh" --channel stable 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [ ! -f "$WORK/executed_version.log" ] && [[ "$out" == *"Unsafe path detected"* ]]; then
	pass "Reject archive path traversal"
else
	fail "Reject archive path traversal" "status=$status out=$out"
fi

# ── Test 12: Python-free execution ──────────────────────────────────────────
CLEAN_BIN="$WORK/clean-bin"
mkdir -p "$CLEAN_BIN"
for tool in bash sh cat cp rm mkdir mktemp id cut tr awk tar gzip sha256sum grep sed dirname basename curl wc cosign; do
	tool_path="$(command -v "$tool" || true)"
	if [ -n "$tool_path" ]; then
		ln -sf "$tool_path" "$CLEAN_BIN/$tool"
	fi
done

rm -f "$WORK/executed_version.log"
set +e
out="$(PATH="$CLEAN_BIN" NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" "$ROOT/bootstrap.sh" --channel beta 2>&1)"
status=$?
set -e
if [ $status -eq 0 ] && [ -f "$WORK/executed_version.log" ]; then
	pass "Python-free runtime execution"
else
	fail "Python-free runtime execution" "status=$status out=$out"
fi

# ── Test 13: Cleanup trap execution ─────────────────────────────────────────
TMP_TRACK="$WORK/tmp_track"
mkdir -p "$TMP_TRACK"
set +e
TMPDIR="$TMP_TRACK" NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$MOCK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel beta >/dev/null 2>&1
set -e
remaining="$(find "$TMP_TRACK" -maxdepth 1 -name 'nbshell-bootstrap.*' | wc -l)"
if [ "$remaining" -eq 0 ]; then
	pass "Cleanup trap removes temp directory on exit"
else
	fail "Cleanup trap removes temp directory on exit" "remaining=$remaining"
fi

# ── Test 14: HTTPS enforcement in production mode ───────────────────────────
PROD_MOCK_DIR="$WORK/prod-mock"
mkdir -p "$PROD_MOCK_DIR/bin"
cat >"$PROD_MOCK_DIR/releases.json" <<EOF
[
  {
    "tag_name": "v0.1.0-beta.7",
    "draft": false,
    "prerelease": true,
    "assets": [
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz",
        "browser_download_url": "http://insecure.example.com/nbshell-0.1.0-beta.7.tar.gz"
      },
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz.sha256",
        "browser_download_url": "http://insecure.example.com/nbshell-0.1.0-beta.7.tar.gz.sha256"
      },
      {
        "name": "nbshell-0.1.0-beta.7.tar.gz.sigstore.json",
        "browser_download_url": "http://insecure.example.com/nbshell-0.1.0-beta.7.tar.gz.sigstore.json"
      }
    ]
  }
]
EOF

cat >"$PROD_MOCK_DIR/bin/curl" <<EOF
#!/usr/bin/env bash
# Mock curl that returns insecure releases.json for API call
cp "$PROD_MOCK_DIR/releases.json" "\${@: -1}"
EOF
chmod +x "$PROD_MOCK_DIR/bin/curl"

set +e
out="$(PATH="$PROD_MOCK_DIR/bin:$PATH" NBSHELL_ALLOW_INSECURE_ASSETS=0 NBSHELL_API_URL="https://api.github.com/repos/nerdislb/nbshell/releases" "$ROOT/bootstrap.sh" --channel beta 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [[ "$out" == *"Insecure asset download URL detected"* ]]; then
	pass "HTTPS URL enforcement for production release assets"
else
	fail "HTTPS URL enforcement for production release assets" "status=$status out=$out"
fi

# ── Test 15: Root user rejection ─────────────────────────────────────────────
ROOT_MOCK_DIR="$WORK/root-mock/bin"
mkdir -p "$ROOT_MOCK_DIR"
cat >"$ROOT_MOCK_DIR/id" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then
	echo "0"
	exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$ROOT_MOCK_DIR/id"

set +e
out="$(PATH="$ROOT_MOCK_DIR:$PATH" "$ROOT/bootstrap.sh" --help 2>&1)"
status=$?
set -e
if [ $status -eq 1 ] && [[ "$out" == *"Do not run this script as root"* ]]; then
	pass "Reject execution as root"
else
	fail "Reject execution as root" "status=$status out=$out"
fi

# ── Test 16: Link member rejection ──────────────────────────────────────────
LINK_DIR="$WORK/link-member"
mkdir -p "$LINK_DIR/build/nbshell-0.3.0" "$LINK_DIR/assets"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$LINK_DIR/build/nbshell-0.3.0/setup.sh"
chmod +x "$LINK_DIR/build/nbshell-0.3.0/setup.sh"
ln -s /tmp "$LINK_DIR/build/nbshell-0.3.0/redirect"
tar -czf "$LINK_DIR/assets/nbshell-0.3.0.tar.gz" -C "$LINK_DIR/build" nbshell-0.3.0
sha256sum "$LINK_DIR/assets/nbshell-0.3.0.tar.gz" >"$LINK_DIR/assets/nbshell-0.3.0.tar.gz.sha256"
printf '{}\n' > "$LINK_DIR/assets/nbshell-0.3.0.tar.gz.sigstore.json"
cat >"$LINK_DIR/releases.json" <<EOF
[{"tag_name":"v0.3.0","draft":false,"prerelease":false,"assets":[
{"name":"nbshell-0.3.0.tar.gz","browser_download_url":"file://$LINK_DIR/assets/nbshell-0.3.0.tar.gz"},
{"name":"nbshell-0.3.0.tar.gz.sha256","browser_download_url":"file://$LINK_DIR/assets/nbshell-0.3.0.tar.gz.sha256"},
{"name":"nbshell-0.3.0.tar.gz.sigstore.json","browser_download_url":"file://$LINK_DIR/assets/nbshell-0.3.0.tar.gz.sigstore.json"}]}]
EOF
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$LINK_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel stable 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [[ "$out" == *"contains links, special files"* ]]; then
	pass "Reject link members before extraction"
else
	fail "Reject link members before extraction" "status=$status out=$out"
fi

# ── Test 17: Bare parent member rejection ───────────────────────────────────
PARENT_DIR="$WORK/bare-parent"
mkdir -p "$PARENT_DIR/assets"
python3 - "$PARENT_DIR/assets/nbshell-0.4.0.tar.gz" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as archive:
    member = tarfile.TarInfo("..")
    member.size = 1
    archive.addfile(member, io.BytesIO(b"x"))
PY
sha256sum "$PARENT_DIR/assets/nbshell-0.4.0.tar.gz" >"$PARENT_DIR/assets/nbshell-0.4.0.tar.gz.sha256"
printf '{}\n' > "$PARENT_DIR/assets/nbshell-0.4.0.tar.gz.sigstore.json"
cat >"$PARENT_DIR/releases.json" <<EOF
[{"tag_name":"v0.4.0","draft":false,"prerelease":false,"assets":[
{"name":"nbshell-0.4.0.tar.gz","browser_download_url":"file://$PARENT_DIR/assets/nbshell-0.4.0.tar.gz"},
{"name":"nbshell-0.4.0.tar.gz.sha256","browser_download_url":"file://$PARENT_DIR/assets/nbshell-0.4.0.tar.gz.sha256"},
{"name":"nbshell-0.4.0.tar.gz.sigstore.json","browser_download_url":"file://$PARENT_DIR/assets/nbshell-0.4.0.tar.gz.sigstore.json"}]}]
EOF
set +e
out="$(NBSHELL_ALLOW_INSECURE_ASSETS=1 NBSHELL_API_URL="file://$PARENT_DIR/releases.json" \
	"$ROOT/bootstrap.sh" --channel stable 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [[ "$out" == *"Unsafe path detected"* ]]; then
	pass "Reject bare parent archive member"
else
	fail "Reject bare parent archive member" "status=$status out=$out"
fi

# ── Test 18: Invalid Sigstore signature rejection ────────────────────────────
rm -f "$WORK/executed_version.log" "$WORK/executed_args.log"
set +e
out="$(NBSHELL_TEST_COSIGN_FAIL=1 NBSHELL_ALLOW_INSECURE_ASSETS=1 \
	NBSHELL_API_URL="file://$MOCK_DIR/releases.json" "$ROOT/bootstrap.sh" --channel beta 2>&1)"
status=$?
set -e
if [ $status -ne 0 ] && [ ! -f "$WORK/executed_version.log" ] && [[ "$out" == *"Sigstore signature verification failed"* ]]; then
	pass "Reject release with invalid Sigstore signature"
else
	fail "Reject release with invalid Sigstore signature" "status=$status out=$out"
fi

# ── Test Summary ────────────────────────────────────────────────────────────
printf '\n\033[1mSummary: %d passed, %d failed\033[0m\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
