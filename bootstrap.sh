#!/usr/bin/env bash
#
# nbshell one-command bootstrap installer.
#
# Downloads, verifies, and runs the nbshell installer from published releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nerdislb/nbshell/main/bootstrap.sh -O && bash bootstrap.sh [options]
#
# Or run with channel / options:
#   bash bootstrap.sh --channel beta --full --yes
#
set -euo pipefail

green() { printf '\033[32m%s\033[0m\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() {
	printf '\033[31m%s\033[0m\n' "$*" >&2
	exit 1
}

[ "$(id -u)" != "0" ] || die "Do not run this script as root. nbshell is installed in your home directory."

show_help() {
	cat <<'USAGE'
bootstrap.sh -- download, verify, and run the nbshell installer.

Usage:
  bootstrap.sh [options] [-- [setup options]]

Options:
  --channel <beta|stable>  Select release channel (default: beta)
  --version <version>      Install a specific nbshell version
  --full                   Install optional desktop and capture tools
  --no-packages            Install files only (same as install.sh)
  --with-greeter           Install Orbital login screen
  --no-greeter             Do not install Orbital login screen
  --no-aur                 Do not offer to install an AUR helper
  --with-hardware          Include hardware-specific legacy packages
  --with-legacy-dotfiles   Optionally migrate old DMS dotfiles
  -y, --yes                Accept normal package and service prompts
  -h, --help               Show this help message

Verification:
  Release archives require a tag-bound Sigstore signature and a matching
  SHA-256 checksum before extraction.
USAGE
}

CHANNEL="beta"
EXPLICIT_VERSION=""
FORWARD_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
	--channel)
		[ $# -ge 2 ] || { printf 'Option --channel requires an argument.\n' >&2; exit 2; }
		shift
		case "$1" in
		beta|stable) CHANNEL="$1" ;;
		*) printf 'Invalid channel: %s (must be "beta" or "stable")\n' "$1" >&2; exit 2 ;;
		esac
		;;
	--channel=*)
		val="${1#*=}"
		case "$val" in
		beta|stable) CHANNEL="$val" ;;
		*) printf 'Invalid channel: %s (must be "beta" or "stable")\n' "$val" >&2; exit 2 ;;
		esac
		;;
	--version)
		[ $# -ge 2 ] || { printf 'Option --version requires an argument.\n' >&2; exit 2; }
		shift
		EXPLICIT_VERSION="${1#v}"
		;;
	--version=*)
		val="${1#*=}"
		EXPLICIT_VERSION="${val#v}"
		;;
	--full|--no-packages|--with-greeter|--no-greeter|-y|--yes|--no-aur|--with-hardware|--with-legacy-dotfiles|--with-dotfiles|--no-dotfiles)
		FORWARD_ARGS+=("$1")
		;;
	--)
		shift
		FORWARD_ARGS+=("$@")
		break
		;;
	-h|--help)
		show_help
		exit 0
		;;
	*)
		printf 'Unknown option: %s (see --help)\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

for cmd in tar gzip awk wc; do
	command -v "$cmd" >/dev/null 2>&1 || die "Required command missing: $cmd"
done
if [ -x /usr/bin/cosign ]; then
	COSIGN_BIN=/usr/bin/cosign
else
	COSIGN_BIN="$(command -v cosign || true)"
fi
if [ -z "$COSIGN_BIN" ] && command -v pacman >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
	printf 'Installing the signed Arch cosign package for release verification …\n'
	sudo pacman -S --needed cosign
	COSIGN_BIN=/usr/bin/cosign
fi
[ -x "$COSIGN_BIN" ] || die "cosign is required for release signature verification."

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
	die "sha256sum (or shasum) is required for checksum verification."
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
	die "curl or wget is required to download release assets."
fi

