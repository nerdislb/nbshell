import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Einstellungen.
//
// Bisher war die config.json die Oberflaeche -- das reicht, solange man weiss,
// welche Schluessel es gibt. Hier stehen sie sichtbar, mit ihren Werten, und
// links/rechts blaettert durch die Moeglichkeiten. Geschrieben wird sofort;
// die Leiste aendert sich beim Zusehen, weil die Config beobachtet wird.
//
// Bewusst kein Shapeular mit Eingabefeldern: jede Zeile ist eine Liste von
// Werten, durch die man blaettert. Das laesst sich blind bedienen und braucht
// keine Pruefung von Eingaben.
//
// Zwei Spalten, seit die Liste ueber vierzig Zeilen lang war: links die
// Gruppen, rechts ihre Zeilen. Tab wechselt die Seite. Eine Wurst aus
// Ueberschriften und Zeilen liest sich ab einer gewissen Laenge nicht mehr --
// man scrollt an der Ueberschrift vorbei und weiss nicht mehr, wo man ist.
Item {
    id: root

    property bool embedded: false
    property bool externalLifecycle: false
    signal backRequested()
    signal closeRequested()

    // Welche Seite die Tasten bekommt: 0 = Gruppen links, 1 = Zeilen rechts.
    property int pane: 1
    property int group: 0
    property int selected: 0

    // Jede Zeile: Schluessel, Beschriftung und die Werte, durch die
    // links/rechts blaettert. `values` leer heisst: Zahl mit Schrittweite.
    // "head" beginnt eine neue Gruppe.
    readonly property var entries: [
        {
            "head": "BAR"
        },
        {
            "key": "edge",
            "def": "top",
            "label": "Edge",
            "values": ["top", "bottom"]
        },
        {
            "key": "mode",
            "def": "island",
            "label": "Shape",
            "values": ["island", "pill", "bar"]
        },
        {
            "key": "gap",
            "def": 6,
            "label": "Distance from edge",
            "step": 1,
            "min": 0,
            "max": 40
        },
        {
            "key": "lines",
            "def": 1,
            "label": "Height in rows",
            "step": 1,
            "min": 1,
            "max": 3
        },
        {
            "key": "barBorder",
            "def": true,
            "label": "Bar border",
            "values": [true, false]
        },
        {
            "key": "islandCenter",
            "def": true,
            "label": "Force center (island)",
            "values": [true, false]
        },
        {
            "key": "islandExpandFullWidth",
            "def": false,
            "label": "Full width when open",
            "values": [true, false]
        },
        {
            "key": "osdInPill",
            "def": true,
            "label": "Overlay inside pill",
            "values": [true, false]
        },
        {
            "head": "MODULES"
        },
        {
            "action": "modules",
            "label": "Arrange …",
            "hint": "Enter"
        },
        {
            "action": "plugins",
            "label": "Plugin manager …",
            "hint": "Enter"
        },
        {
            "key": "widgetColor",
            "def": "text",
            "label": "Color",
            "values": ["text", "accent"]
        },
        {
            "key": "widgetStyle",
            "def": "box",
            "label": "Shape",
            "values": ["box", "plain"]
        },
        {
            "key": "meterStyle",
            "def": "blocks",
            "label": "Meter",
            "values": ["blocks", "line"]
        },
        {
            "key": "visualizerStyle",
            "def": "blocks",
            "label": "Visualizer",
            "values": ["blocks", "line", "dots", "wave"]
        },
        {
            "key": "widgetIcons",
            "def": true,
            "label": "Icons",
            "values": [true, false]
        },
        {
            "key": "quietWidgets",
            "def": true,
            "label": "Hide silent modules",
            "values": [true, false]
        },
        {
            "key": "workspaceStyle",
            "def": "numbers",
            "label": "Workspaces",
            "values": ["numbers", "dots", "pacman", "invader"]
        },
        {
            "key": "workspaceClassic",
            "def": true,
            "label": "Classic character",
            "values": [true, false]
        },
        {
            "key": "trayExpanded",
            "def": false,
            "label": "Tray expanded",
            "values": [true, false]
        },
        {
            "key": "rightSectionExpanded",
            "def": true,
            "label": "Right bar section expanded",
            "values": [true, false]
        },
        {
            "head": "APPEARANCE"
        },
        {
            // Eine Rolle, keine Color: `theme` ist der Vorschlag des Themes,
            // alles andere eine Color AUS dessen Palette. Nach einem
            // Themewechsel gilt dieselbe Rolle im neuen Theme.
            "key": "accent",
            "def": "theme",
            "label": "Accent color",
            "values": ["theme", "red", "green", "yellow", "blue", "magenta", "cyan", "orange", "foreground"]
        },
        {
            // Die Werte kommen aus dem Dateisystem, nicht aus dieser Liste:
            // welche Zeigerthemen es gibt, weiss nur, wer nachsieht. Ein
            // leerer erster Eintrag heisst "nbshell laesst die Finger davon".
            "key": "cursorTheme",
            "def": "",
            "label": "Cursor theme",
            "values": [""].concat(Cursor.themes)
        },
        {
            "key": "cursorSize",
            "def": 24,
            "label": "Cursor size",
            "step": 4,
            "min": 12,
            "max": 64
        },
        {
            "key": "fontSize",
            "def": 13,
            "label": "Text size",
            "step": 1,
            "min": 8,
            "max": 24
        },
        {
            "key": "widgetGap",
            "def": 1,
            "label": "Module spacing",
            "step": 0.5,
            "min": 0,
            "max": 4
        },
        {
            "key": "padX",
            "def": 1,
            "label": "Horizontal padding",
            "step": 0.5,
            "min": 0,
            "max": 3
        },
        {
            "key": "padY",
            "def": 4,
            "label": "Padding",
            "step": 1,
            "min": 0,
            "max": 20
        },
        {
            "key": "radius",
            "def": 0,
            "label": "Corners",
            "step": 1,
            "min": 0,
            "max": 20
        },
        {
            "key": "borderWidth",
            "def": 1,
            "label": "Border width",
            "step": 1,
            "min": 0,
            "max": 4
        },
        {
            "key": "opacity",
            "def": 1.0,
            "label": "Opacity",
            "step": 0.05,
            "min": 0.2,
            "max": 1
        },
        {
            "key": "motionProfile",
            "def": "standard",
            "label": "Motion",
            "values": ["reduced", "standard", "expressive"]
        },
        {
            "head": "BEHAVIOR"
        },
        {
            "key": "collapseDelay",
            "def": 1400,
            "label": "Collapse delay",
            "step": 100,
            "min": 0,
            "max": 3000
        },
        {
            "key": "popoutLeaveDelay",
            "def": 2500,
            "label": "Popout close delay",
            "step": 250,
            "min": 500,
            "max": 6000
        },
        {
            "key": "notifyCorner",
            "def": "auto",
            "label": "Notifications",
            "values": ["auto", "top", "bottom"]
        },
        {
            "key": "notifyTimeout",
            "def": 6000,
            "label": "Popup duration",
            "step": 1000,
            "min": 2000,
            "max": 20000
        },
        {
            "key": "notifyKeepDays",
            "def": 7,
            "label": "Notification history (days)",
            "step": 1,
            "min": 1,
            "max": 30
        },
        {
            "key": "notifyKeep",
            "def": 200,
            "label": "Notification history limit",
            "step": 50,
            "min": 50,
            "max": 1000
        },
        {
            "head": "IDLE"
        },
        {
            "key": "idle",
            "def": true,
            "label": "Automation",
            "values": [true, false]
        },
        {
            "key": "caffeine",
            "def": false,
            "label": "Keep awake",
            "values": [true, false]
        },
        {
            // 0 heisst: diese Stufe faellt aus.
            "key": "idleDim",
            "def": 240,
            "label": "Dim after (s)",
            "step": 30,
            "min": 0,
            "max": 3600
        },
        {
            "key": "idleScreenOff",
            "def": 600,
            "label": "Turn screen off after (s)",
            "step": 60,
            "min": 0,
            "max": 7200
        },
        {
            "key": "idleLock",
            "def": 900,
            "label": "Lock after (s)",
            "step": 60,
            "min": 0,
            "max": 7200
        },
        {
            "head": "LOCK SCREEN"
        },
        {
            "key": "lockBackground",
            "def": "wallpaper",
            "label": "Background",
            "values": ["wallpaper", "solid"]
        },
        {
            "key": "lockBlur",
            "def": 3,
            "label": "Wallpaper blur",
            "step": 1,
            "min": 0,
            "max": 8
        },
        {
            "key": "lockDim",
            "def": 48,
            "label": "Wallpaper dim (%)",
            "step": 5,
            "min": 0,
            "max": 85
        },
        {
            "key": "lockShowDate",
            "def": true,
            "label": "Show date",
            "values": [true, false]
        },
        {
            "key": "lockShowHost",
            "def": true,
            "label": "Show user and host",
            "values": [true, false]
        },
        {
            "head": "SERVICES"
        },
        {
            "key": "wallpaper",
            "def": false,
            "label": "Wallpaper",
            "values": [true, false]
        },
        {
            "key": "wallpaperBlur",
            "def": true,
            "label": Compositor.isUmbriel ? "Overview backdrop" : "Blur overview",
            "values": [true, false]
        },
        {
            "key": "osd",
            "def": true,
            "label": "OSD",
            "values": [true, false]
        },
        {
            "key": "notifications",
            "def": false,
            "label": "Notification server",
            "values": [true, false]
        },
        {
            "key": "updates",
            "def": true,
            "label": "Check for updates",
            "values": [true, false]
        },
        {
            // Aus heisst: pacman/paru fragen wieder bei jedem Schritt nach.
            "key": "updateNoconfirm",
            "def": true,
            "label": "Update without confirmation",
            "values": [true, false]
        },
        {
            "key": "sysGpu",
            "def": true,
            "label": "Query graphics card",
            "values": [true, false]
        },
        {
            "key": "calendar",
            "def": true,
            "label": "Calendar (khal)",
            "values": [true, false]
        },
        {
            "key": "clipboard",
            "def": true,
            "label": "Clipboard",
            "values": [true, false]
        },
        {
            "key": "clipboardGuardSecrets",
            "def": true,
            "label": "Exclude passwords",
            "values": [true, false]
        },
        {
            "key": "todo",
            "def": true,
            "label": "Tasks",
            "values": [true, false]
        },
        {
            "key": "todoShowDone",
            "def": true,
            "label": "Show completed tasks",
            "values": [true, false]
        },
        {
            "key": "themeExport",
            "def": true,
            "label": "Write terminal colors",
            "values": [true, false]
        }
    ]

    // Aus der flachen Liste die Gruppen bauen. Die Zeilen behalten dabei ihre
    // Identitaet -- `step()` bekommt weiter denselben Eintrag wie vorher.
    readonly property var groups: {
        const out = [];
        var cur = null;
        for (var i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (e.head !== undefined) {
                cur = {
                    "head": e.head,
                    "items": []
                };
                out.push(cur);
            } else if (cur) {
                cur.items.push(e);
            }
        }
        return out;
    }

    readonly property var items: groups[group] ? groups[group].items : []

    // Der Kasten behaelt seine Hoehe, egal welche Gruppe offen ist. Sonst
    // springt er beim Wechseln zwischen zwei und vierzehn Zeilen hin und her,
    // und die Gruppenliste links wandert mit.
    readonly property int maxItems: {
        var n = 0;
        for (var i = 0; i < groups.length; i++)
            n = Math.max(n, groups[i].items.length);
        return n;
    }

    function close() {
        if (root.externalLifecycle) {
            Runtime.settingsOpen = false;
            return;
        }
        box.dismiss(() => {
            if (root.embedded)
                root.closeRequested();
            else
                Runtime.settingsOpen = false;
        });
    }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }

    function back() {
        if (root.embedded)
            root.backRequested();
        else
            root.close();
    }

    // Der Rueckfallwert muss derselbe sein wie in Common/Config.qml -- steht
    // ein Schluessel noch nicht in der config.json, zeigte die Zeile sonst 0,
    // waehrend die Leiste laengst mit der echten Vorgabe arbeitet.
    function valueOf(entry) {
        return Config.value(entry.key, entry.def);
    }

    function shown(entry) {
        if (entry.action !== undefined)
            return entry.hint;
        const v = valueOf(entry);
        if (typeof v === "boolean")
            return v ? "on" : "off";
        if (typeof v === "number" && entry.step && entry.step < 1)
            return v.toFixed(2);
        return String(v);
    }

    // Blaettern: bei Listen zum naechsten Eintrag, bei Zahlen um die
    // Schrittweite -- und an den Enden bleibt es stehen, statt umzuspringen.
    function step(entry, direction) {
        if (!entry)
            return;
        // Zeilen, die etwas OEFFNEN statt etwas zu aendern.
        if (entry.action !== undefined) {
            close();
            if (entry.action === "modules")
                Runtime.modulesOpen = true;
            else if (entry.action === "plugins")
                { Runtime.pluginManagerTab = "installed"; Runtime.pluginDeveloperOpen = true; }
            return;
        }
        const current = valueOf(entry);
        if (entry.values) {
            var i = entry.values.indexOf(current);
            if (i < 0)
                i = 0;
            const next = (i + direction + entry.values.length) % entry.values.length;
            Config.set(entry.key, entry.values[next]);
            return;
        }
        const raw = Number(current) + direction * entry.step;
        const clamped = Math.max(entry.min, Math.min(entry.max, raw));
        Config.set(entry.key, entry.step < 1 ? Math.round(clamped * 100) / 100 : Math.round(clamped));
    }

    function move(delta) {
        if (root.pane === 0) {
            const g = root.group + delta;
            if (g >= 0 && g < root.groups.length) {
                root.group = g;
                root.selected = 0;
            }
            return;
        }
        const i = root.selected + delta;
        if (i >= 0 && i < root.items.length)
            root.selected = i;
    }

    function switchPane() {
        root.pane = root.pane === 0 ? 1 : 0;
    }

    onVisibleChanged: {
        if (visible) {
            // Rechts anfangen: dann bleibt es bei ↑↓ waehlen, ←→ aendern --
            // so, wie die Liste sich vorher bedienen liess.
            pane = 1;
            group = 0;
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: box.opacity
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.back()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onTabPressed: root.switchPane()
        Keys.onBacktabPressed: root.switchPane()

        // Links steht die Gruppenliste: dort ist rechts der Weg zu den
        // Zeilen, nicht das Aendern eines Werts.
        Keys.onLeftPressed: {
            if (root.pane === 1)
                root.step(root.items[root.selected], -1);
            else
                root.back();
        }
        Keys.onRightPressed: {
            if (root.pane === 0)
                root.pane = 1;
            else
                root.step(root.items[root.selected], 1);
        }
        Keys.onReturnPressed: {
            if (root.pane === 0)
                root.pane = 1;
            else
                root.step(root.items[root.selected], 1);
        }

        OverlaySurface {
            id: box

            readonly property real rowHeight: Theme.rowHeight
            // Omarchy-sized navigation and value columns: the settings view
            // should read as a calm overview, not a narrow terminal table.
            readonly property real leftWidth: Theme.cellW * 19
            readonly property real rightWidth: Theme.cellW * 47

            preferredWidth: box.leftWidth + box.rightWidth + Theme.cellW * 4
            preferredHeight: header.implicitHeight + root.maxItems * box.rowHeight + footer.implicitHeight + Theme.cellH * 2.5

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: header

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.cellH * 0.6
                height: Theme.cellH * 3
                implicitHeight: height
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
                    text: (root.embedded ? "‹  MAIN MENU  ›  PERSONALIZE  ›  " : "") + "SETTINGS"
                    color: root.embedded ? Theme.fg : Theme.fgDim
                    font.pixelSize: Theme.fontTitle
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.embedded
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.back()
                }
            }

            // ── Links: die Gruppen ───────────────────────────────────────
            Column {
                id: groupColumn

                anchors.left: parent.left
                anchors.top: header.bottom
                anchors.topMargin: Theme.cellH * 0.5
                anchors.leftMargin: Theme.cellW * 0.5
                width: box.leftWidth
                spacing: 0

                Repeater {
                    model: root.groups

                    Rectangle {
                        id: groupRow

                        required property var modelData
                        required property int index

                        readonly property bool current: groupRow.index === root.group

                        width: groupColumn.width
                        height: box.rowHeight
                        radius: Theme.radius
                        // Nur die Seite, die die Tasten hat, bekommt die
                        // volle Markierung -- sonst sehen beide gleich
                        // ausgewaehlt aus und man weiss nicht, wo man tippt.
                        color: groupRow.current && root.pane === 0 ? Theme.selectedSurface(Theme.accent) : "transparent"

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (groupRow.current ? "▸ " : "  ") + groupRow.modelData.head
                            color: {
                                if (groupRow.current && root.pane === 0)
                                    return Theme.selectedForeground(Theme.accent);
                                return groupRow.current ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim;
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                if (root.group !== groupRow.index) {
                                    root.group = groupRow.index;
                                    root.selected = 0;
                                }
                            }
                            onClicked: {
                                root.group = groupRow.index;
                                root.selected = 0;
                                root.pane = 1;
                            }
                        }
                    }
                }
            }

            // Die Trennlinie zwischen den Spalten -- ein Strich, kein Kasten.
            Rectangle {
                anchors.left: groupColumn.right
                anchors.leftMargin: Theme.cellW
                anchors.top: groupColumn.top
                width: Theme.borderWidth
                height: root.maxItems * box.rowHeight
                color: Theme.muted
            }

            // ── Rechts: die Zeilen der Gruppe ────────────────────────────
            Column {
                id: itemColumn

                anchors.left: groupColumn.right
                anchors.leftMargin: Theme.cellW * 2
                anchors.top: groupColumn.top
                width: box.rightWidth
                spacing: 0

                Repeater {
                    model: root.items

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        readonly property bool current: row.index === root.selected

                        width: itemColumn.width
                        height: box.rowHeight
                        radius: Theme.radius
                        color: row.current && root.pane === 1 ? Theme.selectedSurface(Theme.accent) : "transparent"

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.current ? "▸ " : "  ") + row.modelData.label
                            color: row.current && root.pane === 1 ? Theme.selectedForeground(Theme.accent) : Theme.fg
                        }

                        Line {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            // Die Pfeile nur auf der Seite, die sie auch
                            // annimmt: links kaeme ←→ nicht hier an.
                            text: (row.current && root.pane === 1 ? "◂ " : "  ") + root.shown(row.modelData) + (row.current && root.pane === 1 ? " ▸" : "  ")
                            color: row.current && root.pane === 1 ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: {
                                root.selected = row.index;
                                root.pane = 1;
                            }
                            onClicked: mouseEvent => root.step(row.modelData, mouseEvent.button === Qt.RightButton ? -1 : 1)
                            onWheel: wheelEvent => root.step(row.modelData, wheelEvent.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                }
            }

            Line {
                id: footer

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.cellH * 0.6
                anchors.leftMargin: Theme.cellW
                // Muss in EINE Zeile passen: die Hoehe des Kastens rechnet mit
                // `footer.implicitHeight`, ein Umbruch schoebe den Fusstext in
                // die letzte Zeile der Liste.
                text: root.embedded
                    ? "Tab: page · ↑↓ select · ←→ change · Esc/← back"
                    : "Tab: page · ↑↓ select · ←→ change · Esc closes"
                color: Theme.muted
                elide: Text.ElideRight
            }
        }
    }
}
