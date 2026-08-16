import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
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
    readonly property var levelItems: trail.length ? trail[trail.length - 1].sub : root.tree
    readonly property var items: {
        const needle = filterText.trim().toLowerCase();
        if (needle === "") return levelItems;
        return levelItems.filter(e => (e.label + " " + (e.description || "")).toLowerCase().indexOf(needle) >= 0);
    }

    // Etwas groesser als die Leiste -- das Menue soll bequem lesbar sein.
    readonly property int fs: Theme.fontSize + 3

    function open() {
        root.trail = [];
        root.selected = 0;
        root.filterText = "";
        Runtime.menuOpen = true;
    }
    function close() {
        Runtime.menuOpen = false;
    }
    function back() {
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
        if (it.sub) {
            root.trail = root.trail.concat([it]);
            root.selected = 0;
            root.filterText = "";
        } else {
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
            cmd + "; printf '\\n[Enter] schliesst das Fenster … '; read -r _"]);
    }

    onVisibleChanged: {
        if (visible) {
            root.trail = [];
            root.selected = 0;
            root.filterText = "";
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
            "key": "h", "label": "System & Plugins", "description": "Agenten, Sync, Updates, Druck, Ports und Hardware", "icon": Icons.matrix,
            "run": () => Runtime.hubOpen = true
        },
        {
            "key": "n", "label": "Benachrichtigungen", "description": "durchsuchen, DND und Archiv", "icon": Icons.bell,
            "run": () => Runtime.notificationCenterOpen = true
        },
        {
            "key": "e", "label": "Emoji", "description": "lokal suchen und kopieren", "icon": "😀",
            "run": () => Runtime.emojiOpen = true
        },
        {
            "key": "m", "label": "Module", "description": "Bar-Bausteine anordnen", "icon": Icons.cp(0xF12E),
            "run": () => Runtime.modulesOpen = true
        },
        {
            "key": "w", "label": "Webapps", "icon": Icons.cp(0xF059F),
            "sub": [
                { "key": "a", "label": "Webapp anlegen", "icon": Icons.cp(0xF0704), "run": () => root.term("$HOME/.local/bin/webapp add") },
                { "key": "e", "label": "Webapp entfernen", "icon": Icons.cp(0xF01B4), "run": () => root.term("$HOME/.local/bin/webapp remove") },
                { "key": "l", "label": "Webapps auflisten", "icon": Icons.cp(0xF035C), "run": () => root.term("$HOME/.local/bin/webapp list") }
            ]
        },
        {
            "key": "l", "label": "Look & Feel", "description": "Themes, Wallpaper, Bar und Einstellungen", "icon": Icons.palette,
            "sub": [
                { "key": "t", "label": "Theme wählen", "icon": Icons.palette, "run": () => Runtime.themePickerOpen = true },
                { "key": "n", "label": "Nächstes Theme", "icon": Icons.cp(0xF0142), "run": () => ThemeIndex.step(1) },
                { "key": "v", "label": "Voriges Theme", "icon": Icons.cp(0xF0141), "run": () => ThemeIndex.step(-1) },
                { "key": "w", "label": "Wallpaper", "icon": Icons.cp(0xF02E9), "run": () => Runtime.wallpaperOpen = true },
                { "key": "b", "label": "Bar-Form wechseln", "icon": Icons.cp(0xF0379), "run": () => {
                    const order = ["island", "pill", "bar"];
                    Config.set("mode", order[(order.indexOf(Config.mode) + 1) % order.length]);
                } },
                { "key": "e", "label": "Einstellungen", "icon": Icons.cp(0xF0493), "run": () => Runtime.settingsOpen = true },
                { "key": "a", "label": "Aether öffnen", "icon": Icons.palette, "run": () => Quickshell.execDetached(["aether"]) },
                { "key": "i", "label": "Aether-Theme holen", "icon": Icons.download, "run": () => root.term("$HOME/.local/bin/nb-aether-import") },
                { "key": "x", "label": "Theme entfernen", "icon": Icons.cp(0xF01B4), "run": () => root.term("$HOME/.local/bin/nbshell theme remove") }
            ]
        },
        {
            "key": "c", "label": "Capture", "description": "Screenshot, OCR, QR und Recording", "icon": Icons.camera,
            "sub": [
                { "key": "r", "label": "Bereich", "icon": Icons.camera, "run": () => CaptureService.shoot("region") },
                { "key": "b", "label": "Bildschirm", "icon": Icons.cp(0xF0379), "run": () => CaptureService.shoot("screen") },
                { "key": "f", "label": "Fenster", "icon": Icons.cp(0xF04A1), "run": () => CaptureService.shoot("window") },
                { "key": "o", "label": "Text erkennen (OCR)", "icon": Icons.cp(0xF0219), "run": () => CaptureService.ocr() },
                { "key": "q", "label": "QR-Code erkennen", "icon": Icons.cp(0xF0432), "run": () => CaptureService.qr() },
                { "key": "a", "label": "Aufnahme starten/stoppen", "icon": Icons.record, "run": () => CaptureService.toggleRecording() }
            ]
        },
        {
            "key": "y", "label": "Sitzung", "description": "Sperren, schlafen, neu starten oder ausschalten", "icon": Icons.cp(0xF0425),
            "sub": [
                { "key": "s", "label": "Sperren", "icon": Icons.cp(0xF033E), "run": () => Session.run("lock") },
                { "key": "a", "label": "Abmelden", "icon": Icons.cp(0xF0343), "run": () => Session.run("logout") },
                { "key": "b", "label": "Bereitschaft", "icon": Icons.sleep, "run": () => Session.run("suspend") },
                { "key": "u", "label": "Ruhezustand", "icon": Icons.sleep, "run": () => Session.run("hibernate") },
                { "key": "n", "label": "Neu starten", "icon": Icons.refresh, "run": () => Session.run("reboot") },
                { "key": "x", "label": "Ausschalten", "icon": Icons.cp(0xF0425), "run": () => Session.run("poweroff") }
            ]
        },
        {
            "key": "v", "label": "Verbindungen", "description": "Netz, Bluetooth, Tailscale und QR", "icon": Icons.wifi,
            "sub": [
                { "key": "c", "label": "Control-Center", "icon": Icons.wifi, "run": () => Runtime.controlOpen = true },
                { "key": "t", "label": "Tailscale", "icon": "󰖂", "run": () => root.term("tailscale status") },
                { "key": "q", "label": "WLAN-QR-Code", "icon": Icons.cp(0xF0432), "run": () => Runtime.qrOpen = true },
                { "key": "s", "label": "Speedtest", "icon": Icons.cpu, "run": () => Runtime.speedOpen = true }
            ]
        },
        {
            "key": "e", "label": "Extras", "icon": Icons.cp(0xF035C),
            "sub": [
                { "key": "p", "label": "Plugin-Verwaltung", "icon": Icons.cp(0xF12E), "sub": [
                    { "key": "a", "label": "Module anordnen", "icon": Icons.matrix, "run": () => Runtime.modulesOpen = true },
                    { "key": "d", "label": "Plugin-Diagnose", "icon": Icons.cpu, "run": () => Runtime.pluginDeveloperOpen = true },
                    { "key": "l", "label": "Plugins auflisten", "icon": Icons.cp(0xF035C), "run": () => root.term("nbshell plugins") },
                    { "key": "u", "label": "Plugins aktualisieren", "icon": Icons.refresh, "run": () => root.term("nbshell plugin update") },
                    { "key": "o", "label": "Plugin-Ordner oeffnen", "icon": Icons.cp(0xF024B), "run": () => Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/nbshell/plugins"]) }
                ] },
                { "key": "z", "label": "Zwischenablage", "icon": Icons.clipboard, "run": () => Runtime.clipOpen = true },
                { "key": "r", "label": "Prozesse", "icon": Icons.cpu, "run": () => Runtime.procsOpen = true },
                { "key": "m", "label": "Musik", "icon": Icons.play, "run": () => Runtime.musicOpen = true },
                { "key": "a", "label": "Fokus & Equalizer", "icon": Icons.volumeHigh, "run": () => Runtime.audioToolsOpen = true },
                { "key": "t", "label": "Todo", "icon": Icons.todo, "run": () => Runtime.todoOpen = true },
                { "key": "h", "label": "Habits", "icon": Icons.habit, "run": () => Runtime.habitsOpen = true },
                { "key": "k", "label": "Tastenkürzel", "icon": Icons.keyboard, "run": () => Runtime.keysOpen = true }
            ]
        }
    ]

    // Icon fuer den Kopf: in einer Kategorie deren eigenes, sonst das Rastersymbol.
    readonly property string crumbIcon: trail.length ? (trail[trail.length - 1].icon || Icons.matrix) : Icons.matrix

    // Kopfzeile: Wurzel heisst „MENÜ", sonst der Pfad der betretenen Kategorien.
    readonly property string crumb: trail.length
        ? trail.map(t => t.label).join("  ›  ").toUpperCase()
        : "MENÜ"

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.bgDarker, 0.76)
    }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
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

        Rectangle {
            id: box

            anchors.centerIn: parent
            width: Theme.cellW * 48
            height: column.implicitHeight + Theme.cellH * 2

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.muted

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
                    color: Theme.bgLight

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

                Line { visible: root.items.length === 0; text: "Keine Treffer"; color: Theme.muted; topPadding: Theme.cellH }

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
                        color: rowItem.active ? Theme.selection : "transparent"

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

                        Line {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowItem.modelData.icon || ""
                            color: rowItem.active ? Theme.on(Theme.selection) : Theme.accent
                            font.pixelSize: root.fs + 1
                        }

                        Column {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: Theme.cellW
                            anchors.right: rowTrail.left
                            anchors.rightMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Line { width: parent.width; text: rowItem.modelData.label; color: rowItem.active ? Theme.on(Theme.selection) : Theme.fg; font.pixelSize: root.fs; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!rowItem.modelData.description; text: rowItem.modelData.description || ""; color: rowItem.active ? Theme.on(Theme.selection) : Theme.muted; font.pixelSize: Theme.fontSize; elide: Text.ElideRight }
                        }

                        // Rechts: Pfeil bei Untermenue, sonst das Buchstabenkuerzel.
                        Line {
                            id: rowTrail
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowItem.isSub ? "›" : "↵"
                            color: rowItem.active ? Theme.on(Theme.selection) : Theme.muted
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
                    text: root.filterText !== "" ? "Tippen sucht · Backspace loescht · Enter waehlt" : (root.trail.length ? "Esc/← zurueck · Tippen sucht" : "Esc schliesst · Tippen sucht")
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }
}