download_file() {
	local url="$1" dest="$2" max_bytes="$3"
	if [[ "$url" == file://* ]]; then
		local path="${url#file://}"
		cp "$path" "$dest"
	elif [[ "$url" =~ ^/ ]]; then
		cp "$url" "$dest"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL --proto '=https' --retry 3 --max-filesize "$max_bytes" "$url" -o "$dest"
	elif command -v wget >/dev/null 2>&1; then
		(ulimit -f $((max_bytes / 512 + 1)); wget --https-only -qO "$dest" "$url")
	else
		die "No download tool available."
	fi
	[ "$(wc -c < "$dest")" -le "$max_bytes" ] || die "Download exceeded the configured size limit: $url"
}

compute_sha256() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	fi
}

REPOSITORY="${NBSHELL_REPOSITORY:-nerdislb/nbshell}"
API_URL="${NBSHELL_API_URL:-https://api.github.com/repos/$REPOSITORY/releases?per_page=30}"
ALLOW_INSECURE_ASSETS="${NBSHELL_ALLOW_INSECURE_ASSETS:-0}"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-bootstrap.XXXXXX")"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

head2 "nbshell bootstrap"
printf 'Fetching release metadata (%s channel) …\n' "$CHANNEL"

RELEASES_JSON="$TEMP_DIR/releases.json"
if ! download_file "$API_URL" "$RELEASES_JSON" 5242880; then
	die "Failed to fetch release metadata from $API_URL"
fi

RELEASE_INFO="$(awk -v CHANNEL="$CHANNEL" -v TARGET_VER="$EXPLICIT_VERSION" '
function tokenize_json(str, tokens,    len, i, ch, next_ch, tok, num_tokens) {
	len = length(str);
	num_tokens = 0;
	i = 1;
	while (i <= len) {
		ch = substr(str, i, 1);
		if (ch ~ /[ \t\r\n]/) {
			i++;
			continue;
		}
		if (ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == ",") {
			tokens[++num_tokens] = ch;
			i++;
			continue;
		}
		if (ch == "\"") {
			tok = "";
			i++;
			while (i <= len) {
				ch = substr(str, i, 1);
				if (ch == "\\") {
					next_ch = substr(str, i + 1, 1);
					if (next_ch == "\"") { tok = tok "\""; i += 2; continue; }
					else if (next_ch == "\\") { tok = tok "\\"; i += 2; continue; }
					else if (next_ch == "/") { tok = tok "/"; i += 2; continue; }
					else if (next_ch == "n") { tok = tok "\n"; i += 2; continue; }
					else if (next_ch == "t") { tok = tok "\t"; i += 2; continue; }
					else if (next_ch == "r") { tok = tok "\r"; i += 2; continue; }
					else { tok = tok next_ch; i += 2; continue; }
				} else if (ch == "\"") {
					i++;
					break;
				} else {
					tok = tok ch;
					i++;
				}
			}
			tokens[++num_tokens] = "\"" tok "\"";
			continue;
		}
		tok = "";
		while (i <= len) {
			ch = substr(str, i, 1);
			if (ch ~ /[ \t\r\n,:\{\}\[\]]/) break;
			tok = tok ch;
			i++;
		}
		tokens[++num_tokens] = tok;
	}
	return num_tokens;
}

function parse_semver(v, out,    dash_pos, main_part, pre_part, m) {
	gsub(/^v/, "", v);
	dash_pos = index(v, "-");
	if (dash_pos > 0) {
		main_part = substr(v, 1, dash_pos - 1);
		pre_part = substr(v, dash_pos + 1);
	} else {
		main_part = v;
		pre_part = "";
	}
	split(main_part, m, ".");
	out["major"] = m[1] + 0;
	out["minor"] = m[2] + 0;
	out["patch"] = m[3] + 0;
	out["pre"] = pre_part;
	out["valid"] = (m[1] ~ /^[0-9]+$/ && m[2] ~ /^[0-9]+$/ && m[3] ~ /^[0-9]+$/);
}

function cmp_pre(pre1, pre2,    p1, p2, n1, n2, len, i, s1, s2, isnum1, isnum2) {
	if (pre1 == "" && pre2 == "") return 0;
	if (pre1 == "" && pre2 != "") return 1;
	if (pre1 != "" && pre2 == "") return -1;
	n1 = split(pre1, p1, ".");
	n2 = split(pre2, p2, ".");
	len = (n1 < n2 ? n1 : n2);
	for (i = 1; i <= len; i++) {
		s1 = p1[i];
		s2 = p2[i];
		isnum1 = (s1 ~ /^[0-9]+$/);
		isnum2 = (s2 ~ /^[0-9]+$/);
		if (isnum1 && isnum2) {
			if ((s1 + 0) != (s2 + 0)) return ((s1 + 0) > (s2 + 0) ? 1 : -1);
		} else if (isnum1 && !isnum2) {
			return -1;
		} else if (!isnum1 && isnum2) {
			return 1;
		} else {
			if (s1 != s2) return (s1 > s2 ? 1 : -1);
		}
	}
	if (n1 != n2) return (n1 > n2 ? 1 : -1);
	return 0;
}

function semver_cmp(v1, v2,    a1, a2) {
	parse_semver(v1, a1);
	parse_semver(v2, a2);
	if (!a1["valid"] || !a2["valid"]) return 0;
	if (a1["major"] != a2["major"]) return (a1["major"] > a2["major"] ? 1 : -1);
	if (a1["minor"] != a2["minor"]) return (a1["minor"] > a2["minor"] ? 1 : -1);
	if (a1["patch"] != a2["patch"]) return (a1["patch"] > a2["patch"] ? 1 : -1);
	return cmp_pre(a1["pre"], a2["pre"]);
}

function parse_releases(channel, target_ver, num_tokens, tokens,    tok, depth, in_release, in_assets, in_asset, \
	rel_tag, rel_draft, rel_prerelease, rel_html, asset_name, asset_url, \
	best_ver, best_tag, best_html, best_archive_url, best_checksum_url, best_bundle_url, \
	archive_name, checksum_name, bundle_name, key, val, i, ver_clean, eligible, current_assets) {

	best_ver = "";
	best_tag = "";
	best_html = "";
	best_archive_url = "";
	best_checksum_url = "";
	best_bundle_url = "";
	depth = 0;

	for (i = 1; i <= num_tokens; i++) {
		tok = tokens[i];
		if (tok == "{") {
			depth++;
			if (depth == 1) {
				in_release = 1;
				rel_tag = ""; rel_draft = 0; rel_prerelease = 0; rel_html = "";
				delete current_assets;
			} else if (depth == 2 && in_assets) {
				in_asset = 1;
				asset_name = ""; asset_url = "";
			}
		} else if (tok == "}") {
			if (depth == 2 && in_asset) {
				if (asset_name != "" && asset_url != "") {
					current_assets[asset_name] = asset_url;
				}
				in_asset = 0;
			} else if (depth == 1 && in_release) {
				ver_clean = rel_tag;
				gsub(/^v/, "", ver_clean);
				archive_name = "nbshell-" ver_clean ".tar.gz";
				checksum_name = archive_name ".sha256";
				bundle_name = archive_name ".sigstore.json";

				eligible = 0;
				if (!rel_draft) {
					if (target_ver != "") {
						if (ver_clean == target_ver) eligible = 1;
					} else if (channel == "stable") {
						if (!rel_prerelease && index(ver_clean, "-") == 0) eligible = 1;
					} else if (channel == "beta") {
						eligible = 1;
					}
				}

				if (eligible && (archive_name in current_assets) && (checksum_name in current_assets) && (bundle_name in current_assets)) {
					if (best_ver == "" || semver_cmp(ver_clean, best_ver) > 0) {
						best_ver = ver_clean;
						best_tag = rel_tag;
						best_html = rel_html;
						best_archive_url = current_assets[archive_name];
						best_checksum_url = current_assets[checksum_name];
						best_bundle_url = current_assets[bundle_name];
					}
				}
				in_release = 0;
			}
			depth--;
		} else if (tok == "[") {
			# Array start
		} else if (tok == "]") {
			if (in_assets && !in_asset) in_assets = 0;
		} else if (tok ~ /^".*"$/) {
			val = substr(tok, 2, length(tok) - 2);
			if (i < num_tokens && tokens[i+1] == ":") {
				key = val;
				i += 2;
				tok = tokens[i];
				if (tok ~ /^".*"$/) val = substr(tok, 2, length(tok) - 2);
				else val = tok;

				if (depth == 1) {
					if (key == "tag_name") rel_tag = val;
					else if (key == "html_url") rel_html = val;
					else if (key == "draft") rel_draft = (val == "true" || val == "1");
					else if (key == "prerelease") rel_prerelease = (val == "true" || val == "1");
					else if (key == "assets" && tok == "[") in_assets = 1;
				} else if (depth == 2 && in_asset) {
					if (key == "name") asset_name = val;
					else if (key == "browser_download_url") asset_url = val;
				}
			}
		}
	}

	if (best_ver == "") {
		print "ERROR=No eligible release found"
		return 1;
	}

	print "VERSION=" best_ver
	print "TAG=" best_tag
	print "HTML_URL=" best_html
	print "ARCHIVE_NAME=nbshell-" best_ver ".tar.gz"
	print "ARCHIVE_URL=" best_archive_url
	print "CHECKSUM_URL=" best_checksum_url
	print "BUNDLE_URL=" best_bundle_url
	return 0;
}

{
	json_str = json_str $0 "\n";
}
END {
	num = tokenize_json(json_str, tokens);
	exit parse_releases(CHANNEL, TARGET_VER, num, tokens);
}
' "$RELEASES_JSON")" || {
	err_msg="$(printf '%s\n' "$RELEASE_INFO" | grep '^ERROR=' | cut -d= -f2-)"
	die "${err_msg:-Failed to find an eligible release.}"
}

