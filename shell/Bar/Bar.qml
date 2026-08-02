import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// Die Leiste -- je nach Betriebsart eine freistehende Insel oder ein
// durchgehender Balken. Ein Fenster je Bildschirm.
//
// Beide Arten sind dasselbe Fenster: es ist immer bildschirmbreit und
// durchsichtig, und nur der Rahmen darin waechst. Ein Layer-Surface bei jedem
// Animationsschritt neu zu vermessen waere unruhig; eine Maske haelt die
// durchsichtige Flaeche derweil klickdurchlaessig.
//
// Der Unterschied zwischen Insel und Balken ist damit fast nur Geometrie:
//
//   Insel   Rahmen so breit wie sein Inhalt, schwebt (exclusiveZone -1),
//           faehrt beim Ueberfahren auf und zeigt dann alle drei Gruppen.
//   Balken  Rahmen ueber die volle Breite, schiebt die Fenster weg
//           (exclusiveZone), Gruppen links/mitte/rechts.
//
// Die drei Gruppen gibt es in beiden Faellen nur EINMAL. Statt sie je nach
// Betriebsart neu zu bauen, sitzen sie in einer Reihe, deren zwei Zwischen-
// raeume ihre Breite wechseln: im Balken so, dass die Mitte wirklich mittig
// steht, in der Insel auf einen Zeichenabstand.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        readonly property bool barMode: Config.mode === "bar"
        readonly property bool atBottom: Config.edge === "bottom"
        readonly property bool expanded: barMode || Runtime.islandOpen || hovering
        property bool hovering: false

        screen: modelData
        color: "transparent"

        WlrLayershell.namespace: "nbshell:bar"
        WlrLayershell.layer: WlrLayershell.Top

        // Nur solange ein Popout offen ist: sonst zoege ein Klick auf die
        // Leiste dem Fenster darunter staendig die Tastatur weg.
        WlrLayershell.keyboardFocus: (Runtime.popoutCount > 0 || Runtime.popoutHover > 0) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.left: true
        anchors.right: true
        anchors.top: !atBottom
        anchors.bottom: atBottom

        implicitHeight: Theme.barHeight + (barMode ? 0 : Config.gap)

        // Im Balkenmodus reserviert die Leiste ihren Platz, die Fenster ruecken
        // also nach. Als Insel schwebt sie darueber.
        exclusiveZone: barMode ? Theme.barHeight : -1

        mask: Region {
            item: frame
        }

        Timer {
            id: collapseTimer
            interval: Config.collapseDelay
            onTriggered: win.hovering = false
        }

        Rectangle {
            id: frame

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: win.atBottom ? undefined : parent.top
            anchors.bottom: win.atBottom ? parent.bottom : undefined
            anchors.topMargin: win.atBottom ? 0 : (win.barMode ? 0 : Config.gap)
            anchors.bottomMargin: win.atBottom ? (win.barMode ? 0 : Config.gap) : 0

            height: Theme.barHeight
            width: {
                if (win.barMode)
                    return win.width;
                const inner = win.expanded ? content.implicitWidth : collapsed.implicitWidth;
                return Math.min(win.width, inner + Theme.padX * 2);
            }

            radius: win.barMode ? 0 : Theme.radius
            color: Theme.alpha(Theme.bg, Config.opacity)
            border.width: Theme.borderWidth
            border.color: Theme.muted

            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        collapseTimer.stop();
                        win.hovering = true;
                    } else {
                        collapseTimer.restart();
                    }
                }
            }

            // Zugeklappte Insel. Beide Zustaende werden ueberblendet, nicht
            // ueber `visible` geschaltet: ein unsichtbarer Positionierer meldet
            // keine brauchbare implicitWidth mehr -- und genau die braucht der
            // Rahmen oben, um seine Zielbreite zu kennen.
            Row {
                id: collapsed

                anchors.centerIn: parent
                spacing: Theme.gap
                opacity: win.expanded ? 0 : 1
                enabled: !win.expanded

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }

                Repeater {
                    model: Config.collapsedWidgets

                    WidgetHost {
                        required property var modelData
                        widgetName: modelData
                        screenName: win.modelData?.name ?? ""
                    }
                }
            }

            Row {
                id: content

                anchors.verticalCenter: parent.verticalCenter
                x: win.barMode ? Theme.padX : (parent.width - width) / 2
                spacing: 0
                opacity: win.expanded ? 1 : 0
                enabled: win.expanded

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }

                // Im Balken muessen die Zwischenraeume so breit sein, dass die
                // Mittelgruppe wirklich in der Bildschirmmitte steht -- und
                // nicht dort, wo sie nach zwei gleich grossen Luecken landet.
                readonly property real free: frame.width - Theme.padX * 2 - leftGroup.implicitWidth - centerGroup.implicitWidth - rightGroup.implicitWidth
                readonly property real barLeftGap: Math.max(Theme.gap, free / 2 - (leftGroup.implicitWidth - rightGroup.implicitWidth) / 2)
                readonly property real barRightGap: Math.max(Theme.gap, free - barLeftGap)

                Row {
                    id: leftGroup
                    spacing: Theme.gap

                    Repeater {
                        model: Config.leftWidgets

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }
                }

                Item {
                    width: win.barMode ? content.barLeftGap : Theme.gap
                    height: 1
                }

                Row {
                    id: centerGroup
                    spacing: Theme.gap

                    Repeater {
                        model: Config.centerWidgets

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }
                }

                Item {
                    width: win.barMode ? content.barRightGap : Theme.gap
                    height: 1
                }

                Row {
                    id: rightGroup
                    spacing: Theme.gap

                    Repeater {
                        model: Config.rightWidgets

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }
                }
            }
        }
    }
}
