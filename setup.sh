#!/usr/bin/env bash
#
# nbshell komplett einrichten: Packages, Files, Services.
#
# `install.sh` legt nur die Files ab und MELDET, was fehlt -- das ist der
# richtige Weg, wenn man nicht weiss, wem der Rechner gehoert. Dieses Skript
# ist der andere Fall: es holt alles, was nbshell braucht, damit hinterher
# kein Baustein still bleibt und kein Knopf ins Leere greift.
#
#   setup.sh                  der ganze Weg
#   setup.sh --no-packages    nur die Files (dasselbe wie install.sh)
#   setup.sh --full           auch alle optionalen Desktop-Werkzeuge
#   setup.sh --with-legacy-dotfiles  alte DMS-Dotfiles zusaetzlich uebernehmen
#   setup.sh --no-aur         den AUR helper nicht bauen
#   setup.sh --with-hardware  auch die Hardware-Packages der Paketliste

#   setup.sh --with-greeter   Orbital auch bei einer bestehenden Installation einrichten
#   setup.sh --no-greeter     Greeter bei einer Neuinstallation nicht einrichten
#   setup.sh --yes            nichts fragen, alles ja
#
# Absichtlich NICHT als root aufzurufen: die Files gehoeren in $HOME, und ein
# `sudo ./setup.sh` legte sie in /root ab. Fuer pacman ruft das Skript sudo
# selbst auf, an einer einzigen Stelle.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_PACKAGES=1
WITH_DOTFILES=0
WITH_AUR=1
WITH_HARDWARE=0
WITH_OPTIONAL=0
ASSUME_YES=0
GREETER_MODE=auto

# Capture this before install.sh creates the normal user configuration. Automatic
# greeter activation is a fresh-setup policy only; updates must never replace an
# existing display-manager frontend without an explicit --with-greeter request.
NBSHELL_USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/config.json"
NBSHELL_RUNTIME_VERSION="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nbshell/VERSION"
NBSHELL_COMMAND="${XDG_BIN_HOME:-$HOME/.local/bin}/nbshell"
FRESH_NBSHELL_INSTALL=1
if [ -e "$NBSHELL_USER_CONFIG" ] || [ -e "$NBSHELL_RUNTIME_VERSION" ] || [ -e "$NBSHELL_COMMAND" ]; then
	FRESH_NBSHELL_INSTALL=0
fi

# Optionaler Migrationspfad fuer den bisherigen Rechner. Eine normale
# Neuinstallation braucht dieses Repo nicht und installiert insbesondere DMS
# nicht mehr.
DOTFILES_REPO="${NBSHELL_LEGACY_DOTFILES_REPO:-}"
DOTFILES_DIR="$HOME/dotfiles"

while [ $# -gt 0 ]; do
	case "$1" in
	--no-packages) WITH_PACKAGES=0 && shift ;;
	--with-legacy-dotfiles | --with-dotfiles) WITH_DOTFILES=1 && shift ;;
	--no-dotfiles) WITH_DOTFILES=0 && shift ;;
	--no-aur) WITH_AUR=0 && shift ;;
	--with-hardware) WITH_HARDWARE=1 && shift ;;

	--with-greeter)
		[ "$GREETER_MODE" != "off" ] || { printf '%s\n' "--with-greeter and --no-greeter cannot be combined." >&2; exit 2; }
		GREETER_MODE=on && shift
		;;
	--no-greeter)
		[ "$GREETER_MODE" != "on" ] || { printf '%s\n' "--with-greeter and --no-greeter cannot be combined." >&2; exit 2; }
		GREETER_MODE=off && shift
		;;
	--full) WITH_OPTIONAL=1 && shift ;;
	-y | --yes) ASSUME_YES=1 && shift ;;
	-h | --help)
		cat <<'USAGE'
setup.sh -- install nbshell packages, files, and services.

  setup.sh                  install Umbriel and nbshell
  setup.sh --no-packages    install files only (same as install.sh)
  setup.sh --full           install all optional desktop tools
  setup.sh --with-legacy-dotfiles
                            optionally migrate old DMS dotfiles
  setup.sh --no-aur         do not offer to install an AUR helper
  setup.sh --with-hardware  include hardware-specific legacy packages

  setup.sh --with-greeter   install Orbital even on an existing nbshell system
  setup.sh --no-greeter     keep the current display-manager frontend
  setup.sh --yes            accept normal package and service prompts
