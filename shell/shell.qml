//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services
import qs.Bar
import qs.Launcher
import qs.Osd
import qs.Notifications
import qs.Power
import qs.Procs
import qs.Capture
import qs.Settings
import qs.Wallpaper
import qs.Todo
import qs.Habits
import qs.Net
import qs.Music
import qs.Keys
import qs.Ipc

// nbshell -- Einstiegspunkt.
//
// Eine eigene Quickshell-Konfiguration, kein Plugin und kein Fork. DMS bleibt
// daneben installiert und laeuft weiter; die beiden stossen sich nicht, solange
// nbshell keine D-Bus-Namen beansprucht (Benachrichtigungen, Tray) -- das kommt
// erst, wenn hier alles Noetige steht.
ShellRoot {
    id: shell

    Component.onCompleted: {
        // QML-Dateien werden im Betrieb neu geladen. Beim Entwickeln reicht
        // damit Speichern statt Neustarten.
        Quickshell.watchFiles = true;
        console.info("nbshell laeuft — Theme:", Config.theme, "| Modus:", Config.mode);

        // Singletons entstehen in QML erst, wenn sie jemand anfasst. Die
        // Dienste, die von aussen beobachten (Helligkeit, Netz, Bluetooth,
        // Audio, Themeliste), muessen deshalb hier einmal beruehrt werden --
        // sonst faengt der Helligkeitsdienst erst an zu suchen, wenn das
        // Control Center zum ersten Mal aufgeht, und zeigt so lange 0 %.
        void Brightness.available;
        void Net.summary;
        void Bt.available;
        void Audio.ready;
        void ThemeIndex.list;
        void Apps.entries;
        void Osd.enabled;
        void Notify.count;
        void MediaService.active;
        void Clipboard.entries;
        void Procs.list;
        void CaptureService.recording;
        void AiUsage.available;
        void Updates.enabled;
        void PowerService.available;
        void Calendar.enabled;
        void Plugins.scanned;
        void ThemeExport.enabled;
        // Die Aufgaben muessen von Anfang an gelesen werden, nicht erst beim
        // ersten Blick: sonst stuende in der Leiste eine 0, waehrend in der
        // Datei drei offene Punkte liegen -- und ein Abgleich vom Telefon
        // faende beim Schreiben eine leere eigene Seite vor.
        void Todo.count;
        void Habits.count;
        // Die Leerlaufuhren muessen von Anfang an laufen, nicht erst beim ersten
        // Blick auf die Zelle: sonst begaenne die Frist erst, wenn jemand die
        // Leiste anfasst -- also nie.
        void Idle.enabled;
        void Cursor.themes;
        void Nearby.enabled;
    }

    Bar {}

    Wallpaper {}

    Launcher {}

    Osd {}

    Popups {}

    PowerMenu {}

    ProcessList {}

    CaptureMenu {}

    SettingsMenu {}

    ModulesMenu {}

    WallpaperPicker {}

    TodoList {}

    HabitsList {}

    QrWindow {}

    SpeedWindow {}

    MusicWindow {}

    KeysWindow {}

    // ── Steuerung von aussen ──────────────────────────────────────────────
    // Alles, was `nbshell <ziel> <befehl>` erreichbar macht, liegt in qs/Ipc
    // -- nach Sachgebieten getrennt, damit diese Datei die Uebersicht bleibt.

    LookIpc {}
    SystemIpc {}
    DesktopIpc {}
    DataIpc {}
    DeviceIpc {}
}
