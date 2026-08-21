#!/usr/bin/env bash
set -euo pipefail

REPO_URL=https://github.com/nerdislb/omacut.git
REPO_DIR="${NBSHELL_OMACUT_DIR:-$HOME/projects/omacut}"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

install_files() {
	install -Dm755 "$REPO_DIR/build/omacut" "$BIN_DIR/omacut"
	install -Dm644 "$REPO_DIR/pkgbuild/omacut.desktop" "$DATA_HOME/applications/omacut.desktop"
	install -Dm644 "$REPO_DIR/pkgbuild/omacut.svg" "$DATA_HOME/icons/hicolor/scalable/apps/omacut.svg"
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
}

check_dependencies() {
	local missing=() command
	for command in git qmake6 make g++ ffmpeg ffprobe; do
		command -v "$command" >/dev/null 2>&1 || missing+=("$command")
	done
	if ((${#missing[@]})); then
		printf 'Missing build commands: %s\n' "${missing[*]}" >&2
		printf 'On Arch install: sudo pacman -S git base-devel ffmpeg qt6-base qt6-declarative qt6-multimedia\n' >&2
		exit 69
	fi
}

install_omacut() {
	check_dependencies
	if [[ -e $REPO_DIR && ! -d $REPO_DIR/.git ]]; then
		printf 'Refusing to replace non-Git path: %s\n' "$REPO_DIR" >&2
		exit 1
	fi
	if [[ ! -d $REPO_DIR/.git ]]; then
		mkdir -p "$(dirname "$REPO_DIR")"
		git clone "$REPO_URL" "$REPO_DIR"
	else
		git -C "$REPO_DIR" diff --quiet && git -C "$REPO_DIR" diff --cached --quiet || {
			printf 'Omacut has local changes; update was skipped.\n' >&2
			exit 1
		}
		git -C "$REPO_DIR" pull --ff-only
	fi
	"$REPO_DIR/bin/build"
	install_files
	printf 'Omacut installed at %s/omacut\n' "$BIN_DIR"
}

status() {
	if [[ -x $BIN_DIR/omacut ]]; then
		printf 'Omacut    installed (%s)\n' "$BIN_DIR/omacut"
	else
		printf 'Omacut    not installed\n'
	fi
	printf 'Source    %s\n' "$([[ -d $REPO_DIR/.git ]] && echo "$REPO_DIR" || echo 'not cloned')"
}

case "${1:-status}" in
install|update) install_omacut ;;
status) status ;;
remove)
	rm -f "$BIN_DIR/omacut" "$DATA_HOME/applications/omacut.desktop" "$DATA_HOME/icons/hicolor/scalable/apps/omacut.svg"
	printf 'Omacut application files removed. Source checkout kept at %s.\n' "$REPO_DIR"
	;;
*) printf 'Usage: nbshell video-trimmer status|install|update|remove\n' >&2; exit 2 ;;
esac
