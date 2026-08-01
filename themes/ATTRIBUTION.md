# Herkunft der Themes

Die `colors.toml`-Dateien in diesem Verzeichnis stammen aus
<https://github.com/basecamp/omarchy>, MIT-lizenziert,
Copyright (c) David Heinemeier Hansson.

Uebernommen wurden ausschliesslich die Farbdefinitionen. Vorschaubilder,
Hintergruende und die uebrigen Theme-Dateien des Originals (zusammen ueber
100 MB) sind bewusst nicht enthalten.

Aktualisieren:

    for t in <omarchy-repo>/themes/*/; do
      mkdir -p "themes/$(basename "$t")"
      cp "$t/colors.toml" "themes/$(basename "$t")/"
    done
