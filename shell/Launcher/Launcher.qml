import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services

// Anwendungsstarter.
//
// Ein Vollbildfenster auf der obersten Ebene, das die Tastatur exklusiv
// bekommt, solange es offen ist -- anders liesse sich nicht tippen, waehrend
// darunter ein Fenster den Fokus haelt. Sichtbar ist davon nur der Kasten in
// der Mitte; die restliche Flaeche ist durchsichtig und schliesst beim Klick.
//
// Es gibt es nur einmal, nicht je Bildschirm: ein zweiter Starter auf dem
// zweiten Monitor waere ein zweites Eingabefeld mit eigenem Zustand.
PanelWindow {
    id: root

    readonly property var results: Apps.search(input.text)

    // Wie DMS' Spotlight: die Liste bleibt so lang, wie Platz ist, und der
    // Kasten waechst nicht bei jedem Tastendruck.
    property int selected: 0

    // Das Fenster bleibt bestehen und wird nur ein- und ausgeblendet: so ist
    // die Liste beim naechsten Oeffnen sofort da.
    visible: Runtime.launcherOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:launcher"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.launcherOpen = false;
    }

    function accept() {
        const entry = results[selected];
        if (entry)
            Apps.launch(entry);
        else
            Apps.run(input.text);
        close();
    }

    function move(delta) {
        if (results.length === 0)
            return;
        selected = Math.max(0, Math.min(results.length - 1, selected + delta));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    onVisibleChanged: {
        if (visible) {
            input.text = "";
            selected = 0;
            input.forceActiveFocus();
        }
    }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // Etwas oberhalb der Mitte: dort sucht das Auge zuerst, und die Liste
        // waechst nach unten.
        y: Math.round(parent.height * 0.22)

        width: Math.round(Theme.cellW * 64)
        height: header.height + list.height + footer.height + Theme.cellH

        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.accent

        // Klicks im Kasten sollen ihn nicht schliessen.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.8

            Text {
                id: prompt

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "> "
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            TextInput {
                id: input

                anchors.left: prompt.right
                anchors.right: counter.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                focus: true
                selectByMouse: true
                selectionColor: Theme.selection
                selectedTextColor: Theme.fg

                onTextChanged: {
                    root.selected = 0;
                    list.positionViewAtBeginning();
                }

                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onPressed: event => {
                    // Ctrl-N/P wie in jedem Terminalprogramm.
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_N) {
                            root.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_P) {
                            root.move(-1);
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Anwendung suchen, sonst Befehl ausfuehren"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            Text {
                id: counter

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.results.length + ""
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.borderWidth
                color: Theme.muted
            }
        }

        ListView {
            id: list

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            anchors.topMargin: Theme.cellH * 0.4

            // Feste Zeilenzahl statt einer Hoehe in Pixeln: der Kasten aendert
            // seine Groesse beim Tippen dann nicht.
            height: rowHeight * Math.min(12, Math.max(1, root.results.length))
            readonly property real rowHeight: Theme.cellH * 2.4

            clip: true
            model: root.results
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: list.rowHeight
                color: index === root.selected ? Theme.selection : "transparent"

                Text {
                    id: marker

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.index === root.selected ? "▸" : " "
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                // Das Symbol des Programms. Die einzige Stelle im Starter, die
                // nicht aus Zeichen besteht -- ohne sie sucht das Auge laenger.
                Item {
                    id: appIcon

                    anchors.left: marker.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Theme.cellH * 1.5)
                    height: width

                    readonly property string iconSource: Apps.iconFor(row.modelData)

                    IconImage {
                        anchors.fill: parent
                        visible: appIcon.iconSource !== ""
                        source: appIcon.iconSource
                    }

                    // Ersatz fuer Programme ohne Symbol: der erste Buchstabe in
                    // einem Kasten, wie ein Kuerzel.
                    Rectangle {
                        anchors.fill: parent
                        visible: appIcon.iconSource === ""
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: Theme.muted
                        radius: Theme.radius

                        Text {
                            anchors.centerIn: parent
                            text: (row.modelData.name || "?").charAt(0).toUpperCase()
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }
                    }
                }

                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: Theme.cellW
                    anchors.right: badge.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        width: parent.width
                        text: row.modelData.name
                        color: row.index === root.selected ? Theme.on(Theme.selection) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.modelData.genericName || row.modelData.comment || ""
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: badge

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.cellW / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.runInTerminal ? "TUI" : "APP"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selected = row.index
                    onClicked: root.accept()
                }
            }
        }

        Text {
            id: footer

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.4
            verticalAlignment: Text.AlignVCenter
            text: root.results.length > 0 ? "↑↓ waehlen · Enter starten · Esc schliessen" : (input.text === "" ? "keine Anwendungen gefunden" : "Enter fuehrt \"" + input.text + "\" als Befehl aus")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }
}