USAGE
		exit 0
		;;
	*)
		printf 'Unknown option: %s (see --help)\n' "$1" >&2
		exit 2
		;;
	esac
done

if [ "$WITH_PACKAGES" = "0" ] && [ "$GREETER_MODE" = "on" ]; then
	printf '%s\n' "--with-greeter cannot be combined with --no-packages." >&2
	exit 2
fi

WANT_GREETER_SETUP=0
if [ "$WITH_PACKAGES" = "1" ] && { [ "$GREETER_MODE" = "on" ] || { [ "$GREETER_MODE" = "auto" ] && [ "$FRESH_NBSHELL_INSTALL" = "1" ]; }; }; then
	WANT_GREETER_SETUP=1
fi

green() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() {
	printf '\033[31m%s\033[0m\n' "$*" >&2
	exit 1
}

# Wird nur in einem `if` benutzt -- dort setzt `set -e` aus, der abschliessende
# Test kann das Skript also nicht stillschweigend beenden.
ask() {
	local q="$1" def="${2:-y}" ans=""
	[ "$ASSUME_YES" = "1" ] && return 0
	if [ "$def" = "j" ] || [ "$def" = "y" ]; then
		read -r -p "$q [Y/n] " ans || return 1
		[ -z "$ans" ] || [[ $ans =~ ^[jJyY] ]]
	else
		read -r -p "$q [y/N] " ans || return 1
		[[ $ans =~ ^[jJyY] ]]
	fi
}

[ "$(id -u)" != "0" ] || die "Do not run this script as root. nbshell is installed in your home directory."

# ── Die Packages ───────────────────────────────────────────────────────────
#
# Nach Zweck sortiert, damit man sieht, wofuer man was bekommt. Alles davon
# liegt in den offiziellen Repos -- auch quickshell. Nur der AUR helper weiter
# unten ist ein Sonderfall.

# Ohne das running nichts.
PKG_BASIS=(quickshell ttf-jetbrains-mono-nerd python python-dbus python-gobject jq git curl patch cosign)

# Woher die Bausteine ihre Zahlen haben. Quickshell spricht mit diesen
# Servicesn ueber DBus, `pactl` braucht die Aufnahme fuer den audio.
PKG_SYSTEM=(networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber libpulse upower)

# Einzelne Bausteine und Knoepfe.
#   wl-clipboard   Ablage (`wl-paste --watch`, `wl-copy`)
#   hyprlock       independent fallback if the native Quickshell locker cannot start
#   tuned          power profiles beim Akku
#   libnotify      `notify-send` aus den Skripten
#   xdg-utils      `xdg-open` nach einer Aufnahme
#   pacman-contrib `checkupdates` -- ohne das rechnet der Updater langsamer
#   fakeroot       der Rueckweg des Updaters, wenn checkupdates fehlt
#   headsetcontrol Akkustand im Headset-Plugin (USB-HID++, Logitech & co.)
#   hyprpolkitagent das Fenster, das nach dem Passwort fragt, wenn ein Programm
#                  Rechte will. polkitd selbst fragt NIEMANDEN -- ohne einen
#                  Agenten in der Sitzung scheitert jede Anfrage still. Ein
#                  A minimal compositor session does not provide one.
#   qrencode       WLAN als QR-Code im Control Center
#   speedtest-cli  Durchsatz messen, ebenda
#   imagemagick    Wallpaper-Streifen fuer transparenten Bar-Kontrast abtasten
#   bubblewrap     Dateisystem-/Netzwerkgrenze fuer Hermes-Jobs und Team-Checks
PKG_BAUSTEINE=(wl-clipboard hyprlock tuned libnotify xdg-utils pacman-contrib fakeroot headsetcontrol hyprpolkitagent qrencode speedtest-cli imagemagick sqlite libsecret bubblewrap)

# Kalender: khal rechnet die Wiederholungen, vdirsyncer holt sie.
PKG_KALENDER=(khal vdirsyncer)

