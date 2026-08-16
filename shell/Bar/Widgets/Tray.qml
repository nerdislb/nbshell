import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// System-Tray.
//
// Die Symbole kommen von den Programmen selbst -- das ist die eine Stelle, an
// der eine Textoberflaeche nicht mit Text auskommt. Der Rahmen drumherum
// bleibt derselbe wie bei jedem anderen Baustein.
//
// Links startet, Mitte ist die zweite Aktion des Programms, rechts oeffnet
// dessen Menue. Genau das erwartet ein SNI-Programm.
//
// Eingeklappt steht nur ein schlichtes `>` da. Aufgeklappt wird es zu `<` --
// die Anzahl ist unwichtig, weil die Symbole selbst direkt daneben erscheinen.
// Der Zustand steht in der Config und ueberlebt damit den Neustart.
Cell {
    id: root

    // Welches Symbol gerade sein Menue zeigt. Der Anker des Popouts wandert
    // mit, damit es unter dem richtigen Symbol steht.
    property var menuItem: null
    property Item menuAnchor: null

    readonly property var items: SystemTray.items?.values ?? []

    readonly property bool expanded: Config.value("trayExpanded", false)

    shown: items.length > 0
    custom: true

    Row {
        spacing: Theme.cellW / 2

        // Der Pfeil zeigt zugleich Aktion und Zustand, ohne einen Zaehler.
        Line {
            id: toggle

            anchors.verticalCenter: parent.verticalCenter
            text: root.expanded ? "<" : ">"
            color: Theme.textDim

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Theme.cellW / 2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Config.set("trayExpanded", !root.expanded)
            }
        }

        Repeater {
            model: root.expanded ? root.items : []

            Item {
                id: entry

                required property var modelData

                width: Theme.cellH
                height: Theme.cellH

                IconImage {
                    id: icon

                    anchors.fill: parent
                    source: entry.modelData.icon
                    // Nicht abschalten, wenn das Programm "passiv" meldet --
                    // nur blasser: verschwundene Symbole verwirren mehr, als
                    // sie Platz sparen.
                    opacity: entry.modelData.status === Status.Passive ? 0.5 : 1
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onClicked: mouseEvent => {
                        const item = entry.modelData;
                        if (mouseEvent.button === Qt.RightButton || item.onlyMenu) {
                            if (!item.hasMenu)
                                return;
                            // Dasselbe Symbol noch einmal schliesst das Menue.
                            if (menuPopout.visible && root.menuItem === item) {
                                menuPopout.visible = false;
                                return;
                            }
                            root.menuItem = item;
                            root.menuAnchor = entry;
                            menuPopout.visible = true;
                            return;
                        }
                        if (mouseEvent.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                            return;
                        }
                        item.activate();
                    }

                    onWheel: wheelEvent => entry.modelData.scroll(wheelEvent.angleDelta.y, false)
                }
            }
        }
    }

    // Ein Popout fuer alle Symbole: es haengt jeweils an dem, das zuletzt
    // angeklickt wurde.
    Popout {
        id: menuPopout

        anchorItem: root.menuAnchor ?? root
        takesKeyboard: false
        contentComponent: menuComponent
    }

    Component {
        id: menuComponent

        Column {
            spacing: Theme.cellH * 0.3

            Line {
                text: root.menuItem?.title || root.menuItem?.id || ""
                color: Theme.fgDim
            }

            MenuView {
                handle: root.menuItem?.menu ?? null
                dismiss: () => {
                    menuPopout.visible = false;
                }
            }
        }
    }
}
