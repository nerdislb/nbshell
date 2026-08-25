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
import qs.Notes
import qs.Calculator
import qs.Store
import qs.Habits
import qs.Net
import qs.Music
import qs.Keys
import qs.Menu
import qs.Ipc
import qs.Extensions

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
        console.info("nbshell running — theme:", Config.theme, "| mode:", Config.mode);

        // Singletons entstehen in QML erst, wenn sie jemand anfasst. Die
        // Dienste, die von aussen beobachten (Helligkeit, Netz, Bluetooth,
        // Audio, Themeliste), muessen deshalb hier einmal beruehrt werden --
        // sonst faengt der Helligkeitsdienst erst an zu suchen, wenn das
        // Control Center zum ersten Mal aufgeht, und zeigt so lange 0 %.
        void Brightness.available;
        void Displays.outputs;
        void Net.summary;
        void Bt.available;
        void Audio.ready;
        void ThemeIndex.list;
        // Wallpaper-per-theme restoration is event-driven. Keep its singleton
        // alive from session start; otherwise theme changes before the picker
        // is opened leave the previous theme's override on screen.
        void Wallpapers.current;
        void Apps.entries;
        void Osd.enabled;
        void Notify.count;
        void MediaService.active;
        void Clipboard.entries;
        void Procs.list;
        void CaptureService.recording;
        void AiUsage.available;
        void Agents.defaultAgent;
        void Dictation.state;
        void BongoCat.active;
        void Updates.enabled;
        void ShellUpdates.current;
        void PowerService.available;
        void Calendar.enabled;
        void Plugins.scanned;
        void ThemeExport.enabled;
        // Die Aufgaben muessen von Anfang an gelesen werden, nicht erst beim
        // ersten Blick: sonst stuende in der Leiste eine 0, waehrend in der
        // Datei drei offene Punkte liegen -- und ein Abgleich vom Telefon
        // faende beim Schreiben eine leere eigene Seite vor.
        void Todo.count;
        void Notes.count;
        void Habits.count;
        // Die Leerlaufuhren muessen von Anfang an laufen, nicht erst beim ersten
        // Blick auf die Zelle: sonst begaenne die Frist erst, wenn jemand die
        // Leiste anfasst -- also nie.
        void Idle.enabled;
        void Cursor.themes;
        void Nearby.enabled;
        void Phone.available;
        void Tailnet.available;
        void WhatsApp.unread;
        void ZenPip.active;
    }

    Bar {}

    Wallpaper {}

    Launcher {}

    Osd {}

    Popups {}

    NotificationCenter {}

    PowerMenu {}

    // Large, infrequently used surfaces are created only while open. Their
    // public IPC remains permanently available through the Runtime flags
    // below, while closing a surface releases its QML object tree and caches.
    LazyLoader { active: Runtime.procsOpen; ProcessList {} }

    LazyLoader { active: Runtime.captureOpen; CaptureMenu {} }

    LazyLoader { active: Runtime.settingsOpen; SettingsWindow {} }

    LazyLoader { active: Runtime.modulesOpen; ModulesMenu {} }

    LazyLoader { active: Runtime.pluginDeveloperOpen; PluginDeveloper {} }

    LazyLoader { active: Runtime.displayOpen; DisplayPanel {} }

    LazyLoader { active: Runtime.uiGalleryOpen; UiGallery {} }

    LazyLoader { active: Runtime.wallpaperOpen; WallpaperPicker {} }

    LazyLoader { active: Runtime.todoOpen; TodoList {} }

    LazyLoader { active: Runtime.notesOpen; NotesWindow {} }

    LazyLoader { active: Runtime.calculatorOpen; CalculatorWindow {} }

    LazyLoader { active: Runtime.storeOpen; StoreWindow {} }

    LazyLoader { active: Runtime.habitsOpen; HabitsList {} }

    LazyLoader { active: Runtime.qrOpen; QrWindow {} }

    LazyLoader { active: Runtime.speedOpen; SpeedWindow {} }

    LazyLoader { active: Runtime.audioToolsOpen; AudioTools {} }

    LazyLoader { active: Runtime.keysOpen; KeysWindow {} }

    Menu {}

    LazyLoader { active: Runtime.emojiOpen; EmojiWindow {} }

    LazyLoader { active: Runtime.hubOpen; SystemHub {} }

    LazyLoader { active: Runtime.dashboardOpen; Dashboard {} }

    LazyLoader { active: Runtime.agentCenterOpen; AgentCenter {} }

    // Nachinstallierte Dienste, Panels und Overlays. Nur explizit aktivierte
    // Plugin-IDs werden geladen; reine Bar-Widgets entstehen in WidgetHost.
    PluginHost {}

    // ── Steuerung von aussen ──────────────────────────────────────────────
    // Alles, was `nbshell <ziel> <befehl>` erreichbar macht, liegt in qs/Ipc
    // -- nach Sachgebieten getrennt, damit diese Datei die Uebersicht bleibt.

    LookIpc {}
    SystemIpc {}
    DesktopIpc {}
    DataIpc {}
    DeviceIpc {}
}