# Abgleich der Aufgabenliste mit dem Telefon. Syncthing bewegt nur die Datei;
# zusammengefuehrt wird sie in nbshell selbst (siehe README, "Aufgaben").
# Ohne Syncthing funktioniert die Liste trotzdem -- dann eben nur hier.
PKG_ABGLEICH=(syncthing)

# Recording, trimming, and text recognition.
PKG_AUFNAHME=(grim wf-recorder slurp satty swappy tesseract tesseract-data-deu tesseract-data-eng ffmpeg qt6-base qt6-declarative qt6-multimedia)

PKG_CORE=(wl-clipboard libnotify xdg-utils hyprpolkitagent)
if [ $WITH_OPTIONAL -eq 1 ]; then
	ALLE=("${PKG_BASIS[@]}" "${PKG_SYSTEM[@]}" "${PKG_BAUSTEINE[@]}" "${PKG_KALENDER[@]}" "${PKG_ABGLEICH[@]}" "${PKG_AUFNAHME[@]}")
else
	ALLE=("${PKG_BASIS[@]}" "${PKG_SYSTEM[@]}" "${PKG_CORE[@]}")
fi
[ "$WANT_GREETER_SETUP" = "0" ] || ALLE+=(greetd imagemagick)

if [ $WITH_PACKAGES -eq 1 ]; then
	command -v pacman >/dev/null || die "pacman was not found. This installer targets Arch Linux. On other systems, use --no-packages and install the listed dependencies manually."

	head2 "Packages"

	fehlend=()
	for p in "${ALLE[@]}"; do
		pacman -Qq "$p" >/dev/null 2>&1 || fehlend+=("$p")
	done

	if [ ${#fehlend[@]} -eq 0 ]; then
		green "All ${#ALLE[@]} packages are already installed."
	else
		printf 'Missing %d of %d:\n\n' "${#fehlend[@]}" "${#ALLE[@]}"
		printf '  %s\n' "${fehlend[*]}"
		printf '\n'
		if ask "Install with pacman?"; then
			# --needed: schon Vorhandenes wird nicht neu gebaut.
			#
			# Bricht pacman ab (Abbruch an seiner eigenen Frage, kein Netz,
			# ein Konflikt), darf das NICHT das ganze Skript beenden: die
			# Files weiter unten will man dann trotzdem haben.
			if sudo pacman -S --needed "${fehlend[@]}"; then
				green "Packages installed."
			else
				warn "pacman failed -- file installation will continue."
			fi
		else
			warn "Skipped -- related modules will remain unavailable."
		fi
	fi

	# ── AUR helper ───────────────────────────────────────────────────
	#
	# Nur fuer EINE Sache: der Updater zaehlt damit auch AUR-Packages. Er
	# running ohne, dann fehlen in der Zahl eben die AUR-Updates.
	#
	# Das ist der einzige Schritt, der Fremdcode uebersetzt -- deshalb wird
	# gefragt, auch mit --yes nicht uebergangen, und die Adresse steht dabei.
	if [ $WITH_OPTIONAL -eq 1 ] && [ $WITH_AUR -eq 1 ] && ! command -v paru >/dev/null 2>&1 && ! command -v yay >/dev/null 2>&1; then
		head2 "AUR helper"
		echo "paru or yay is required to include AUR updates."
		echo "Build from https://aur.archlinux.org/paru-bin.git (uses your sudo and makepkg)."
		echo
		# Hier wird bewusst IMMER gefragt, auch mit --yes: das ist der einzige
		# Schritt, der Code of ausserhalb der Repos uebersetzt und ausfuehrt.
		# Das soll niemand aus Versehen anstossen.
		aur_ans=""
		read -r -p "Build paru-bin now? [y/N] " aur_ans || aur_ans=""
		if [[ $aur_ans =~ ^[jJyY] ]]; then
			pacman -Qq base-devel >/dev/null 2>&1 || sudo pacman -S --needed base-devel
			tmp="$(mktemp -d)"
			# Nicht im Trap: das Verzeichnis soll stehen bleiben, wenn der
			# Bau schiefgeht -- sonst ist auch das Protokoll weg.
			if git clone --depth 1 --quiet https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" &&
				(cd "$tmp/paru-bin" && makepkg -si --noconfirm); then
				rm -rf "$tmp"
				green "paru installed."
			else
				warn "Build failed. The directory was kept for inspection: $tmp/paru-bin"
			fi
		else
			warn "Without an AUR helper, the updater only counts repository updates."
		fi
	fi

	# ── Services ──────────────────────────────────────────────────────
	#
	# Diese werden NICHT ungefragt eingeschaltet. Wer sein Netz mit
	# systemd-networkd oder iwd verwaltet, steht nach einem beherzten
	# `enable NetworkManager` ohne Verbindung da -- und das waere ein
	# teurer Preis fuer eine Zahl in der Leiste.
	head2 "Services"

	dienst() {
		local unit="$1" zweck="$2" vorgabe="${3:-j}"

		# Gibt es die Unit gar nicht, wurde ihr Paket not installed.
		# Ein `enable` darauf scheitert -- und unter `set -e` risse es das
		# ganze Skript mit, kurz vor den Files.
		if ! systemctl list-unit-files "$unit.service" >/dev/null 2>&1 ||
			[ -z "$(systemctl list-unit-files --no-legend "$unit.service" 2>/dev/null)" ]; then
			printf '  %-16s not installed (%s)\n' "$unit" "$zweck"
			return 0
		fi
		if systemctl is-active --quiet "$unit" 2>/dev/null || systemctl is-enabled --quiet "$unit" 2>/dev/null; then
			printf '  %-16s running (%s)\n' "$unit" "$zweck"
			return 0
		fi
		printf '  %-16s off (%s)\n' "$unit" "$zweck"
		if ask "    $unit enable?" "$vorgabe"; then
			sudo systemctl enable --now "$unit" || warn "    failed -- run manually: sudo systemctl enable --now $unit"
		fi
		return 0
	}

	# NetworkManager mit Vorgabe "nein" -- siehe oben.
	dienst NetworkManager "network module" n
	dienst bluetooth "Bluetooth module"
	dienst tuned "power profiles"

	# Syncthing ist der einzige BENUTZERdienst hier: die Files, die es
	# bewegt, gehoeren dem Benutzer, und es haelt seine Einstellungen unter
	# ~/.local/state. Als Systemdienst muesste es sich beides erst nehmen.
	# Es laesst sich getrost einschalten, bevor ein Ordner eingerichtet ist
	# -- ohne Ordner und ohne gekoppeltes Geraet tut es nichts als eine
	# Oberflaeche auf 127.0.0.1:8384 anzubieten.
	if [ -n "$(systemctl --user list-unit-files --no-legend syncthing.service 2>/dev/null)" ]; then
		if systemctl --user is-enabled --quiet syncthing.service 2>/dev/null; then
			printf '  %-16s running (task sync)\n' "syncthing"
		else
			printf '  %-16s off (sync tasks with the phone)\n' "syncthing"
			if ask "    syncthing enable?" j; then
				systemctl --user enable --now syncthing.service ||
					warn "    failed -- run manually: systemctl --user enable --now syncthing.service"
			fi
		fi
	else
		printf '  %-16s not installed (task sync)\n' "syncthing"
	fi

	# Die beiden laufen je Sitzung und sind ueber Sockets aktiviert; sie
	# einzuschalten ist selten noetig, ihr Fehlen aber einen Hinweis wert.
	for u in pipewire wireplumber; do
		if systemctl --user is-active --quiet "$u" 2>/dev/null; then
			printf '  %-16s running (audio)\n' "$u"
		else
			warn "  $u is not running -- the volume module needs it."
		fi
	done
fi

# ── Dotfiles ─────────────────────────────────────────────────────────────
#
# Nur fuer die bewusste Migration einer vorhandenen alten Installation. Der
# Standardweg bleibt vollstaendig unabhaengig of diesem DMS-Dotfiles-Repo.
if [ $WITH_DOTFILES -eq 1 ]; then
	head2 "Dotfiles"
	[ -n "$DOTFILES_REPO" ] || die "Set NBSHELL_LEGACY_DOTFILES_REPO before using legacy migration."

	if [ -d "$DOTFILES_DIR/.git" ]; then
		printf '  %s exists -- fetching the latest revision.\n' "${DOTFILES_DIR/#$HOME/\~}"
		git -C "$DOTFILES_DIR" pull --ff-only --quiet 2>/dev/null ||
			warn "  git pull failed (local changes?) -- using the existing checkout."
	elif [ -e "$DOTFILES_DIR" ]; then
		die "$DOTFILES_DIR exists but is not a Git repository. Move or remove it first."
	else
		printf '  cloning %s\n' "$DOTFILES_REPO"
		git clone --quiet "$DOTFILES_REPO" "$DOTFILES_DIR" ||
			die "Clone failed. Check GitHub authentication with: ssh -T git@github.com"
	fi

	# ── Die Paketliste des anderen Rechners ──────────────────────────
	#
	# Sie ist ein `pacman -Qqe` und enthaelt damit auch Kernel, Firmware
	# und Grafiktreiber. Die gehoeren NICHT blind auf eine andere Maschine:
	# `nvidia-open` auf einem AMD-Rechner ist kein Fehler, der auffaellt --
	# er liegt einfach da und wird bei jedem Update mitgebaut. Deshalb
	# werden sie herausgesucht und nur mit --with-hardware mitgenommen.
	HW_MUSTER='^(nvidia|lib32-nvidia|libva-nvidia|amd-ucode|intel-ucode|linux|lib32-mesa|mesa|vulkan|lib32-vulkan|xf86-video)'

	if [ $WITH_PACKAGES -eq 1 ] && [ -f "$DOTFILES_DIR/pkglist.txt" ]; then
		hw=()
		rest=()
		while read -r p; do
			[ -n "$p" ] || continue
			case "$p" in \#*) continue ;; esac
			pacman -Qq "$p" >/dev/null 2>&1 && continue
			if [[ $p =~ $HW_MUSTER ]]; then
				hw+=("$p")
			else
				rest+=("$p")
			fi
		done <"$DOTFILES_DIR/pkglist.txt"

		if [ ${#hw[@]} -gt 0 ]; then
			printf '\n  Hardware-specific packages skipped by default (%d):\n    %s\n' "${#hw[@]}" "${hw[*]}"
			[ $WITH_HARDWARE -eq 1 ] && rest+=("${hw[@]}") && echo "    --with-hardware: included."
		fi

		if [ ${#rest[@]} -eq 0 ]; then
			green "  All packages from pkglist.txt are installed."
		else
			printf '\n  Missing %d packages from pkglist.txt:\n    %s\n\n' "${#rest[@]}" "${rest[*]}"
			if ask "  Install them?"; then
				sudo pacman -S --needed "${rest[@]}" || warn "  pacman failed."
			fi
		fi
	fi

	# AUR: nur wenn ein Helfer da ist. Ohne einen ginge es nur mit makepkg
	# je Paket, und das ist kein Schritt fuer ein Einrichtungsskript.
	if [ $WITH_PACKAGES -eq 1 ] && [ -f "$DOTFILES_DIR/pkglist-aur.txt" ]; then
		helper="$(command -v paru || command -v yay || true)"
		if [ -n "$helper" ]; then
			aur=()
			while read -r p; do
				[ -n "$p" ] || continue
				case "$p" in \#*) continue ;; esac
				pacman -Qq "$p" >/dev/null 2>&1 || aur+=("$p")
			done <"$DOTFILES_DIR/pkglist-aur.txt"
			if [ ${#aur[@]} -eq 0 ]; then
				green "  All packages from pkglist-aur.txt are installed."
			else
				printf '\n  Missing %d packages from pkglist-aur.txt:\n    %s\n\n' "${#aur[@]}" "${aur[*]}"
				if ask "  Build with $(basename "$helper")?"; then
					"$helper" -S --needed "${aur[@]}" || warn "  $(basename "$helper") failed."
				fi
			fi
		else
			warn "  No paru/yay -- skipping the AUR package list."
		fi
	fi

	# ── Die Einstellungen selbst ─────────────────────────────────────
	if [ -x "$DOTFILES_DIR/bin/restore.sh" ]; then
		echo
		warn "  restore.sh REPLACES ~/.local/bin. Files not stored in the dotfiles"
		warn "  repository will be removed. It creates .bak copies first."
		echo
		if ask "  Run restore.sh now?"; then
			# Es fragt selbst noch einmal nach. Mit --yes soll nichts
			# stehen bleiben, also wird die Antwort hineingereicht.
			if [ "$ASSUME_YES" = "1" ]; then
				printf 'y\n' | "$DOTFILES_DIR/bin/restore.sh" || warn "  restore.sh failed."
			else
				"$DOTFILES_DIR/bin/restore.sh" || warn "  restore.sh failed."
			fi
		fi
	else
		warn "  $DOTFILES_DIR/bin/restore.sh is missing -- keeping current settings."
	fi
fi

# Umbriel is the only supported compositor. Build and test its pinned stack
# before deploying shell files that depend on it.
if [ "$WITH_PACKAGES" = "1" ]; then
	head2 "Umbriel compositor"
	"$SRC/setup-umbriel.sh" --skip-shell-install
else
	warn "Umbriel build skipped by --no-packages; an existing Umbriel installation is required."
fi

# ── Files ──────────────────────────────────────────────────────────────
#
# Den Rest kann install.sh schon: Shell, Themes, Config, Plugins, Unit,
# Tastenkuerzel, der Befehl. Zweimal dasselbe zu schreiben hiesse, es zweimal
# zu pflegen.
#
# NACH den Dotfiles, und das ist keine Geschmacksfrage: restore.sh ersetzt
# ~/.local/bin als Ganzes, also auch den Befehl `nbshell` darin. Andersherum
# gewaenne die Kopie aus dem Dotfiles-Repo -- und die ist nur so neu wie das
# letzte save.sh.
head2 "Files"
NBSHELL_FROM_SETUP=1 "$SRC/install.sh"

# Quickshell's native locker uses a deliberately separate, password-first PAM
# service. Files-only setup stages the payload but never changes /etc.
if [ "$WITH_PACKAGES" = "1" ]; then
	LOCKER_SETUP="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/setup-locker.sh"
	NBSHELL_LOCK_PAM_SOURCE="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/locker/nbshell-lock.pam" \
		"$LOCKER_SETUP"
fi


# A complete fresh setup uses the native Orbital login screen by default. The
# installed payload is deliberately exercised here instead of the checkout copy.
# Existing installations are left untouched unless --with-greeter was explicit;
# agreety provides the independent text recovery path.
if [ "$WANT_GREETER_SETUP" = "1" ]; then
	head2 "Login screen"
	greeter_ready=1
	for command in umbriel start-umbriel quickshell agreety; do
		command -v "$command" >/dev/null 2>&1 || greeter_ready=0
	done
	if [ "$greeter_ready" = "0" ] && [ "$GREETER_MODE" = "auto" ]; then
		warn "Orbital skipped because its dependencies were not installed. Run nbshell greeter install later."
	elif [ "$GREETER_MODE" = "on" ] || ask "Install the Orbital login screen?" y; then
		GREETER_SETUP="${XDG_DATA_HOME:-$HOME/.local/share}/nbshell/setup-greeter.sh"
		[ -x "$GREETER_SETUP" ] || die "The installed greeter setup payload is missing: $GREETER_SETUP"
		"$GREETER_SETUP" install
	else
		warn "Orbital skipped. Run nbshell greeter install later."
	fi
fi

if [ $WITH_PACKAGES -eq 1 ]; then
	# Zum Schluss die Final check: was of den Befehlen, die die Skripte
	# aufrufen, ist jetzt WIRKLICH da? Ein installiertes Paket ist noch kein
	# Befehl im PATH.
	head2 "Final check"
	fehlt=0
	check_commands=(qs umbriel start-umbriel python3 jq git curl wl-copy wl-paste notify-send xdg-open pactl)
	if [ $WITH_OPTIONAL -eq 1 ]; then
		check_commands+=(hyprlock tuned-adm khal vdirsyncer grim wf-recorder slurp satty
			swappy tesseract checkupdates fakeroot)
	fi
	for c in "${check_commands[@]}"; do
		command -v "$c" >/dev/null 2>&1 || {
			warn "  $c is still missing"
			fehlt=1
		}
	done
	[ $fehlt -eq 0 ] && green "All required commands are available."
fi

echo
echo "Next steps:"
echo "  Log out and choose Umbriel."
echo "  nbshell switch on      refresh autostart and the Umbriel integration"
echo
echo "Calendar accounts require separate khal/vdirsyncer configuration; see README.md."
