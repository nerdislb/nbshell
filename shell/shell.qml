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
import qs.Shopping
import qs.Store
import qs.Habits
import qs.Net
import qs.Music
import qs.Keys
import qs.Menu
import qs.Ipc
import qs.Extensions
import qs.Widgets

// nbshell is an independent Quickshell desktop, not a plugin or DMS fork.
// Explicit activation owns the notification and tray integration; remaining
// DMS handling exists only for migration and recovery cleanup.
ShellRoot {
    id: shell

    readonly property bool disableHotReload: ["1", "true", "yes"].includes(
        String(Quickshell.env("NBSHELL_DISABLE_HOT_RELOAD")).toLowerCase())

    Component.onCompleted: {
        // Manual development starts keep live QML reloads. The installed
        // systemd service disables them: watching the complete deployed tree
        // for a session that never edits it only consumes inotify resources.
        Quickshell.watchFiles = !shell.disableHotReload;
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
        void ShoppingDraft.draft;
        void Habits.count;
        // Die Leerlaufuhren muessen von Anfang an laufen, nicht erst beim ersten
        // Blick auf die Zelle: sonst begaenne die Frist erst, wenn jemand die
        // Leiste anfasst -- also nie.
        void Idle.enabled;
        void Cursor.themes;
        void Nearby.enabled;
        void ZenPip.active;
    }

    Bar {}

    Wallpaper {}

    Launcher {}

    Osd {}

    Popups {}

    MotionLoader {
        requested: Runtime.notificationCenterOpen
        sourceComponent: Component { NotificationCenter {} }
    }

    MotionLoader {
        requested: Runtime.powerOpen
        sourceComponent: Component { PowerMenu {} }
    }

    // Large, infrequently used surfaces are created only while open. Their
    // public IPC remains permanently available through the Runtime flags
    // below, while closing a surface releases its QML object tree and caches.
    LazyLoader { active: Runtime.procsOpen; ProcessList {} }

    LazyLoader { active: Runtime.captureOpen; CaptureMenu {} }

    MotionLoader {
        requested: Runtime.settingsOpen
        sourceComponent: Component { SettingsWindow {} }
    }

    MotionLoader {
        requested: Runtime.modulesOpen
        sourceComponent: Component { ModulesMenu {} }
    }

    MotionLoader {
        requested: Runtime.pluginDeveloperOpen
        sourceComponent: Component { PluginDeveloper {} }
    }

    MotionLoader {
        requested: Runtime.displayOpen
        sourceComponent: Component { DisplayPanel {} }
    }

    MotionLoader {
        requested: Runtime.uiGalleryOpen
        sourceComponent: Component { UiGallery {} }
    }

    MotionLoader {
        requested: Runtime.themePickerOpen
        sourceComponent: Component { ThemeGallery {} }
    }

    LazyLoader { active: Runtime.wallpaperOpen; WallpaperPicker {} }

    LazyLoader { active: Runtime.todoOpen; TodoList {} }

    LazyLoader { active: Runtime.notesOpen; NotesWindow {} }

    LazyLoader { active: Runtime.calculatorOpen; CalculatorWindow {} }

    LazyLoader { active: Runtime.shoppingListOpen; ShoppingListWindow {} }

    LazyLoader { active: Runtime.storeOpen; StoreWindow {} }

    LazyLoader { active: Runtime.habitsOpen; HabitsList {} }

    LazyLoader { active: Runtime.qrOpen; QrWindow {} }

    LazyLoader { active: Runtime.speedOpen; SpeedWindow {} }

    MotionLoader {
        requested: Runtime.audioToolsOpen
        sourceComponent: Component { AudioTools {} }
    }

    LazyLoader { active: Runtime.keysOpen; KeysWindow {} }

    Menu {}

    LazyLoader { active: Runtime.emojiOpen; EmojiWindow {} }

    MotionLoader {
        requested: Runtime.hubOpen
        sourceComponent: Component { SystemHub {} }
    }

    MotionLoader {
        requested: Runtime.dashboardOpen
        sourceComponent: Component { Dashboard {} }
    }

    MotionLoader {
        requested: Runtime.agentCenterOpen
        sourceComponent: Component { AgentCenter {} }
    }

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
