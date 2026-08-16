# Zu nbshell beitragen

Danke fuer dein Interesse. nbshell ist noch in aktiver Entwicklung; kleine,
klar abgegrenzte Pull Requests lassen sich am besten pruefen.

## Vor einem Pull Request

1. Beschreibe bei groesseren Aenderungen zuerst das Problem in einem Issue.
2. Veraendere keine persoenliche `config.json` und committe keine Zugangsdaten.
3. Pruefe Shell-Skripte mit `bash -n` und die niri-Datei mit `niri validate`.
4. Fuehre die vorhandenen Tests aus:

   ```bash
   ./tests/plugin-validation.sh
   ```

5. Erklaere im Pull Request knapp, was sich fuer Benutzer aendert und wie du
   die Aenderung getestet hast.

KI-unterstuetzte Beitraege sind willkommen. Bitte pruefe generierten Code
selbst und gib im Pull Request an, wenn wesentliche Teile mit KI entstanden
sind.
