import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Settings
import qs.Widgets

// Das Menue -- ein Omarchy-artiger Sammelpunkt fuer alles, was nbshell kann.
//
// Vollbild-Overlay mit exklusiver Tastatur, genau wie PowerMenu und der
// Starter. Der Unterschied: die Liste ist VERSCHACHTELT. Kategorien (mit ▸)
// klappen als eigene Ebene auf, Esc/Backspace geht eine Ebene zurueck, auf der
// obersten schliesst Esc. Jede Zeile hat einen Buchstaben davor -- damit
// waehlt man ohne zu zaehlen.
//
// Der Baum ist reine Daten (siehe `tree`): ein Blatt hat `run`, eine Kategorie
// `sub`. Aktionen setzen dieselben Runtime-Flags / rufen dieselben Dienste wie
// die IPC-Handler -- das Menue ist also nur ein zweiter Weg zu Vorhandenem.
PanelWindow {
    id: root

    visible: Runtime.menuOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:menu"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.menuOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    // ── Navigation ──────────────────────────────────────────────────────────
    // `trail` ist der Stapel betretener Kategorien; die sichtbare Liste ist die
    // `sub` der obersten -- oder der Wurzelbaum, wenn der Stapel leer ist.
    property var trail: []
    property int selected: 0
    property string filterText: ""
    property bool settingsPage: false
    readonly property var levelItems: trail.length ? trail[trail.length - 1].sub : root.tree

    function searchTree(entries, needle, parents, inheritedText) {
        var matches = [];
        for (var i = 0; i < entries.length; i++) {
            const entry = entries[i];
            const path = parents.concat([entry.label]);
            const searchable = (inheritedText + " " + entry.label + " " + (entry.description || "")).toLowerCase();
            if (entry.sub) {
                matches = matches.concat(root.searchTree(entry.sub, needle, path, searchable));
            } else if (searchable.indexOf(needle) >= 0) {
                matches.push({
                    "label": entry.label,
                    "description": path.slice(0, -1).join(" › ") || entry.description || "Menu action",
                    "icon": entry.icon,
                    "run": entry.run
                });
            }
        }
        return matches;
    }

    readonly property var items: {
        const needle = filterText.trim().toLowerCase();
        if (needle === "") return levelItems;

        if (trail.length)
            return levelItems.filter(e => (e.label + " " + (e.description || "")).toLowerCase().indexOf(needle) >= 0);

        // Root search spans the complete nested menu as well as installed
        // desktop applications. Caps keep one-letter queries on screen.
        const appMatches = Apps.rank(needle).slice(0, 5).map(match => ({
            "label": match.entry.name,
            "description": match.entry.genericName || match.entry.comment || "Application",
            "appEntry": match.entry
        }));
        const menuMatches = root.searchTree(root.tree, needle, [], "").slice(0, 7);
        return appMatches.concat(menuMatches);
    }

    // Etwas groesser als die Leiste -- das Menue soll bequem lesbar sein.
    readonly property int fs: Theme.fontTitle

    function open() {
        root.trail = [];
        root.selected = 0;
        root.filterText = "";
        Runtime.menuOpen = true;
    }
    function openSettings() {
        root.settingsPage = true;
    }
    function close() {
        root.settingsPage = false;
        box.dismiss(() => Runtime.menuOpen = false);
    }
    function back() {
        if (root.settingsPage) {
            root.settingsPage = false;
            return;
        }
        if (root.filterText !== "") {
            root.filterText = "";
            root.selected = 0;
            return;
        }
        if (root.trail.length) {
            root.trail = root.trail.slice(0, -1);
            root.selected = 0;
        } else {
            root.close();
        }
    }
    function activate(i) {
        const it = root.items[i];
        if (!it)
            return;
        if (it.appEntry) {
            root.close();
            Apps.launch(it.appEntry);
        } else if (it.sub) {
            root.trail = root.trail.concat([it]);
            root.selected = 0;
            root.filterText = "";
        } else {
            if (!it.inline)
                root.close();
            if (it.run)
                it.run();
        }
    }

    // Einen Befehl in einem Terminal starten -- fuer interaktive Skripte wie
    // `webapp add`, die per read nachfragen. Terminal wie beim Starter (Apps),
    // mit einer Pause am Ende, damit man das Ergebnis noch liest.
    function term(cmd) {
        Quickshell.execDetached([Apps.terminal, "-e", "sh", "-c",
            cmd + "; printf '\\nEnter closes this window … '; read -r _"]);
    }

    onVisibleChanged: {
        if (visible) {
            root.trail = [];
            root.selected = 0;
            root.filterText = "";
            root.settingsPage = false;
            keys.forceActiveFocus();
        }
    }

    // Beim externen Oeffnen (IPC) immer frisch auf der Wurzel starten.
    Connections {
        target: Runtime
        function onMenuOpenChanged() {
            if (Runtime.menuOpen) {
                root.trail = [];
                root.selected = 0;
                root.filterText = "";
            }
        }
    }

    // ── Der Menuebaum ───────────────────────────────────────────────────────
    readonly property var tree: [
        {
            "key": "a", "label": "Apps", "icon": Icons.matrix,
            "run": () => {
                Runtime.launcherPrefill = "";
                Runtime.launcherOpen = true;
            }
        },
        {
            "key": "d", "label": "Dashboard", "description": "Today, media, and frequently used tools", "icon": Icons.cp(0xF0F9),
            "run": () => Runtime.dashboardOpen = true
        },
        {
            "key": "w", "label": "Work & Tools", "description": "Notifications, clipboard, tasks, translation, and web apps", "icon": Icons.clipboard,
            "sub": [
                { "key": "n", "label": "Notifications", "description": "Search, DND, and archive", "icon": Icons.bell, "run": () => Runtime.notificationCenterOpen = true },
                { "key": "c", "label": "Clipboard", "icon": Icons.clipboard, "run": () => Runtime.clipOpen = true },
                { "key": "t", "label": "Todo", "icon": Icons.todo, "run": () => Runtime.todoOpen = true },
                { "key": "n", "label": "Notes", "icon": "󰎞", "run": () => Runtime.notesOpen = true },
                { "key": "h", "label": "Habits", "icon": Icons.habit, "run": () => Runtime.habitsOpen = true },
                { "key": "e", "label": "Emoji", "description": "Search and copy locally", "icon": "😀", "run": () => Runtime.emojiOpen = true },
                { "key": "r", "label": "Translate", "icon": "文", "run": () => Plugins.invoke("shaun.quick-translate", "toggle", "{}") },
                { "key": "w", "label": "Web apps", "icon": Icons.cp(0xF059F), "sub": [
                    { "key": "a", "label": "Create web app", "icon": Icons.cp(0xF0704), "run": () => root.term("$HOME/.local/bin/webapp add") },
                    { "key": "e", "label": "Remove web app", "icon": Icons.cp(0xF01B4), "run": () => root.term("$HOME/.local/bin/webapp remove") },
                    { "key": "l", "label": "List web apps", "icon": Icons.cp(0xF035C), "run": () => root.term("$HOME/.local/bin/webapp list") }
                ] },
                { "key": "k", "label": "Keyboard shortcuts", "icon": Icons.keyboard, "run": () => Runtime.keysOpen = true }
            ]
        },
        {
            "key": "i", "label": "AI & Agents", "description": "Agents, models, projects, sessions, and usage", "icon": Icons.cp(0xF1218),
            "run": () => Runtime.agentCenterOpen = true
        },
        {
            "key": "m", "label": "Media & Capture", "description": "Media controls, screenshots, recording, OCR, and audio tools", "icon": Icons.camera,
            "sub": [
                { "key": "m", "label": "Media", "icon": Icons.play, "run": () => { Runtime.dashboardPage = 1; Runtime.dashboardOpen = true; } },
                { "key": "c", "label": "Capture", "description": "Screenshots, recording, and trimming", "icon": Icons.camera, "sub": [
                    { "key": "r", "label": "Region", "icon": Icons.camera, "run": () => CaptureService.shoot("region") },
                    { "key": "b", "label": "Screen", "icon": Icons.cp(0xF0379), "run": () => CaptureService.shoot("screen") },
                    { "key": "f", "label": "Window", "icon": Icons.cp(0xF04A1), "run": () => {
                        Runtime.captureWindowSelect = true;
                        Runtime.captureOpen = true;
                    } },
                    { "key": "o", "label": "Recognize text (OCR)", "icon": Icons.cp(0xF0219), "run": () => CaptureService.ocr() },
                    { "key": "q", "label": "Scan QR code", "icon": Icons.cp(0xF0432), "run": () => CaptureService.qr() },
                    { "key": "a", "label": "Start/stop recording", "icon": Icons.record, "run": () => CaptureService.toggleRecording() },
                    { "key": "t", "label": "Trim latest recording", "icon": Icons.cp(0xF03B7), "run": () => CaptureService.trimLastRecording() },
                    { "key": "s", "label": "Open streaming studio", "icon": Icons.cp(0xF0502), "run": () => CaptureService.openStreamingStudio() }
                ] },
                { "key": "a", "label": "Focus & equalizer", "icon": Icons.volumeHigh, "run": () => Runtime.audioToolsOpen = true }
            ]
        },
        {
            "key": "g", "label": "Gaming", "description": "Install and remove game launchers and streaming tools", "icon": Icons.cp(0xF11B),
            "sub": [
                { "key": "i", "label": "Install", "icon": Icons.download, "sub": [
                    { "key": "s", "label": "Steam", "icon": "", "run": () => root.term("nbshell gaming install steam") },
                    { "key": "r", "label": "RetroArch", "icon": "󰯉", "run": () => root.term("nbshell gaming install retroarch") },
                    { "key": "m", "label": "Minecraft", "icon": "󰍳", "run": () => root.term("nbshell gaming install minecraft") },
                    { "key": "n", "label": "NVIDIA GeForce NOW", "icon": "󰢹", "run": () => root.term("nbshell gaming install geforce-now") },
                    { "key": "x", "label": "Xbox Cloud Gaming", "icon": "", "run": () => root.term("nbshell gaming install xbox-cloud") },
                    { "key": "c", "label": "Xbox Controllers", "icon": "󰂯", "run": () => root.term("nbshell gaming install xbox-controllers") },
                    { "key": "b", "label": "Battle.net", "icon": "", "run": () => root.term("nbshell gaming install battlenet") },
                    { "key": "l", "label": "Lutris", "icon": "", "run": () => root.term("nbshell gaming install lutris") },
                    { "key": "h", "label": "Heroic (Epic Games)", "icon": "󱓟", "run": () => root.term("nbshell gaming install heroic") },
                    { "key": "o", "label": "Moonlight", "icon": Icons.play, "run": () => root.term("nbshell gaming install moonlight") },
                    { "key": "a", "label": "RetroArch game launcher", "icon": "󰯉", "run": () => root.term("nbshell gaming retro-launcher") }
                ] },
                { "key": "r", "label": "Remove", "icon": Icons.cp(0xF01B4), "sub": [
                    { "key": "s", "label": "Steam", "icon": "", "run": () => root.term("nbshell gaming remove steam") },
                    { "key": "r", "label": "RetroArch", "icon": "󰯉", "run": () => root.term("nbshell gaming remove retroarch") },
                    { "key": "m", "label": "Minecraft", "icon": "󰍳", "run": () => root.term("nbshell gaming remove minecraft") },
                    { "key": "n", "label": "NVIDIA GeForce NOW", "icon": "󰢹", "run": () => root.term("nbshell gaming remove geforce-now") },
                    { "key": "x", "label": "Xbox Cloud Gaming", "icon": "", "run": () => root.term("nbshell gaming remove xbox-cloud") },
                    { "key": "c", "label": "Xbox Controllers", "icon": "󰂯", "run": () => root.term("nbshell gaming remove xbox-controllers") },
                    { "key": "b", "label": "Battle.net", "icon": "", "run": () => root.term("nbshell gaming remove battlenet") },
                    { "key": "l", "label": "Lutris", "icon": "", "run": () => root.term("nbshell gaming remove lutris") },
                    { "key": "h", "label": "Heroic (Epic Games)", "icon": "󱓟", "run": () => root.term("nbshell gaming remove heroic") },
                    { "key": "o", "label": "Moonlight", "icon": Icons.play, "run": () => root.term("nbshell gaming remove moonlight") }
                ] },
                { "key": "s", "label": "Status", "description": "Show installed and available tools", "icon": Icons.cp(0xF035C), "run": () => root.term("nbshell gaming status") }
            ]
        },
        {
            "key": "s", "label": "System", "description": "Connections, displays, status, processes, and session controls", "icon": Icons.cpu,
            "sub": [
                { "key": "h", "label": "System & Plugins", "description": "Sync, updates, printing, ports, and hardware", "icon": Icons.matrix, "run": () => Runtime.hubOpen = true },
                { "key": "c", "label": "Connections", "description": "Network, VPN, Bluetooth, Tailscale, and QR", "icon": Icons.wifi, "sub": [
                    { "key": "c", "label": "Control center", "icon": Icons.wifi, "run": () => Runtime.controlOpen = true },
                    { "key": "t", "label": "Tailscale", "icon": "󰖂", "run": () => root.term("tailscale status") },
                    { "key": "q", "label": "Wi-Fi QR code", "icon": Icons.cp(0xF0432), "run": () => Runtime.qrOpen = true },
                    { "key": "s", "label": "Speedtest", "icon": Icons.cpu, "run": () => Runtime.speedOpen = true }
                ] },
                { "key": "d", "label": "Displays", "description": "Resolution, scale, orientation, and position", "icon": Icons.cp(0xF0379), "run": () => Runtime.displayOpen = true },
                { "key": "p", "label": "Processes", "icon": Icons.cpu, "run": () => Runtime.procsOpen = true },
                { "key": "s", "label": "Session", "description": "Lock, sleep, restart, or power off", "icon": Icons.cp(0xF0425), "sub": [
                    { "key": "s", "label": "Lock", "icon": Icons.cp(0xF033E), "run": () => Session.run("lock") },
                    { "key": "a", "label": "Log out", "icon": Icons.cp(0xF0343), "run": () => Session.run("logout") },
                    { "key": "b", "label": "Suspend", "icon": Icons.sleep, "run": () => Session.run("suspend") },
                    { "key": "u", "label": "Hibernate", "icon": Icons.sleep, "run": () => Session.run("hibernate") },
                    { "key": "n", "label": "Restart", "icon": Icons.refresh, "run": () => Session.run("reboot") },
                    { "key": "x", "label": "Power off", "icon": Icons.cp(0xF0425), "run": () => Session.run("poweroff") }
                ] }
            ]
        },
        {
            "key": "p", "label": "Personalize", "description": "Themes, wallpaper, bar, modules, plugins, and settings", "icon": Icons.palette,
            "sub": [
                { "key": "s", "label": "Settings", "description": "Appearance, behavior, idle, lock screen, and services", "icon": Icons.cp(0xF0493), "inline": true, "run": () => root.openSettings() },
                { "key": "l", "label": "Look & Feel", "description": "Themes, wallpaper, bar, and settings", "icon": Icons.palette, "sub": [
                    { "key": "t", "label": "Choose theme", "icon": Icons.palette, "run": () => Runtime.themePickerOpen = true },
                    { "key": "n", "label": "Next theme", "icon": Icons.cp(0xF0142), "run": () => ThemeIndex.step(1) },
                    { "key": "v", "label": "Previous theme", "icon": Icons.cp(0xF0141), "run": () => ThemeIndex.step(-1) },
                    { "key": "w", "label": "Wallpaper", "icon": Icons.cp(0xF02E9), "run": () => Runtime.wallpaperOpen = true },
                    { "key": "b", "label": "Change bar shape", "icon": Icons.cp(0xF0379), "run": () => {
                        const order = ["island", "pill", "bar"];
                        Config.set("mode", order[(order.indexOf(Config.mode) + 1) % order.length]);
                    } },
                    { "key": "g", "label": "UI gallery", "icon": Icons.cp(0xF03D9), "run": () => Runtime.uiGalleryOpen = true },
                    { "key": "a", "label": "Open Aether", "icon": Icons.palette, "run": () => Quickshell.execDetached(["aether"]) },
                    { "key": "i", "label": "Import Aether theme", "icon": Icons.download, "run": () => root.term("$HOME/.local/bin/nb-aether-import") },
                    { "key": "x", "label": "Remove theme", "icon": Icons.cp(0xF01B4), "run": () => root.term("$HOME/.local/bin/nbshell theme remove") }
                ] },
                { "key": "m", "label": "Arrange modules", "icon": Icons.matrix, "run": () => Runtime.modulesOpen = true },
                { "key": "p", "label": "Plugin management", "icon": Icons.cp(0xF12E), "sub": [
                    { "key": "s", "label": "Plugin manager & store", "icon": Icons.cp(0xF12E), "run": () => { Runtime.pluginManagerTab = "installed"; Runtime.pluginDeveloperOpen = true; } },
                    { "key": "l", "label": "List plugins", "icon": Icons.cp(0xF035C), "run": () => root.term("nbshell plugins") },
                    { "key": "u", "label": "Update plugins", "icon": Icons.refresh, "run": () => root.term("nbshell plugin update") },
                    { "key": "o", "label": "Open plugin folder", "icon": Icons.cp(0xF024B), "run": () => Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/nbshell/plugins"]) }
                ] }
            ]
        }
    ]

    // Icon fuer den Kopf: in einer Kategorie deren eigenes, sonst das Rastersymbol.
    readonly property string crumbIcon: trail.length ? (trail[trail.length - 1].icon || Icons.matrix) : Icons.matrix

    // Kopfzeile: Wurzel heisst „MENÜ", sonst der Pfad der betretenen Kategorien.
    readonly property string crumb: trail.length
        ? trail.map(t => t.label).join("  ›  ").toUpperCase()
        : "MENU"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
    }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        // This scope must remain active while the embedded settings page owns
        // focus; otherwise its child FocusScope cannot receive key events.
        focus: root.visible

        Keys.onEscapePressed: root.back()
        Keys.onReturnPressed: root.activate(root.selected)
        Keys.onEnterPressed: root.activate(root.selected)
        Keys.onRightPressed: root.activate(root.selected)
        Keys.onLeftPressed: root.back()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.items.length - 1, root.selected + 1)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace) {
                if (root.filterText !== "") {
                    root.filterText = root.filterText.slice(0, -1);
                    root.selected = 0;
                } else root.back();
                event.accepted = true;
                return;
            }
            // Wie Quattros Menue: Tippen filtert sofort. Die rechts gezeigten
            // Buchstaben bleiben als Merkhilfe fuer die Baumstruktur.
            if (event.text && event.text >= " ") {
                root.filterText += event.text;
                root.selected = 0;
                event.accepted = true;
            }
        }

        MotionSurface {
            id: box

            visible: !root.settingsPage

            anchors.centerIn: parent
            width: Theme.cellW * 48
            height: column.implicitHeight + Theme.cellH * 2

            accentBorder: true

            // Klick im Kasten NICHT durchreichen (sonst schliesst der Backdrop).
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: Theme.cellH * 0.2

                Rectangle {
                    width: column.width
                    height: Theme.cellH * 3
                    radius: Theme.radius
                    color: Theme.panelSurfaceRaised
                    border.width: Theme.borderWidth
                    border.color: Theme.panelBorder

                    Line {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW
                        anchors.rightMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText !== "" ? root.filterText : (root.crumbIcon + "  " + root.crumb)
                        color: root.filterText !== "" ? Theme.fg : Theme.fgDim
                        font.pixelSize: root.fs
                        elide: Text.ElideRight
                    }
                }

                Line { visible: root.items.length === 0; text: "No results"; color: Theme.muted; topPadding: Theme.cellH }

                Repeater {
                    model: root.items

                    Rectangle {
                        id: rowItem

                        required property var modelData
                        required property int index

                        readonly property bool isSub: !!modelData.sub
                        readonly property bool active: rowItem.index === root.selected

                        width: column.width
                        height: root.fs * (rowItem.modelData.description ? 3.15 : 2.65)
                        radius: Theme.radius
                        color: rowItem.active ? Theme.selectedSurface(Theme.accent) : "transparent"
                        border.width: rowItem.active ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder
                        scale: rowItem.active ? 1 : 0.992
                        Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Theme.motionEffect
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.motionCurveEffect
                            }
                        }

                        // Akzent-Balken links, wenn die Zeile gewaehlt ist.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.borderWidth * 2
                            height: parent.height * 0.55
                            radius: width
                            color: Theme.accent
                            visible: rowItem.active
                        }

                        Item {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(Theme.cellH * 1.5)
                            height: width

                            readonly property string appIcon: rowItem.modelData.appEntry ? Apps.iconFor(rowItem.modelData.appEntry) : ""

                            IconImage {
                                anchors.fill: parent
                                visible: rowIcon.appIcon !== ""
                                source: rowIcon.appIcon
                            }

                            Line {
                                anchors.centerIn: parent
                                visible: rowIcon.appIcon === ""
                                text: rowItem.modelData.appEntry
                                    ? (rowItem.modelData.label || "?").charAt(0).toUpperCase()
                                    : (rowItem.modelData.icon || "")
                                color: rowItem.active ? Theme.selectedForeground(Theme.accent) : Theme.accent
                                font.pixelSize: root.fs + 1
                            }
                        }

                        Column {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: Theme.cellW
                            anchors.right: rowTrail.left
                            anchors.rightMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Line { width: parent.width; text: rowItem.modelData.label; color: rowItem.active ? Theme.selectedForeground(Theme.accent) : Theme.fg; font.pixelSize: root.fs; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!rowItem.modelData.description; text: rowItem.modelData.description || ""; color: rowItem.active ? Theme.selectedForeground(Theme.accent) : Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
                        }

                        // Rechts: Pfeil bei Untermenue, sonst das Buchstabenkuerzel.
                        Line {
                            id: rowTrail
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowItem.isSub ? "›" : "↵"
                            color: rowItem.active ? Theme.selectedForeground(Theme.accent) : Theme.muted
                            font.pixelSize: root.fs
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = rowItem.index
                            onClicked: root.activate(rowItem.index)
                        }
                    }
                }

                Line {
                    text: root.filterText !== "" ? "Search menus and apps · Backspace deletes · Enter launches" : (root.trail.length ? "Esc/← back · type to search" : "Esc closes · type to search")
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }

        SettingsMenu {
            anchors.fill: parent
            visible: root.settingsPage
            embedded: true
            onBackRequested: root.settingsPage = false
            onCloseRequested: Runtime.menuOpen = false
        }
    }
}
