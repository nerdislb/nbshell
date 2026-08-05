#!/usr/bin/env bash
#
# nbshell komplett einrichten: Pakete, Dateien, Dienste.
#
# `install.sh` legt nur die Dateien ab und MELDET, was fehlt -- das ist der
# richtige Weg, wenn man nicht weiss, wem der Rechner gehoert. Dieses Skript
# ist der andere Fall: es holt alles, was nbshell braucht, damit hinterher
# kein Baustein still bleibt und kein Knopf ins Leere greift.
#
#   setup.sh                 Pakete, Dateien, Dienste -- der ganze Weg
#   setup.sh --no-packages   nur die Dateien (dasselbe wie install.sh)
#   setup.sh --no-aur        den AUR-Helfer nicht bauen
#   setup.sh --yes           nichts fragen, alles ja
#
# Absichtlich NICHT als root aufzurufen: die Dateien gehoeren in $HOME, und ein
# `sudo ./setup.sh` legte sie in /root ab. Fuer pacman ruft das Skript sudo
# selbst auf, an einer einzigen Stelle.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_PACKAGES=1
WITH_AUR=1
ASSUME_YES=0

while [ $# -gt 0 ]; do
	case "$1" in
	--no-packages) WITH_PACKAGES=0 && shift ;;
	--no-aur) WITH_AUR=0 && shift ;;
	-y | --yes) ASSUME_YES=1 && shift ;;
	-h | --help)
		cat <<'USAGE'
setup.sh -- nbshell komplett einrichten: Pakete, Dateien, Dienste.

  setup.sh                 Pakete, Dateien, Dienste -- der ganze Weg
  setup.sh --no-packages   nur die Dateien (dasselbe wie install.sh)
  setup.sh --no-aur        den AUR-Helfer nicht bauen
  setup.sh --yes           nichts fragen, alles ja
USAGE
		exit 0
		;;
	*)
		printf 'Unbekannt: %s (--help zeigt die Aufrufe)\n' "$1" >&2
		exit 2
		;;
	esac
done

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
	local q="$1" def="${2:-j}" ans=""
	[ "$ASSUME_YES" = "1" ] && return 0
	if [ "$def" = "j" ]; then
		read -r -p "$q [J/n] " ans || return 1
		[ -z "$ans" ] || [[ $ans =~ ^[jJyY] ]]
	else
		read -r -p "$q [j/N] " ans || return 1
		[[ $ans =~ ^[jJyY] ]]
	fi
}

[ "$(id -u)" != "0" ] || die "Bitte NICHT als root: nbshell wird in dein \$HOME installiert."

# ── Die Pakete ───────────────────────────────────────────────────────────
#
# Nach Zweck sortiert, damit man sieht, wofuer man was bekommt. Alles davon
# liegt in den offiziellen Repos -- auch quickshell. Nur der AUR-Helfer weiter
# unten ist ein Sonderfall.

# Ohne das laeuft nichts.
PKG_BASIS=(quickshell niri ttf-inconsolata-nerd python jq git curl)

# Woher die Bausteine ihre Zahlen haben. Quickshell spricht mit diesen
# Diensten ueber DBus, `pactl` braucht die Aufnahme fuer den Ton.
PKG_SYSTEM=(networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber libpulse upower)

# Einzelne Bausteine und Knoepfe.
#   wl-clipboard   Ablage (`wl-paste --watch`, `wl-copy`)
#   hyprlock       Sperren im Power-Menue
#   tuned          Energieprofile beim Akku
#   libnotify      `notify-send` aus den Skripten
#   xdg-utils      `xdg-open` nach einer Aufnahme
#   pacman-contrib `checkupdates` -- ohne das rechnet der Updater langsamer
#   fakeroot       der Rueckweg des Updaters, wenn checkupdates fehlt
PKG_BAUSTEINE=(wl-clipboard hyprlock tuned libnotify xdg-utils pacman-contrib fakeroot)

