import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Einstellungen.
//
// Bisher war die config.json die Oberflaeche -- das reicht, solange man weiss,
// welche Schluessel es gibt. Hier stehen sie sichtbar, mit ihren Werten, und
// links/rechts blaettert durch die Moeglichkeiten. Geschrieben wird sofort;
// die Leiste aendert sich beim Zusehen, weil die Config beobachtet wird.
//
// Bewusst kein Formular mit Eingabefeldern: jede Zeile ist eine Liste von
// Werten, durch die man blaettert. Das laesst sich blind bedienen und braucht
// keine Pruefung von Eingaben.
//
// Zwei Spalten, seit die Liste ueber vierzig Zeilen lang war: links die
// Gruppen, rechts ihre Zeilen. Tab wechselt die Seite. Eine Wurst aus
// Ueberschriften und Zeilen liest sich ab einer gewissen Laenge nicht mehr --
// man scrollt an der Ueberschrift vorbei und weiss nicht mehr, wo man ist.
PanelWindow {
    id: root

    // Welche Seite die Tasten bekommt: 0 = Gruppen links, 1 = Zeilen rechts.
    property int pane: 1
    property int group: 0
    property int selected: 0

    // Jede Zeile: Schluessel, Beschriftung und die Werte, durch die
    // links/rechts blaettert. `values` leer heisst: Zahl mit Schrittweite.
    // "head" beginnt eine neue Gruppe.
    readonly property var entries: [
        {
            "head": "LEISTE"
        },
        {
            "key": "edge",
            "def": "top",
            "label": "Rand",
            "values": ["top", "bottom"]
        },
        {
            "key": "mode",
            "def": "island",
            "label": "Form",
            "values": ["island", "pill", "bar"]
        },
        {
            "key": "gap",
            "def": 6,
            "label": "Abstand zum Rand",
            "step": 1,
            "min": 0,
            "max": 40
        },
        {
            "key": "lines",
            "def": 1,
            "label": "Hoehe in Zeilen",
            "step": 1,
            "min": 1,
            "max": 3
        },
        {
            "key": "barBorder",
            "def": true,
            "label": "Rahmen um die Leiste",
            "values": [true, false]
        },
        {
            "key": "islandCenter",
            "def": true,
            "label": "Mitte erzwingen (Insel)",
            "values": [true, false]
        },
        {
            "key": "osdInPill",
            "def": true,
            "label": "Einblendung in der Pille",
            "values": [true, false]
        },
        {
            "head": "BAUSTEINE"
        },
        {
            "action": "modules",
            "label": "Anordnen …",
            "hint": "Enter"
        },
        {
            "key": "widgetColor",
            "def": "text",
            "label": "Farbe",
            "values": ["text", "accent"]
        },
        {
            "key": "widgetStyle",
            "def": "box",
            "label": "Form",
            "values": ["box", "bracket", "plain"]
        },
        {
            "key": "widgetIcons",
            "def": true,
            "label": "Symbole",
            "values": [true, false]
        },
        {
            "key": "quietWidgets",
            "def": true,
            "label": "Stille verstecken",
            "values": [true, false]
        },
        {
            "key": "workspaceStyle",
            "def": "numbers",
            "label": "Arbeitsflaechen",
            "values": ["numbers", "dots", "pacman", "invader"]
        },
        {
            "key": "workspaceClassic",
            "def": true,
            "label": "Figur klassisch",
            "values": [true, false]
        },
        {
            "key": "trayExpanded",
            "def": false,
            "label": "Tray aufgeklappt",
            "values": [true, false]
        },
        {
            "head": "AUSSEHEN"
        },
        {
            // Eine Rolle, keine Farbe: `theme` ist der Vorschlag des Themes,
            // alles andere eine Farbe AUS dessen Palette. Nach einem
            // Themewechsel gilt dieselbe Rolle im neuen Theme.
            "key": "accent",
            "def": "theme",
            "label": "Akzentfarbe",
            "values": ["theme", "red", "green", "yellow", "blue", "magenta", "cyan", "orange", "foreground"]
        },
        {
            "key": "fontSize",
            "def": 13,
            "label": "Schriftgroesse",
            "step": 1,
            "min": 8,
            "max": 24
        },
        {
            "key": "widgetGap",
            "def": 1,
            "label": "Abstand der Bausteine",
            "step": 0.5,
            "min": 0,
            "max": 4
        },
        {
            "key": "padX",
            "def": 1,
            "label": "Innenabstand seitlich",
            "step": 0.5,
            "min": 0,
            "max": 3
        },
        {
            "key": "padY",
            "def": 4,
            "label": "Innenabstand",
            "step": 1,
            "min": 0,
            "max": 20
        },
        {
            "key": "radius",
            "def": 0,
            "label": "Ecken",
            "step": 1,
            "min": 0,
            "max": 20
        },
        {
            "key": "borderWidth",
            "def": 1,
            "label": "Rahmenstaerke",
            "step": 1,
            "min": 0,
            "max": 4
        },
        {
            "key": "opacity",
            "def": 1.0,
            "label": "Deckkraft",
            "step": 0.05,
            "min": 0.2,
            "max": 1
        },
        {
            "head": "VERHALTEN"
        },
        {
            "key": "collapseDelay",
            "def": 250,
            "label": "Nachlauf beim Zuklappen",
            "step": 50,
            "min": 0,
            "max": 1000
        },
        {
            "key": "popoutLeaveDelay",
            "def": 2500,
            "label": "Popout schliesst nach",
            "step": 250,
            "min": 500,
            "max": 6000
        },
        {
            "key": "notifyCorner",
            "def": "auto",
            "label": "Benachrichtigungen",
            "values": ["auto", "top", "bottom"]
        },
        {
            "key": "notifyTimeout",
            "def": 6000,
            "label": "Karte bleibt",
            "step": 1000,
            "min": 2000,
            "max": 20000
        },
        {
            "head": "DIENSTE"
        },
        {
            "key": "wallpaper",
            "def": false,
            "label": "Hintergrundbild",
            "values": [true, false]
        },
        {
            "key": "wallpaperBlur",
            "def": true,
            "label": "Uebersicht weichzeichnen",
            "values": [true, false]
        },
        {
            "key": "osd",
            "def": true,
            "label": "Einblendung",
            "values": [true, false]
        },
        {
            "key": "notifications",
            "def": false,
            "label": "Benachrichtigungsserver",
            "values": [true, false]
        },
        {
            "key": "updates",
            "def": true,
            "label": "Updates pruefen",
            "values": [true, false]
        },
        {
            // Aus heisst: pacman/paru fragen wieder bei jedem Schritt nach.
            "key": "updateNoconfirm",
            "def": true,
            "label": "Update ohne Rueckfrage",
            "values": [true, false]
        },
        {
            "key": "sysGpu",
            "def": true,
            "label": "Grafikkarte abfragen",
            "values": [true, false]
        },
        {
            "key": "calendar",
            "def": true,
            "label": "Kalender (khal)",
            "values": [true, false]
        },
        {
            "key": "clipboard",
            "def": true,
            "label": "Zwischenablage",
            "values": [true, false]
        },
        {
            "key": "clipboardGuardSecrets",
            "def": true,
            "label": "Passwoerter aussperren",
            "values": [true, false]
        },
        {
            "key": "todo",
            "def": true,
            "label": "Aufgaben",
            "values": [true, false]
        },
        {
            "key": "todoShowDone",
            "def": true,
            "label": "Erledigte anzeigen",
            "values": [true, false]
        },
        {
            "key": "themeExport",
            "def": true,
            "label": "Terminalfarben schreiben",
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

    visible: Runtime.settingsOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:settings"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.settingsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.settingsOpen = false;
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
            return v ? "an" : "aus";
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

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onTabPressed: root.switchPane()
        Keys.onBacktabPressed: root.switchPane()

        // Links steht die Gruppenliste: dort ist rechts der Weg zu den
        // Zeilen, nicht das Aendern eines Werts.
        Keys.onLeftPressed: {
            if (root.pane === 1)
                root.step(root.items[root.selected], -1);
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

        Rectangle {
            id: box

            readonly property real rowHeight: Theme.cellH * 1.5
            readonly property real leftWidth: Theme.cellW * 16
            readonly property real rightWidth: Theme.cellW * 42

            anchors.centerIn: parent
            width: box.leftWidth + box.rightWidth + Theme.cellW * 3
            height: header.implicitHeight + root.maxItems * box.rowHeight + footer.implicitHeight + Theme.cellH * 2.5

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            MouseArea {
                anchors.fill: parent
            }

            Text {
                id: header

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.cellH * 0.6
                anchors.leftMargin: Theme.cellW
                text: "EINSTELLUNGEN"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
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
                        color: groupRow.current && root.pane === 0 ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (groupRow.current ? "▸ " : "  ") + groupRow.modelData.head
                            color: {
                                if (groupRow.current && root.pane === 0)
                                    return Theme.on(Theme.selection);
                                return groupRow.current ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim;
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
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
                        color: row.current && root.pane === 1 ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.current ? "▸ " : "  ") + row.modelData.label
                            color: row.current && root.pane === 1 ? Theme.on(Theme.selection) : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            // Die Pfeile nur auf der Seite, die sie auch
                            // annimmt: links kaeme ←→ nicht hier an.
                            text: (row.current && root.pane === 1 ? "◂ " : "  ") + root.shown(row.modelData) + (row.current && root.pane === 1 ? " ▸" : "  ")
                            color: row.current && root.pane === 1 ? Theme.readable(Theme.accent, Theme.selection) : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
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

            Text {
                id: footer

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.cellH * 0.6
                anchors.leftMargin: Theme.cellW
                // Muss in EINE Zeile passen: die Hoehe des Kastens rechnet mit
                // `footer.implicitHeight`, ein Umbruch schoebe den Fusstext in
                // die letzte Zeile der Liste.
                text: "Tab: Seite · ↑↓ waehlen · ←→ aendern · Esc schliesst"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
        }
    }
}