VERSION="$(printf '%s\n' "$RELEASE_INFO" | grep '^VERSION=' | cut -d= -f2-)"
TAG="$(printf '%s\n' "$RELEASE_INFO" | grep '^TAG=' | cut -d= -f2-)"
HTML_URL="$(printf '%s\n' "$RELEASE_INFO" | grep '^HTML_URL=' | cut -d= -f2-)"
ARCHIVE_NAME="$(printf '%s\n' "$RELEASE_INFO" | grep '^ARCHIVE_NAME=' | cut -d= -f2-)"
ARCHIVE_URL="$(printf '%s\n' "$RELEASE_INFO" | grep '^ARCHIVE_URL=' | cut -d= -f2-)"
CHECKSUM_URL="$(printf '%s\n' "$RELEASE_INFO" | grep '^CHECKSUM_URL=' | cut -d= -f2-)"
BUNDLE_URL="$(printf '%s\n' "$RELEASE_INFO" | grep '^BUNDLE_URL=' | cut -d= -f2-)"

[ -n "$VERSION" ] || die "Could not determine target version."

if [ "$ALLOW_INSECURE_ASSETS" != "1" ] && [[ ! "$API_URL" =~ ^/ ]] && [[ ! "$API_URL" =~ ^file:// ]]; then
	if [[ ! "$ARCHIVE_URL" =~ ^https:// ]] || [[ ! "$CHECKSUM_URL" =~ ^https:// ]] || [[ ! "$BUNDLE_URL" =~ ^https:// ]]; then
		die "Insecure asset download URL detected (HTTPS required)."
	fi
fi

printf 'Selected release: %s (%s)\n' "$TAG" "$CHANNEL"
if [ -n "$HTML_URL" ]; then
	printf 'Release notes: %s\n' "$HTML_URL"
fi

ARCHIVE_FILE="$TEMP_DIR/$ARCHIVE_NAME"
CHECKSUM_FILE="$TEMP_DIR/$ARCHIVE_NAME.sha256"
BUNDLE_FILE="$TEMP_DIR/$ARCHIVE_NAME.sigstore.json"

printf 'Downloading %s …\n' "$ARCHIVE_NAME"
download_file "$ARCHIVE_URL" "$ARCHIVE_FILE" 104857600

printf 'Downloading checksum …\n'
download_file "$CHECKSUM_URL" "$CHECKSUM_FILE" 4096

printf 'Downloading Sigstore bundle …\n'
download_file "$BUNDLE_URL" "$BUNDLE_FILE" 5242880

SIGNING_IDENTITY="https://github.com/$REPOSITORY/.github/workflows/release.yml@refs/tags/$TAG"
if ! "$COSIGN_BIN" verify-blob "$ARCHIVE_FILE" \
		--bundle "$BUNDLE_FILE" \
		--certificate-identity "$SIGNING_IDENTITY" \
		--certificate-oidc-issuer "https://token.actions.githubusercontent.com" >/dev/null; then
	die "Sigstore signature verification failed."
fi
green "Sigstore signature verified."

EXPECTED_CHECKSUM="$(awk '{print $1; exit}' "$CHECKSUM_FILE" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$EXPECTED_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
	die "Invalid SHA-256 checksum format in $CHECKSUM_FILE"
fi

ACTUAL_CHECKSUM="$(compute_sha256 "$ARCHIVE_FILE" | tr '[:upper:]' '[:lower:]')"
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
	printf 'Checksum verification failed!\n  Expected: %s\n  Actual:   %s\n' "$EXPECTED_CHECKSUM" "$ACTUAL_CHECKSUM" >&2
	die "Release archive checksum mismatch; aborting installation to prevent corruption."
fi

green "SHA-256 checksum verified."

EXTRACT_DIR="$TEMP_DIR/source"
mkdir -p "$EXTRACT_DIR"

while IFS= read -r member; do
	[ -n "$member" ] || continue
	if [[ "$member" == ".." ]] || [[ "$member" == /* ]] || [[ "$member" == *../* ]] || [[ "$member" == */../* ]] || [[ "$member" == */.. ]]; then
		die "Unsafe path detected in release archive: $member"
	fi
done < <(tar -tzf "$ARCHIVE_FILE")

# Release archives are source trees, so they need only regular files and
# directories. Reject links and special files before extraction; otherwise an
# archive controlled by a compromised release could redirect later members or
# create device/FIFO nodes. Also bound the expanded payload to avoid a small
# compressed asset exhausting the target filesystem.
if ! tar -tvzf "$ARCHIVE_FILE" | awk '
BEGIN { total = 0 }
{
	type = substr($1, 1, 1)
	if (type != "-" && type != "d") exit 2
	total += $3
	if (total > 536870912) exit 3
}
'; then
	die "Release archive contains links, special files, or more than 512 MiB of expanded data."
fi

tar -xzf "$ARCHIVE_FILE" -C "$EXTRACT_DIR"

roots=()
for entry in "$EXTRACT_DIR"/*; do
	[ -d "$entry" ] && roots+=("$entry")
done

if [ ${#roots[@]} -ne 1 ] || [ ! -f "${roots[0]}/setup.sh" ]; then
	die "Release archive does not contain a valid nbshell source tree."
fi

SOURCE_DIR="${roots[0]}"

head2 "Starting nbshell installer"
INSTALL_STATUS=0
"$SOURCE_DIR/setup.sh" "${FORWARD_ARGS[@]}" || INSTALL_STATUS=$?
exit "$INSTALL_STATUS"
