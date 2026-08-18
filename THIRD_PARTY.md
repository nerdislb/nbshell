# Drittanbieter und Inspirationen

nbshell ist eine eigene Implementierung. Einige mitgelieferte Bestandteile
stammen aus anderen MIT-lizenzierten Projekten oder wurden davon abgeleitet:

- Die Farbdefinitionen unter `themes/` stammen aus
  [Omarchy](https://github.com/basecamp/omarchy). Details stehen in
  [themes/ATTRIBUTION.md](themes/ATTRIBUTION.md).
- Die Bongo-Cat-Bilder und zugehoerige Logik basieren auf wayland-bongocat und
  HANCOREs Omarchy-Plugin. Beide Lizenztexte liegen unter
  `shell/assets/bongocat/`.
- Teile der KDE-Connect-Erkennung wurden von
  [OmaConnect](https://github.com/jitendradara12/omaconnect) abgeleitet.
- Der AI-Usage-Provider wurde aus dem MIT-lizenzierten `aiOverviewControl`
  integriert. Sein Lizenztext liegt unter `shell/scripts/ai-usage/LICENSE`.
- App-/Web-Herkunft, Fokusaktion und Kartenaufbau der Benachrichtigungszentrale
  sind von Jesse Burlamaques MIT-lizenziertem
  [Herald Notification Center](https://github.com/jesseburlamaque/herald-notification)
  inspiriert. nbshell verwendet dabei weiterhin seinen eigenen persistenten
  Benachrichtigungsdienst und eine eigenstaendige TUI-Implementierung.

Omarchy, niri, Quickshell und die genannten Projekte sind eigenstaendige
Projekte. Ihre Nennung bedeutet keine offizielle Verbindung oder Unterstuetzung.
