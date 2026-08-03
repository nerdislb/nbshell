import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Themewahl. Die Zelle zeigt den Namen des aktiven Themes; ein Klick klappt
// die Liste auf, das Mausrad blaettert direkt durch.
Cell {
    id: root

    icon: Icons.palette
    text: Config.theme
    color: Theme.accent
    interactive: true

    onWheel: delta => ThemeIndex.step(delta > 0 ? -1 : 1)

    // Nicht als Bindung: ein Klick auf die Zelle schaltet dasselbe Popout, und
    // eine Bindung wuerde ihn beim naechsten Mal ueberschreiben.
    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.themePickerOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onThemePickerOpenChanged() {
            root.setPopout(Runtime.themePickerOpen);
        }
    }

    popout: Component {
        Column {
            id: picker

            // Wird vom Popout gesetzt, siehe Widgets/Popout.qml.
            property var closePopout: null

            // Ein Positionierer rechnet seine implizite Groesse selbst aus --
            // sie zu setzen ist ein Fehler ("read-only property"). Die Breite
            // steht deshalb als eigene Zahl da und geht an die Zeilen.
            readonly property real rowWidth: 34 * Theme.cellW

            spacing: Theme.cellH * 0.3

            Text {
                id: header
                text: "THEMES  (" + ThemeIndex.list.length + ")"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: ThemeIndex.list

                Rectangle {
                    id: row

                    required property var modelData

                    readonly property bool isCurrent: modelData.name === Config.theme

                    width: picker.rowWidth
                    height: Theme.cellH * 1.5
                    radius: Theme.radius
                    color: mouse.hovered ? Theme.hover : "transparent"
                    border.width: row.isCurrent ? Theme.borderWidth : 0
                    border.color: Theme.accent

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        // Der Zeiger markiert das aktive Theme -- so, wie eine
                        // Auswahl im Terminal aussieht.
                        text: (row.isCurrent ? "▸ " : "  ") + row.modelData.name
                        color: row.isCurrent ? Theme.readable(Theme.accent, Theme.bg) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }

                    // Farbprobe: dieselben fuenf Farben, die auch das Terminal
                    // zeigt. Damit sieht man vor dem Wechseln, was kommt.
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Repeater {
                            model: [row.modelData.background, row.modelData.accent, row.modelData.red, row.modelData.green, row.modelData.yellow]

                            Rectangle {
                                required property var modelData
                                width: Theme.cellW * 1.6
                                height: Theme.cellH * 0.8
                                color: modelData || "transparent"
                                border.width: 1
                                border.color: Theme.muted
                            }
                        }
                    }

                    HoverHandler {
                        id: mouse

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            ThemeIndex.apply(row.modelData.name);
                            if (picker.closePopout)
                                picker.closePopout();
                        }
                    }
                }
            }
        }
    }
}