# Kalender: khal rechnet die Wiederholungen, vdirsyncer holt sie.
PKG_KALENDER=(khal vdirsyncer)

# Aufnehmen, zuschneiden, Text erkennen.
PKG_AUFNAHME=(wf-recorder slurp satty swappy tesseract tesseract-data-deu tesseract-data-eng)

ALLE=("${PKG_BASIS[@]}" "${PKG_SYSTEM[@]}" "${PKG_BAUSTEINE[@]}" "${PKG_KALENDER[@]}" "${PKG_AUFNAHME[@]}")

if [ $WITH_PACKAGES -eq 1 ]; then
	command -v pacman >/dev/null || die "Kein pacman gefunden. Dieses Skript richtet sich an Arch; auf anderen Systemen: --no-packages und die Liste im Kopf von Hand nachbauen."

	head2 "Pakete"

	fehlend=()
	for p in "${ALLE[@]}"; do
		pacman -Qq "$p" >/dev/null 2>&1 || fehlend+=("$p")
	done

	if [ ${#fehlend[@]} -eq 0 ]; then
		green "Alle ${#ALLE[@]} Pakete sind schon da."
	else
		printf 'Es fehlen %d von %d:\n\n' "${#fehlend[@]}" "${#ALLE[@]}"
		printf '  %s\n' "${fehlend[*]}"
		printf '\n'
		if ask "Mit pacman installieren?"; then
			# --needed: schon Vorhandenes wird nicht neu gebaut.
			#
			# Bricht pacman ab (Abbruch an seiner eigenen Frage, kein Netz,
			# ein Konflikt), darf das NICHT das ganze Skript beenden: die
			# Dateien weiter unten will man dann trotzdem haben.
			if sudo pacman -S --needed "${fehlend[@]}"; then
				green "Pakete installiert."
			else
				warn "pacman ist ausgestiegen -- die Dateien werden trotzdem eingerichtet."
			fi
		else
			warn "Uebersprungen -- ohne sie bleiben Bausteine still."
		fi
	fi

	# ── AUR-Helfer ───────────────────────────────────────────────────
	#
	# Nur fuer EINE Sache: der Updater zaehlt damit auch AUR-Pakete. Er
	# laeuft ohne, dann fehlen in der Zahl eben die AUR-Updates.
	#
	# Das ist der einzige Schritt, der Fremdcode uebersetzt -- deshalb wird
	# gefragt, auch mit --yes nicht uebergangen, und die Adresse steht dabei.
	if [ $WITH_AUR -eq 1 ] && ! command -v paru >/dev/null 2>&1 && ! command -v yay >/dev/null 2>&1; then
		head2 "AUR-Helfer"
		echo "Fuer die AUR-Updates im Updater fehlt paru oder yay."
		echo "Bauen von https://aur.archlinux.org/paru-bin.git (dein sudo, dein makepkg)."
		echo
		# Hier wird bewusst IMMER gefragt, auch mit --yes: das ist der einzige
		# Schritt, der Code von ausserhalb der Repos uebersetzt und ausfuehrt.
		# Das soll niemand aus Versehen anstossen.
		aur_ans=""
		read -r -p "paru-bin jetzt bauen? [j/N] " aur_ans || aur_ans=""
		if [[ $aur_ans =~ ^[jJyY] ]]; then
			pacman -Qq base-devel >/dev/null 2>&1 || sudo pacman -S --needed base-devel
			tmp="$(mktemp -d)"
			# Nicht im Trap: das Verzeichnis soll stehen bleiben, wenn der
			# Bau schiefgeht -- sonst ist auch das Protokoll weg.
			if git clone --depth 1 --quiet https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" &&
				(cd "$tmp/paru-bin" && makepkg -si --noconfirm); then
				rm -rf "$tmp"
				green "paru installiert."
			else
				warn "Bau fehlgeschlagen. Das Verzeichnis bleibt zum Nachsehen: $tmp/paru-bin"
			fi
		else
			warn "Ohne AUR-Helfer zaehlt der Updater nur die Repo-Updates."
		fi
	fi

	# ── Dienste ──────────────────────────────────────────────────────
	#
	# Diese werden NICHT ungefragt eingeschaltet. Wer sein Netz mit
	# systemd-networkd oder iwd verwaltet, steht nach einem beherzten
	# `enable NetworkManager` ohne Verbindung da -- und das waere ein
	# teurer Preis fuer eine Zahl in der Leiste.
	head2 "Dienste"

	dienst() {
		local unit="$1" zweck="$2" vorgabe="${3:-j}"

		# Gibt es die Unit gar nicht, wurde ihr Paket nicht installiert.
		# Ein `enable` darauf scheitert -- und unter `set -e` risse es das
		# ganze Skript mit, kurz vor den Dateien.
		if ! systemctl list-unit-files "$unit.service" >/dev/null 2>&1 ||
			[ -z "$(systemctl list-unit-files --no-legend "$unit.service" 2>/dev/null)" ]; then
			printf '  %-16s nicht installiert (%s)\n' "$unit" "$zweck"
			return 0
		fi
		if systemctl is-active --quiet "$unit" 2>/dev/null || systemctl is-enabled --quiet "$unit" 2>/dev/null; then
			printf '  %-16s laeuft (%s)\n' "$unit" "$zweck"
			return 0
		fi
		printf '  %-16s aus (%s)\n' "$unit" "$zweck"
		if ask "    $unit einschalten?" "$vorgabe"; then
			sudo systemctl enable --now "$unit" || warn "    ging nicht -- von Hand: sudo systemctl enable --now $unit"
		fi
		return 0
	}

	# NetworkManager mit Vorgabe "nein" -- siehe oben.
	dienst NetworkManager "Netz-Baustein" n
	dienst bluetooth "Bluetooth-Baustein"
	dienst tuned "Energieprofile"

	# Die beiden laufen je Sitzung und sind ueber Sockets aktiviert; sie
	# einzuschalten ist selten noetig, ihr Fehlen aber einen Hinweis wert.
	for u in pipewire wireplumber; do
		if systemctl --user is-active --quiet "$u" 2>/dev/null; then
			printf '  %-16s laeuft (Ton)\n' "$u"
		else
			warn "  $u laeuft nicht -- ohne ihn bleibt der Lautstaerkebaustein leer."
		fi
	done
fi

# ── Dateien ──────────────────────────────────────────────────────────────
#
# Den Rest kann install.sh schon: Shell, Themes, Config, Plugins, Unit,
# Tastenkuerzel, der Befehl. Zweimal dasselbe zu schreiben hiesse, es zweimal
# zu pflegen.
head2 "Dateien"
NBSHELL_FROM_SETUP=1 "$SRC/install.sh"

if [ $WITH_PACKAGES -eq 1 ]; then
	# Zum Schluss die Gegenprobe: was von den Befehlen, die die Skripte
	# aufrufen, ist jetzt WIRKLICH da? Ein installiertes Paket ist noch kein
	# Befehl im PATH.
	head2 "Gegenprobe"
	fehlt=0
	for c in qs niri python3 jq git curl wl-copy wl-paste notify-send xdg-open \
		hyprlock tuned-adm khal vdirsyncer wf-recorder slurp satty swappy \
		tesseract pactl checkupdates fakeroot; do
		command -v "$c" >/dev/null 2>&1 || {
			warn "  $c fehlt weiterhin"
			fehlt=1
		}
	done
	[ $fehlt -eq 0 ] && green "Alle Befehle da."
fi

cat <<'EOF'

Weiter geht es mit:
  nbshell start -d       im Hintergrund starten
  nbshell switch on      dauerhaft einrichten (Autostart, Tastenkuerzel,
                         Benachrichtigungen, Fensterrahmen, Terminalfarben)

Der Kalender braucht noch seine Konten -- siehe README, Abschnitt "Kalender".
EOF
