# nbshell

nbshell ist eine von [Omarchy](https://omarchy.org) inspirierte Desktop-Shell
fuer [niri](https://github.com/YaLTeR/niri). Sie basiert auf
[Quickshell](https://quickshell.org), ist eigenstaendig und benoetigt keine
vollstaendige Desktop-Umgebung.

Das Projekt ist mit Unterstuetzung von KI entstanden und wird weiterhin aktiv
gemeinsam mit KI-Werkzeugen entwickelt. Entscheidungen, Tests und die Richtung
des Projekts bleiben dabei menschlich gesteuert.

> nbshell ist ein junges, persoenliches Projekt. Es funktioniert im Alltag,
> APIs und Konfiguration koennen sich aber noch aendern.

## Was ist enthalten?

- Insel, Pille oder durchgehende Bar mit frei anordenbaren Modulen
- Omarchy-inspirierte Menues, Dashboard, Themes und Wallpaper
- Launcher, Zwischenablage, Benachrichtigungen und System-Tray
- Audio, Medien, Bluetooth, WLAN, Akkus und Energieprofile
- Kalender, Aufgaben, Gewohnheiten und KDE Connect
- Screenshots, Bildschirmaufnahme, OCR und Bildschirmschoner
- AI-Usage fuer Codex, Claude, Antigravity und weitere Anbieter
- niri-Tastenkuerzel, Terminalfarben und eigener Autostart

## Installation

Vorausgesetzt werden Arch Linux (oder ein Arch-Derivat), niri und eine laufende
Wayland-Sitzung.

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
nbshell switch on
```

`setup.sh` zeigt vor jeder Paketinstallation, was fehlt. Wer Pakete lieber
selbst verwaltet, installiert nur die Dateien:

```bash
./install.sh
nbshell start
```

Die vorhandene niri-Konfiguration bleibt erhalten. Gibt es noch keine, erzeugt
der Installer eine minimale gueltige `~/.config/niri/config.kdl`. Persönliche
nbshell-Einstellungen werden bei spaeteren Installationen nicht ueberschrieben.

Nach der Installation sind diese Befehle hilfreich:

```bash
nbshell switch status    # Integration und Dienste pruefen
nbshell menu             # Hauptmenue oeffnen
nbshell settings         # Darstellung konfigurieren
nbshell modules          # Module anordnen
nbshell keys             # Tastenkuerzel anzeigen
nbshell --help           # alle Befehle
```

## Hilfe

`nbshell --help` listet alle Befehle. Weitere Dokumentation entsteht parallel
zur Stabilisierung der oeffentlichen Schnittstellen. Bis dahin sind Issues fuer
Fragen und nachvollziehbare Fehlerberichte willkommen.

## Mitmachen

Fehlerberichte und Pull Requests sind willkommen. Bitte beachte vor einem
Beitrag [CONTRIBUTING.md](CONTRIBUTING.md). Sicherheitsprobleme bitte nicht als
oeffentliches Issue melden; Hinweise stehen in [SECURITY.md](SECURITY.md).

## Herkunft und Lizenz

nbshell orientiert sich gestalterisch und in einzelnen Workflows an Omarchy,
ist aber eine eigene Implementierung fuer niri und Quickshell. Die Herkunft
mitgelieferter Farbthemen ist in
[themes/ATTRIBUTION.md](themes/ATTRIBUTION.md) dokumentiert. Der integrierte
AI-Usage-Helfer fuehrt seine eigene MIT-Lizenz im Quellverzeichnis mit.
Weitere uebernommene oder abgeleitete Bestandteile sind in
[THIRD_PARTY.md](THIRD_PARTY.md) aufgefuehrt.

Der uebrige Code steht unter der [MIT-Lizenz](LICENSE).
