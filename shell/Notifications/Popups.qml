import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Common
import qs.Services

// Die Karten, die bei einer neuen Benachrichtigung aufgehen.
//
// Sie stehen gegenueber der Leiste am rechten Rand, gestapelt, neueste oben.
// Jede laeuft nach `notifyTimeout` von selbst ab; dringende bleiben stehen,
// bis man sie wegklickt -- so, wie es die Spezifikation vorsieht.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        readonly property bool atTop: Config.edge !== "top"

        screen: modelData
        visible: Notify.popups.length > 0
        color: "transparent"

        WlrLayershell.namespace: "nbshell:notifications"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors.right: true
        anchors.top: atTop
        anchors.bottom: !atTop

        implicitWidth: Theme.cellW * 52
        implicitHeight: Math.min(screen.height * 0.8, stack.implicitHeight + Theme.cellH * 4)

        // Nur die Karten nehmen Klicks an, der Rest des Streifens nicht.
        mask: Region {
            item: stack
        }

        Column {
            id: stack

            anchors.right: parent.right
            anchors.top: win.atTop ? parent.top : undefined
            anchors.bottom: win.atTop ? undefined : parent.bottom
            anchors.margins: Theme.cellH

            spacing: Theme.cellH * 0.5

            Repeater {
                model: Notify.popups

                Rectangle {
                    id: card

                    required property var modelData

                    readonly property var n: modelData.notification
                    readonly property bool urgent: n?.urgency === NotificationUrgency.Critical

                    width: Theme.cellW * 48
                    height: body.implicitHeight + Theme.cellH

                    color: Theme.bg
                    radius: Theme.radius
                    border.width: Theme.borderWidth
                    border.color: card.urgent ? Theme.red : Theme.muted

                    // Dringendes bleibt stehen, bis es jemand wegklickt.
                    Timer {
                        interval: Notify.popupTimeout
                        running: !card.urgent && !hover.hovered
                        onTriggered: Notify.dismissPopup(card.modelData)
                    }

                    HoverHandler {
                        id: hover
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.cellW
                        spacing: Theme.cellH * 0.2

                        Text {
                            width: parent.width
                            text: (card.urgent ? "! " : "") + (card.n?.appName || "System") + "  ·  " + Notify.ago(card.modelData.time)
                            color: card.urgent ? Theme.red : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: card.n?.summary ?? ""
                            color: Theme.fgBright
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: text !== ""
                            // Der Text darf Auszeichnung enthalten; als
                            // RichText gelesen bleibt <b> ein Fettdruck statt
                            // sichtbarer Klammern.
                            text: card.n?.body ?? ""
                            textFormat: Text.RichText
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: Theme.cellW
                            visible: (card.n?.actions?.length ?? 0) > 0

                            Repeater {
                                model: card.n?.actions ?? []

                                Rectangle {
                                    id: actionButton

                                    required property var modelData

                                    width: actionText.implicitWidth + Theme.cellW * 2
                                    height: Theme.cellH * 1.4
                                    radius: Theme.radius
                                    color: actionMouse.containsMouse ? Theme.selection : "transparent"
                                    border.width: Theme.borderWidth
                                    border.color: Theme.muted

                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: actionButton.modelData.text
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        renderType: Text.NativeRendering
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Notify.invoke(card.modelData, actionButton.modelData)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // Unter den Knoepfen: die sollen zuerst drankommen.
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouseEvent => {
                            if (mouseEvent.button === Qt.RightButton)
                                Notify.drop(card.modelData);
                            else
                                Notify.dismissPopup(card.modelData);
                        }
                    }
                }
            }
        }
    }
}
