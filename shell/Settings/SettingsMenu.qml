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
PanelWindow {
    id: root

    property int selected: 0

    // Jede Zeile: Schluessel, Beschriftung und die Werte, durch die
    // links/rechts blaettert. `values` leer heisst: Zahl mit Schrittweite.
    readonly property var entries: [
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
            "values": ["island", "bar"]
        },
        {
            "key": "widgetStyle",
            "def": "box",
            "label": "Bausteine",
            "values": ["box", "bracket", "plain"]
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
            "key": "lines",
            "def": 1,
            "label": "Hoehe in Zeilen",
            "step": 1,
            "min": 1,
            "max": 3
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
            "label": "Rahmen",
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
            "key": "collapseDelay",
            "def": 250,
            "label": "Nachlauf beim Zuklappen",
            "step": 50,
            "min": 0,
            "max": 1000
        },
        {
            "key": "wallpaper",
            "def": false,
            "label": "Hintergrundbild",
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
            "key": "clipboard",
            "def": true,
            "label": "Zwischenablage",
            "values": [true, false]
        },
        {
            "key": "themeExport",
            "def": true,
            "label": "Terminalfarben schreiben",
            "values": [true, false]
        }
    ]

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

    onVisibleChanged: {
        if (visible) {
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
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.entries.length - 1, root.selected + 1)
        Keys.onLeftPressed: root.step(root.entries[root.selected], -1)
        Keys.onRightPressed: root.step(root.entries[root.selected], 1)
        Keys.onReturnPressed: root.step(root.entries[root.selected], 1)

        Rectangle {
            anchors.centerIn: parent
            width: Theme.cellW * 52
            height: column.implicitHeight + Theme.cellH * 2

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: 0

                Text {
                    text: "EINSTELLUNGEN"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    bottomPadding: Theme.cellH * 0.5
                }

                Repeater {
                    model: root.entries

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        height: Theme.cellH * 1.5
                        radius: Theme.radius
                        color: row.index === root.selected ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.index === root.selected ? "▸ " : "  ") + row.modelData.label
                            color: row.index === root.selected ? Theme.fgBright : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.index === root.selected ? "◂ " : "  ") + root.shown(row.modelData) + (row.index === root.selected ? " ▸" : "  ")
                            color: row.index === root.selected ? Theme.accent : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: root.selected = row.index
                            onClicked: mouseEvent => root.step(row.modelData, mouseEvent.button === Qt.RightButton ? -1 : 1)
                            onWheel: wheelEvent => root.step(row.modelData, wheelEvent.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                }

                Text {
                    width: column.width
                    text: "↑↓ waehlen · ←→ aendern · Esc schliesst\nWas hier fehlt, steht in " + Config.configDir + "/config.json"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    topPadding: Theme.cellH * 0.5
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
