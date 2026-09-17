import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Commons as Commons
import qs.Services
import qs.Settings
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout

// Main menu: Omarchy-style presentation over nbshell's existing action tree.
// Escape clears search, then closes; Left/Backspace return to the parent.
// The tree remains data: leaves have run, categories have sub. Actions retain
// their existing service paths; the visual adaptation never replaces them.
PanelWindow {
    id: root

    visible: Runtime.menuOpen
    screen: Compositor.focusedScreen
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
    onSelectedChanged: Qt.callLater(revealSelection)
    onItemsChanged: Qt.callLater(revealSelection)

    function revealSelection() {
        const row = menuRows.itemAt(root.selected);
        if (!root.visible || !row || menuScroll.height < row.height) return;
        const top = row.y;
        const bottom = top + row.height;
        if (top < menuScroll.contentY) menuScroll.contentY = top;
        else if (bottom > menuScroll.contentY + menuScroll.height)
            menuScroll.contentY = bottom - menuScroll.height;
        menuScroll.returnToBounds();
    }
    property string filterText: ""
    property bool settingsPage: false
    readonly property bool closing: box.closing
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

        // Auch innerhalb eines Untermenues wird der ganze Teilbaum
        // durchsucht, nicht nur die direkte Ebene: die Referenz findet eine
        // Aktion ueber dieselbe Suche, egal wie tief sie liegt.
        if (trail.length)
            return root.searchTree(levelItems, needle, trail, "");

        // Root search spans the complete nested menu as well as installed
        // desktop applications. The reference caps nothing; our list scrolls
        // and maxRowsHeight bounds it, so the earlier slices (five apps,
        // seven actions) only made existing entries unreachable by search.
        const appMatches = Apps.rank(needle).map(match => ({
            "label": match.entry.name,
            "description": match.entry.genericName || match.entry.comment || "Application",
            "appEntry": match.entry
        }));
        const menuMatches = root.searchTree(root.tree, needle, [], "");
        return appMatches.concat(menuMatches);
    }

    // Menu typography is scoped independently from the bar.
    readonly property int fs: Theme.menuFontSize
    property real pinnedTop: -1
    property real maxRowsHeight: -1
    property var pointerPosition: null
    readonly property var rowHeights: items.length ? items.map(e => filterText && e.description ? Theme.menuDetailRowHeight : Theme.menuBaseRowHeight) : [Theme.menuBaseRowHeight]
    readonly property real rowsHeight: MenuLayout.foldedHeight(rowHeights, Theme.menuRowSpacing, Math.min(root.height * 0.7, maxRowsHeight >= 0 ? maxRowsHeight : root.height, root.height - (pinnedTop >= 0 ? pinnedTop : Theme.menuScreenMargin) - Theme.menuScreenMargin - Theme.menuInset * 2 - Theme.menuHeaderHeight - Theme.menuGap))

    function freezePosition() {
        if (pinnedTop < 0 && visible) { pinnedTop = box.y; maxRowsHeight = menuScroll.height; }
        pointerPosition = null;
    }
    function move(delta) {
        pointerPosition = null;
        selected = MenuLayout.nextIndex(selected, delta, items.length);
    }
    function setFilter(value) {
        freezePosition();
        filterText = value; selected = 0; menuScroll.contentY = 0;
    }
    function pointTo(index, item, mouse) {
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) selected = index;
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point)) pointerPosition = point;
    }

    function open() {
        const wasClosing = box.closing;
        root.pinnedTop = -1; root.maxRowsHeight = -1; root.pointerPosition = null;
        root.trail = [];
        root.selected = 0;
        root.filterText = "";
        Runtime.menuOpen = true;
        if (wasClosing) box.enter();
    }
    function openSettings() {
        root.settingsPage = true;
    }
    function close() {
        root.settingsPage = false;
        box.dismiss(() => Runtime.menuOpen = false);
    }
    Component.onCompleted: Runtime.menuController = root
    Component.onDestruction: if (Runtime.menuController === root) Runtime.menuController = null
    function back() {
        freezePosition();
        if (root.settingsPage) {
            root.settingsPage = false;
            return;
        }
        if (root.filterText !== "") {
            root.setFilter("");
            return;
        }
        if (root.trail.length) {
            root.trail = root.trail.slice(0, -1);
            root.selected = 0;
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
            freezePosition();
            menuScroll.contentY = 0;
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
            box.enter();
            root.pinnedTop = -1; root.maxRowsHeight = -1; root.pointerPosition = null;
            root.trail = [];
            root.selected = 0;
            root.filterText = "";
            root.settingsPage = false;
            menuScroll.contentY = 0;
            Qt.callLater(root.revealSelection);
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
            "key": "a", "label": "Apps", "icon": "󰀻", "link": true,
            "run": () => {
                Runtime.launcherPrefill = "";
                Runtime.openLauncher();
            }
        },
        {
            "key": "d", "label": "Dashboard", "description": "Today, media, and frequently used tools", "icon": Icons.cpu,
            "run": () => Runtime.dashboardOpen = true
        },
        {
            "key": "w", "label": "Work & Tools", "description": "Notifications, lists, notes, translation, and web apps", "icon": Icons.clipboard,
            "sub": [
                { "key": "n", "label": "Notifications", "description": "Search, DND, and archive", "icon": Icons.bell, "run": () => Runtime.notificationCenterOpen = true },
                { "key": "c", "label": "Clipboard", "icon": Icons.clipboard, "run": () => Runtime.clipOpen = true },
                { "key": "t", "label": "Todo", "icon": Icons.todo, "run": () => Runtime.todoOpen = true },
                { "key": "n", "label": "Notes", "icon": "󰎞", "run": () => Runtime.notesOpen = true },
                { "key": "s", "label": "Shopping list", "description": "Format and send to the Einkauf WhatsApp group", "icon": Icons.cp(0xF0110), "run": () => Runtime.shoppingListOpen = true },
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
            "sub": [
                { "key": "a", "label": "Agent Center", "description": "Agents, projects, sessions, and usage", "icon": Icons.cp(0xF1218), "run": () => Runtime.agentCenterOpen = true },
                { "key": "o", "label": "Install / Open OpenClaw", "description": "Local AI workspace with subscription sign-in", "icon": Icons.download, "run": () => root.term("nbshell openclaw install") }
            ]
        },
        {
            "key": "m", "label": "Media & Capture", "description": "Media controls, screenshots, recording, OCR, and audio tools", "icon": Icons.camera,
            "sub": [
                { "key": "m", "label": "Media", "icon": Icons.play, "run": () => { Runtime.dashboardPage = 0; Runtime.dashboardOpen = true; } },
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
                    { "key": "m", "label": "Minecraft", "icon": "󰍳", "run": () => Quickshell.execDetached(["nbshell", "gaming", "install", "minecraft"]) },
                    { "key": "n", "label": "NVIDIA GeForce NOW", "icon": "󰢹", "run": () => root.term("nbshell gaming install geforce-now") },
                    { "key": "x", "label": "Xbox Cloud Gaming", "icon": "", "run": () => root.term("nbshell gaming install xbox-cloud") },
                    { "key": "c", "label": "Xbox Controllers", "icon": "󰂯", "run": () => root.term("nbshell gaming install xbox-controllers") },
                    { "key": "b", "label": "Battle.net", "icon": "", "run": () => Quickshell.execDetached(["nbshell", "gaming", "install", "battlenet"]) },
                    { "key": "g", "label": "GOG Galaxy", "icon": "", "run": () => Quickshell.execDetached(["nbshell", "gaming", "install", "gog"]) },
                    { "key": "e", "label": "Epic Games", "icon": "", "run": () => Quickshell.execDetached(["nbshell", "gaming", "install", "epic"]) },
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
                    { "key": "b", "label": "Battle.net app entry", "icon": "", "run": () => root.term("nbshell gaming remove battlenet") },
                    { "key": "g", "label": "GOG Galaxy app entry", "icon": "", "run": () => root.term("nbshell gaming remove gog") },
                    { "key": "e", "label": "Epic Games app entry", "icon": "", "run": () => root.term("nbshell gaming remove epic") },
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
                    { "key": "c", "label": "Control center", "icon": Icons.wifi, "run": () => {
                        Runtime.revealIslandTemporarily();
                        Runtime.requestPopout("control", Compositor.focusedOutput);
                    } },
                    { "key": "t", "label": "Tailscale", "icon": "󰖂", "run": () => root.term("tailscale status") },
                    { "key": "q", "label": "Wi-Fi QR code", "icon": Icons.cp(0xF0432), "run": () => Runtime.qrOpen = true },
                    { "key": "s", "label": "Speedtest", "icon": Icons.cpu, "run": () => Runtime.speedOpen = true }
                ] },
                { "key": "w", "label": "Windows", "description": "Windows 11 on demand, shared files, and development", "icon": Icons.cp(0xF17A), "sub": [
                    { "key": "s", "label": "Start Windows", "description": "Open Windows; stop the VM when closed", "icon": Icons.cp(0xF17A), "run": () => Quickshell.execDetached(["nbshell", "windows", "launch"]) },
                    { "key": "b", "label": "Start Windows for builds", "description": "Keep Windows running after the window closes", "icon": Icons.cp(0xF17A), "run": () => Quickshell.execDetached(["nbshell", "windows", "launch", "--keep-alive"]) },
                    { "key": "i", "label": "Install / Configure", "description": "Install Windows or adjust VM resources", "icon": Icons.download, "run": () => Quickshell.execDetached(["nbshell", "windows", "install"]) },
                    { "key": "f", "label": "Shared folder", "description": "Files shared with Windows", "icon": Icons.cp(0xF024B), "run": () => Quickshell.execDetached(["nbshell", "windows", "shared"]) },
                    { "key": "c", "label": "Installation console", "description": "View installation and recovery in the browser", "icon": Icons.cp(0xF108), "run": () => Quickshell.execDetached(["nbshell", "windows", "console"]) },
                    { "key": "l", "label": "Windows sign-in", "description": "Show the private VM login in a local terminal", "icon": Icons.cp(0xF033E), "run": () => root.term("nbshell windows credentials") },
                    { "key": "t", "label": "Status", "icon": Icons.cpu, "run": () => root.term("nbshell windows status") },
                    { "key": "x", "label": "Stop Windows", "description": "Shut down the VM, including background builds", "icon": Icons.cp(0xF011), "run": () => Quickshell.execDetached(["nbshell", "windows", "stop"]) }
                ] },
                { "key": "d", "label": "Displays", "description": "Resolution, scale, orientation, and position", "icon": Icons.cp(0xF0379), "run": () => Runtime.displayOpen = true },
                { "key": "t", "label": "Touchpad", "description": "Pointer feel, Mac-inspired curves, scrolling and clicking", "icon": Icons.cp(0xF07F8), "run": () => Quickshell.execDetached(["nbshell", "touchpad"]) },
                { "key": "p", "label": "Processes", "icon": Icons.cpu, "run": () => Runtime.procsOpen = true },
                { "key": "v", "label": "Security", "description": "Password manager and session security", "icon": Icons.cp(0xF033E), "sub": [
                    { "key": "p", "label": "Approve next system action", "description": "Use the paired phone for one sudo or Polkit request", "icon": Icons.cp(0xF033E), "run": () => root.term("nbshell auth approve-next system") },
                    { "key": "o", "label": "Open 1Password", "icon": Icons.cp(0xF033E), "run": () => Quickshell.execDetached(["1password", "--show"]) },
                    { "key": "q", "label": "1Password Quick Access", "description": "Search without leaving the current app (Ctrl+Shift+Space)", "icon": Icons.cp(0xF06E0), "run": () => Quickshell.execDetached(["1password", "--quick-access"]) },
                    { "key": "l", "label": "Lock 1Password", "icon": Icons.cp(0xF033E), "run": () => Quickshell.execDetached(["1password", "--lock"]) }
                ] },
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
                    { "key": "e", "label": "Theme Maker", "description": "Create a theme with a live UI preview", "icon": Icons.palette, "run": () => Quickshell.execDetached(["nbshell", "theme-maker"]) },
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
        ? trail[trail.length - 1].label
        : "Go"

    Rectangle {
        anchors.fill: parent
        color: root.settingsPage ? Theme.scrim : Theme.menuScrim
        opacity: box.opacity
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

        Keys.onEscapePressed: {
            if (root.settingsPage) root.back();
            else if (root.filterText) root.setFilter("");
            else root.close();
        }
        Keys.onReturnPressed: root.activate(root.selected)
        Keys.onEnterPressed: root.activate(root.selected)
        Keys.onRightPressed: root.activate(root.selected)
        Keys.onLeftPressed: if (!root.filterText) root.back()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                root.move(event.key === Qt.Key_PageUp ? -6 : 6); event.accepted = true;
            } else if (Commons.Util.editsFilter(event, root.filterText)) {
                // Dieselben Bearbeitungstasten wie die Referenz: Backspace
                // loescht ein Zeichen, Strg+Backspace ein Wort, Strg+U die
                // ganze Suche. Util.editsFilter/editedFilter sind genau dafuer
                // portiert worden und waren hier ungenutzt.
                root.setFilter(Commons.Util.editedFilter(event, root.filterText));
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace) {
                // Nur wenn nichts zu loeschen ist: Backspace geht eine Ebene
                // zurueck (dokumentiertes nbshell-Verhalten).
                root.back();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_N || event.key === Qt.Key_P)) {
                root.move(event.key === Qt.Key_N ? 1 : -1); event.accepted = true;
            } else if (event.text && event.text >= " " && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                root.setFilter(root.filterText + event.text); event.accepted = true;
            }
        }

        MotionSurface {
            id: box
            visible: !root.settingsPage
            // Original menu maps immediately; no row zoom or delayed dismissal.
            motionEnabled: false
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(Theme.menuScreenMargin, Math.min(root.pinnedTop >= 0 ? root.pinnedTop : Math.round((parent.height - height) / 2), parent.height - height - Theme.menuScreenMargin))
            width: Math.max(1, Math.min(Theme.menuWidth, parent.width - Theme.menuScreenMargin * 2))
            height: Math.max(1, Math.min(Theme.menuInset * 2 + Theme.menuHeaderHeight + Theme.menuGap + root.rowsHeight, parent.height - Theme.menuScreenMargin * 2))
            color: Theme.bg
            border.width: Theme.menuBorderWidth
            border.color: Theme.fg
            clip: true
            MouseArea { anchors.fill: parent }

            Line {
                id: menuHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.menuInset
                height: Theme.menuHeaderHeight
                text: root.filterText || (root.crumb + "…")
                font.pixelSize: Theme.menuFontSize
                color: Theme.fg
                opacity: root.filterText ? 1 : 0.58
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            Flickable {
                id: menuScroll
                anchors.top: menuHeader.bottom
                anchors.topMargin: Theme.menuGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Theme.menuInset
                anchors.rightMargin: Theme.menuInset
                anchors.bottomMargin: Theme.menuInset
                clip: true
                contentWidth: width
                contentHeight: column.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                onHeightChanged: Qt.callLater(root.revealSelection)

                Column {
                    id: column
                    width: menuScroll.width
                    spacing: Theme.menuRowSpacing
                    Line {
                        width: parent.width; height: Theme.menuBaseRowHeight
                        visible: root.items.length === 0
                        text: "No results"; color: Theme.fg; opacity: 0.58
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Theme.menuFontSize
                    }
                    Repeater {
                        id: menuRows
                        model: root.items
                        InteractiveSurface {
                            id: rowItem
                            required property var modelData
                            required property int index
                            readonly property bool isSub: !!modelData.sub
                            readonly property bool active: rowItem.index === root.selected
                            readonly property bool showDetail: root.filterText !== "" && !!modelData.description
                            width: column.width
                            height: showDetail ? Theme.menuDetailRowHeight : Theme.menuBaseRowHeight
                            radius: Theme.radius
                            color: active ? Theme.menuSelection : "transparent"
                            keyboardFocusable: false
                            accessibleName: modelData.label || "Menu item"
                            accessibleDescription: [modelData.description || "", isSub ? "Opens submenu" : "Activates action"].filter(part => part !== "").join("; ")
                            accessibleSelected: active
                            onTriggered: root.activate(index)
                            Item {
                                id: rowIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.menuRowInset
                                width: Theme.menuIconSlot
                                height: Theme.menuIconSize
                                y: rowText.y + (labelText.height - height) / 2
                                readonly property string appIcon: rowItem.modelData.appEntry ? Apps.iconFor(rowItem.modelData.appEntry) : ""
                                IconImage {
                                    anchors.centerIn: parent
                                    width: Theme.menuIconSize; height: width
                                    visible: rowIcon.appIcon !== ""
                                    source: rowIcon.appIcon
                                }
                                Line {
                                    anchors.centerIn: parent
                                    visible: rowIcon.appIcon === ""
                                    text: rowItem.modelData.appEntry ? (rowItem.modelData.label || "?").charAt(0).toUpperCase() : (rowItem.modelData.icon || "")
                                    color: rowItem.active ? Theme.menuSelectedText : Theme.fg
                                    font.pixelSize: Theme.menuIconSize
                                }
                            }
                            Column {
                                id: rowText
                                anchors.left: rowIcon.right
                                anchors.leftMargin: Theme.menuGap
                                anchors.right: rowTrail.left
                                anchors.rightMargin: Theme.menuGap
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.menuRowSpacing
                                Line {
                                    id: labelText
                                    width: parent.width; text: rowItem.modelData.label
                                    color: rowItem.active ? Theme.menuSelectedText : Theme.fg
                                    font.pixelSize: Theme.menuFontSize; font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Line {
                                    width: parent.width; visible: rowItem.showDetail
                                    text: rowItem.modelData.description || ""
                                    color: Theme.fg; opacity: 0.52
                                    font.pixelSize: Theme.menuDetailFontSize; elide: Text.ElideRight
                                }
                            }
                            Line {
                                id: rowTrail
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.menuRowInset
                                width: Theme.menuTrailWidth
                                y: rowText.y + (labelText.height - height) / 2
                                text: rowItem.isSub || rowItem.modelData.link ? "›" : ""
                                color: rowItem.active ? Theme.menuSelectedText : Theme.fg
                                opacity: 0.36; font.pixelSize: Theme.menuFontSize
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.pointTo(rowItem.index, rowItem, {x: mouseX, y: mouseY})
                                onPositionChanged: mouse => root.pointTo(rowItem.index, rowItem, mouse)
                                onClicked: { root.selected = rowItem.index; rowItem.activate(); }
                            }
                        }
                    }
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
