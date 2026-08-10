import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Themewahl. Die Zelle zeigt den Namen des aktiven Themes; ein Klick klappt
// die Liste auf, das Mausrad blaettert direkt durch.
Cell {
    id: root

    icon: Icons.palette
    // Wie beim Netz: das Symbol reicht, der Name steht in der Liste.
    text: Config.widgetIcons ? "" : Config.theme
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

            // Welches Theme die Vorschau gerade zeigt. Ohne Maus auf einer
            // Zeile ist das das aktive -- so steht dort nie ein leeres Feld,
            // und man sieht beim Aufklappen, womit man vergleicht.
            property string previewName: Config.theme

            readonly property var previewTheme: ThemeIndex.byName(picker.previewName) ?? ThemeIndex.current

            spacing: Theme.cellH * 0.3

            // Der Name des aktiven Themes ist die Sache, "Theme" der
            // Zusammenhang; die Anzahl steht als Marke daneben, statt in
            // Klammern hinter einer Ueberschrift zu verschwinden.
            PanelHead {
                id: header

                rowWidth: picker.rowWidth
                icon: Icons.palette
                title: picker.previewName
                subtitle: picker.previewName === Config.theme ? "Theme · aktiv" : "Theme · Vorschau"
                badge: String(ThemeIndex.list.length)
            }

            // Die Vorschau steht OBEN und nicht bei der Zeile: sie bleibt
            // damit an derselben Stelle, waehrend die Maus durch die Liste
            // faehrt. Wanderte sie mit, muesste das Auge ihr folgen, statt
            // die Farben zu vergleichen.
            ThemePreview {
                rowWidth: picker.rowWidth
                theme: picker.previewTheme
            }

            // ── Der Akzent ───────────────────────────────────────────────
            // Gewaehlt wird eine ROLLE, keine Farbe: die Kaestchen zeigen, wie
            // sie im AKTIVEN Theme aussieht, und nach einem Themewechsel
            // dieselbe Rolle im neuen. Nachgebaut nach Shibumi-Shell, wo die
            // Reihe `Auto 01 … 08 FG` heisst.
            Item {
                width: picker.rowWidth
                height: Theme.cellH * 1.2

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AKZENT"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.accentRole
                    color: Theme.readable(Theme.accent, Theme.bg)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            Row {
                spacing: Theme.cellW * 0.4

                Repeater {
                    model: Theme.accentRoles

                    Rectangle {
                        id: swatch

                        required property var modelData

                        readonly property bool active: swatch.modelData === Theme.accentRole

                        width: (picker.rowWidth - Theme.cellW * 0.4 * (Theme.accentRoles.length - 1)) / Theme.accentRoles.length
                        height: Theme.cellH * 1.2
                        color: Theme.roleColor(swatch.modelData)
                        radius: Theme.radius

                        // Das aktive Feld bekommt einen Ring in der Schriftfarbe,
                        // nicht im Akzent: der IST ja die Fuellung, und ein Ring
                        // in derselben Farbe waere unsichtbar.
                        border.width: swatch.active ? Math.max(2, Theme.borderWidth * 2) : Theme.borderWidth
                        border.color: swatch.active ? Theme.fgBright : Theme.muted

                        // "theme" ist keine eigene Farbe, sondern ein Verweis --
                        // der Punkt sagt, dass hier das Theme entscheidet.
                        Text {
                            anchors.centerIn: parent
                            visible: swatch.modelData === "theme"
                            text: "·"
                            color: Theme.on(Theme.roleColor("theme"))
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: Config.set("accent", swatch.modelData)
                        }
                    }
                }
            }

            Rule {
                rowWidth: picker.rowWidth
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

                        // Beim Verlassen zurueck auf das aktive Theme, nicht
                        // auf die zuletzt beruehrte Zeile: sonst behauptet die
                        // Kopfzeile weiter "Vorschau", obwohl die Maus laengst
                        // woanders ist.
                        onHoveredChanged: picker.previewName = mouse.hovered ? row.modelData.name : Config.theme
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
