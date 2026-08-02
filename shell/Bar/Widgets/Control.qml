import QtQuick
import Quickshell.Networking
import qs.Common
import qs.Services
import qs.Widgets

// Control Center: Helligkeit, WLAN, Bluetooth in einem Popout.
//
// Die Zelle in der Leiste zeigt schon das Wichtigste -- an welchem Netz man
// haengt. Ein reiner Knopf waere verschenkter Platz.
Cell {
    id: root

    interactive: true
    popoutTakesKeyboard: true
    text: Net.summary.length > 12 ? (Net.summary.substring(0, 11) + "…") : Net.summary
    color: Net.online ? Theme.fg : Theme.fgDim

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.controlOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onControlOpenChanged() {
            root.setPopout(Runtime.controlOpen);
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            // Welches Netz gerade nach einem Passwort fragt. Leer heisst: kein
            // Eingabefeld offen.
            property var pendingNetwork: null

            readonly property real rowWidth: 44 * Theme.cellW

            spacing: Theme.cellH * 0.4

            component Heading: Text {
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            // ── Helligkeit ────────────────────────────────────────────────

            Heading {
                text: "HELLIGKEIT"
                visible: Brightness.available
            }

            Row {
                spacing: Theme.cellW
                visible: Brightness.available

                LevelBar {
                    cells: 28
                    value: Brightness.percent
                    fillColor: Theme.yellow
                    onMoved: v => Brightness.set(v)
                }

                Text {
                    text: (Brightness.percent + "%").padStart(5, " ")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            // ── WLAN ──────────────────────────────────────────────────────

            Item {
                width: panel.rowWidth
                height: Theme.cellH

                Heading {
                    anchors.left: parent.left
                    text: "WLAN"
                }

                Text {
                    anchors.right: parent.right
                    text: Net.wifiEnabled ? "[ an ]" : "[ aus ]"
                    color: Net.wifiEnabled ? Theme.green : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.cellW / 2
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.setWifiEnabled(!Net.wifiEnabled)
                    }
                }
            }

            Repeater {
                model: Net.wifiEnabled ? Net.wifiNetworks.slice(0, 8) : []

                Column {
                    id: entry

                    required property var modelData

                    readonly property bool isCurrent: modelData.connected
                    readonly property bool asksPassword: panel.pendingNetwork === modelData

                    spacing: 0

                    Rectangle {
                        width: panel.rowWidth
                        height: Theme.cellH * 1.4
                        radius: Theme.radius
                        color: wifiMouse.containsMouse ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.right: strength.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: (entry.isCurrent ? "▸ " : "  ") + entry.modelData.name + (entry.modelData.known && !entry.isCurrent ? "  ·gespeichert" : "")
                            color: entry.isCurrent ? Theme.accent : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }

                        Text {
                            id: strength

                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (entry.modelData.security !== WifiSecurityType.Open ? "🔒 " : "   ") + Net.bars(entry.modelData.signalStrength)
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: wifiMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (entry.isCurrent) {
                                    Net.disconnect(entry.modelData);
                                    return;
                                }
                                if (Net.needsPassword(entry.modelData)) {
                                    panel.pendingNetwork = entry.modelData;
                                    return;
                                }
                                Net.connect(entry.modelData, "");
                            }
                        }
                    }

                    // Passwortzeile, nur fuer unbekannte verschluesselte Netze.
                    Rectangle {
                        width: panel.rowWidth
                        height: entry.asksPassword ? Theme.cellH * 1.6 : 0
                        visible: entry.asksPassword
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: Theme.accent

                        TextInput {
                            id: pskField

                            anchors.fill: parent
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.rightMargin: Theme.cellW / 2
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            echoMode: TextInput.Password
                            focus: entry.asksPassword
                            onAccepted: {
                                Net.connect(entry.modelData, text);
                                text = "";
                                panel.pendingNetwork = null;
                            }
                            Keys.onEscapePressed: {
                                text = "";
                                panel.pendingNetwork = null;
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pskField.text === ""
                                text: "Passwort, Enter verbindet"
                                color: Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }
            }

            // ── Bluetooth ─────────────────────────────────────────────────

            Item {
                width: panel.rowWidth
                height: Theme.cellH
                visible: Bt.available

                Heading {
                    anchors.left: parent.left
                    text: "BLUETOOTH"
                }

                Text {
                    anchors.right: parent.right
                    text: Bt.enabled ? "[ an ]" : "[ aus ]"
                    color: Bt.enabled ? Theme.green : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.cellW / 2
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Bt.setEnabled(!Bt.enabled)
                    }
                }
            }

            Repeater {
                model: Bt.enabled ? Bt.sorted.slice(0, 6) : []

                Rectangle {
                    id: btRow

                    required property var modelData

                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: btMouse.containsMouse ? Theme.selection : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: (btRow.modelData.connected ? "▸ " : "  ") + Bt.label(btRow.modelData) + (btRow.modelData.batteryAvailable ? ("  " + Math.round(btRow.modelData.battery * 100) + "%") : "") + (btRow.modelData.paired || btRow.modelData.connected ? "" : "  ·neu")
                        color: btRow.modelData.connected ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: btMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Bt.toggleDevice(btRow.modelData)
                    }
                }
            }
        }
    }
}
