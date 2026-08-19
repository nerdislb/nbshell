import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    shown: true
    quiet: WhatsApp.unread === 0 && WhatsApp.ready
    slotChars: 2
    interactive: true
    popoutTakesKeyboard: true
    label: "WA"
    icon: String.fromCodePoint(0xf232)
    text: WhatsApp.unread > 0 ? String(WhatsApp.unread) : ""
    color: WhatsApp.unread > 0 ? Theme.green : (WhatsApp.ready ? Theme.barAccent : Theme.textDim)
    onRightClicked: WhatsApp.openWeb()

    popout: Component {
        Column {
            id: panel
            property var closePopout: null
            property string draft: ""
            readonly property real rowWidth: 58 * Theme.cellW
            spacing: Theme.cellH * 0.25

            function submit() {
                if (WhatsApp.sendText(composer.text)) {
                    composer.text = "";
                    panel.draft = "";
                    composer.forceActiveFocus();
                }
            }

            PanelHead {
                rowWidth: panel.rowWidth
                icon: root.icon
                title: WhatsApp.currentChat ? WhatsApp.currentChat.name : "WhatsApp"
                subtitle: WhatsApp.ready ? "Messages · right-click opens the web app" : (WhatsApp.online ? "Bridge ready" : "Bridge not installed")
                badge: WhatsApp.unread > 0 ? String(WhatsApp.unread) : (WhatsApp.ready ? "online" : "offline")
                badgeColor: WhatsApp.ready ? Theme.green : Theme.fgDim
            }

            ActionButton {
                visible: !WhatsApp.online
                width: panel.rowWidth
                text: "Install and start bridge"
                tone: "primary"
                onTriggered: WhatsApp.setup()
            }

            Column {
                visible: WhatsApp.online && !WhatsApp.linked
                width: panel.rowWidth
                spacing: Theme.cellH * 0.25
                Line { text: "Connect this nbshell as a linked device."; color: Theme.fg }
                ActionButton {
                    width: panel.rowWidth
                    text: WhatsApp.hasQr ? "Refresh QR code" : "Connect device"
                    tone: "primary"
                    onTriggered: WhatsApp.beginLogin()
                }
                Image {
                    visible: WhatsApp.hasQr && WhatsApp.qrPng !== ""
                    width: 30 * Theme.cellW; height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: visible ? "file://" + WhatsApp.qrPng : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }
                Line { visible: WhatsApp.hasQr; text: "Phone: WhatsApp → Linked devices → Link a device"; color: Theme.fgDim }
            }

            Row {
                visible: WhatsApp.ready
                spacing: Theme.cellW

                Column {
                    width: 22 * Theme.cellW
                    spacing: 1
                    Rule { rowWidth: parent.width; label: "CHATS" }
                    Repeater {
                        // Acht Zeilen passen auch mit Kopf und Composer sicher
                        // unter eine obere Bar. PopupWindow begrenzt zwar sein
                        // Fenster am Bildschirmrand, Kinder wuerden ohne diese
                        // Grenze aber einfach ueber den Rahmen weitermalen.
                        model: WhatsApp.chats.slice(0, 8)
                        Rectangle {
                            id: chatRow
                            required property var modelData
                            width: 22 * Theme.cellW; height: Theme.cellH * 2.3
                            clip: true
                            color: WhatsApp.currentJid === modelData.jid ? Theme.selectedSurface() : (chatHover.hovered ? Theme.hover : "transparent")
                            Column {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                Line { width: parent.width; text: (chatRow.modelData.unread > 0 ? chatRow.modelData.unread + "  " : "") + chatRow.modelData.name; color: chatRow.modelData.unread > 0 ? Theme.fgBright : Theme.fg; elide: Text.ElideRight; maximumLineCount: 1 }
                                Line { width: parent.width; text: chatRow.modelData.lastText || ""; color: Theme.fgDim; elide: Text.ElideRight; maximumLineCount: 1 }
                            }
                            HoverHandler { id: chatHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: WhatsApp.selectChat(chatRow.modelData.jid) }
                        }
                    }
                }

                Column {
                    width: 35 * Theme.cellW
                    spacing: Theme.cellH * 0.15
                    Rule { rowWidth: parent.width; label: WhatsApp.currentChat ? "VERLAUF" : "NACHRICHTEN" }
                    Line { visible: WhatsApp.currentJid === ""; text: "Select a chat on the left"; color: Theme.muted }
                    Repeater {
                        model: WhatsApp.messages.slice(-6)
                        Line {
                            required property var modelData
                            width: 35 * Theme.cellW
                            text: (modelData.fromMe ? "> " : "< ") + (modelData.text || "Media")
                            color: modelData.fromMe ? Theme.accent : Theme.fg
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        visible: WhatsApp.currentJid !== ""
                        width: 35 * Theme.cellW
                        height: Theme.cellH * 1.8
                        spacing: Theme.cellW

                        // Das Popup besitzt bereits den Wayland-Keyboard-Grab,
                        // aber niri reicht einen normalen TextInput-Klick nicht
                        // in jedem Fall als aktiven Item-Fokus weiter. Sobald
                        // nach der Chatwahl der Composer sichtbar wird, holen
                        // wir ihn deshalb explizit nach dem Layout-Durchlauf.
                        onVisibleChanged: if (visible)
                            Qt.callLater(() => composer.forceActiveFocus())

                        Rectangle {
                            width: 27 * Theme.cellW
                            height: parent.height
                            color: Theme.alpha(Theme.fg, 0.04)
                            border.width: Theme.borderWidth
                            border.color: composer.activeFocus ? Theme.accent : Theme.fgDim
                            radius: Theme.radius

                            TextInput {
                                id: composer
                                anchors.fill: parent; anchors.margins: Theme.cellW * 0.6
                                color: Theme.fg; selectionColor: Theme.selection
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                activeFocusOnPress: true
                                text: panel.draft
                                onTextChanged: panel.draft = text
                                onAccepted: panel.submit()

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: composer.forceActiveFocus()
                                }
                            }
                        }

                        Rectangle {
                            width: 7 * Theme.cellW
                            height: parent.height
                            color: sendHover.hovered ? Theme.hover : "transparent"
                            border.width: Theme.borderWidth
                            border.color: panel.draft.trim() !== "" ? Theme.accent : Theme.fgDim
                            radius: Theme.radius

                            Line {
                                anchors.centerIn: parent
                                text: "send"
                                color: panel.draft.trim() !== "" ? Theme.accent : Theme.muted
                            }
                            HoverHandler {
                                id: sendHover
                                cursorShape: panel.draft.trim() !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                            TapHandler {
                                enabled: panel.draft.trim() !== ""
                                onTapped: panel.submit()
                            }
                        }
                    }
                    Line { visible: WhatsApp.currentJid !== ""; text: "Enter or send · right-click WA to open Brave"; color: Theme.muted }
                }
            }
        }
    }
}
