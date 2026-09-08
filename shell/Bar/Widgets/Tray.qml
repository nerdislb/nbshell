import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
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
    readonly property real itemExtent: Theme.barIconSlot + Theme.barItemPadding * 2

    function isSymbolic(source) {
        // Preserve Quickshell's resolved URL, including fallback theme paths.
        // Only named symbolic icons opt into recoloring; app artwork stays intact.
        return String(source || "").split("?")[0].endsWith("-symbolic");
    }

    shown: items.length > 0
    custom: true

    Row {
        spacing: 0

        // Der Pfeil zeigt zugleich Aktion und Zustand, ohne einen Zaehler.
        Item {
            id: toggle
            width: root.itemExtent
            height: root.implicitHeight

            Line {
                anchors.centerIn: parent
                text: root.expanded ? "<" : ">"
                color: Theme.textDim
            }

            MouseArea {
                anchors.fill: parent
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

                width: root.itemExtent
                height: root.implicitHeight

                Item {
                    id: icon

                    anchors.centerIn: parent
                    width: Theme.barIconHeight
                    height: width
                    readonly property bool symbolic: root.isSymbolic(entry.modelData.icon)
                    // Nicht abschalten, wenn das Programm "passiv" meldet --
                    // nur blasser: verschwundene Symbole verwirren mehr, als
                    // sie Platz sparen.
                    opacity: entry.modelData.status === Status.Passive ? 0.5 : 1

                    Image {
                        id: artwork
                        anchors.fill: parent
                        source: entry.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                        visible: !icon.symbolic
                        layer.enabled: icon.symbolic
                    }

                    MultiEffect {
                        anchors.fill: artwork
                        source: artwork
                        visible: icon.symbolic
                        colorization: 1
                        colorizationColor: root.shownColor
                    }
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
                                menuPopout.close();
                                return;
                            }
                            root.menuItem = item;
                            root.menuAnchor = entry;
                            menuPopout.open();
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
        takesKeyboard: true
        contentComponent: menuComponent
    }

    Component {
        id: menuComponent

        Column {
            id: content
            readonly property Item initialFocusItem: menu.initialFocusItem
            spacing: Theme.cellH * 0.3

            Line {
                text: root.menuItem?.title || root.menuItem?.id || ""
                color: Theme.fgDim
            }

            MenuView {
                id: menu
                handle: root.menuItem?.menu ?? null
                dismiss: () => {
                    menuPopout.close();
                }
            }
        }
    }
}
