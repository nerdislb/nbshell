import QtQuick
import Quickshell
import Quickshell.Io
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

    // Kabel schlaegt Funk: haengt beides, ist das Kabel die Verbindung, ueber
    // die es laeuft.
    icon: Net.wiredConnected ? Icons.lan
        : (Net.activeWifi ? Icons.wifiSignal(Net.activeWifi.signalStrength)
            : (Net.wifiEnabled ? Icons.wifiDisconnected : Icons.wifiOff))
    // Der Netzname stand frueher daneben. Das Symbol sagt schon, ob und
    // wie man haengt -- im Popout steht der Name ohnehin. Ohne Symbole
    // bleibt er, sonst waere die Zelle leer.
    label: "NET"
    text: Config.widgetIcons ? "" : (Net.summary.length > 12 ? (Net.summary.substring(0, 11) + "…") : Net.summary)
    color: Net.online ? Theme.text : Theme.textDim

    preview: Component {
        BarPreview {
            icon: root.icon
            title: Net.summary
            subtitle: Net.activeWifi ? "Wi-Fi" : (Net.wiredConnected ? "Wired network" : "Offline")
            badge: Net.activeWifi ? Net.percentOf(Net.activeWifi.signalStrength) + " %" : (Net.wiredConnected ? "LAN" : "")
            badgeColor: Net.online ? Theme.green : Theme.fgDim
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Brightness", "value": Brightness.available ? Brightness.percent + " %" : "unavailable" },
                        { "label": "Bluetooth", "value": Bt.connected.length + " connected" },
                        { "label": "Wi-Fi", "value": Net.wifiEnabled ? "enabled" : "disabled", "color": Net.wifiEnabled ? Theme.fg : Theme.yellow },
                        { "label": "VPN", "value": Net.activeVpns.length ? Net.activeVpns[0].name : "disconnected", "color": Net.activeVpns.length ? Theme.green : Theme.fgDim }
                    ]
                }
            ]
        }
    }

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.controlOpen = root.popoutVisible

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            // Welches Netz gerade nach einem Passwort fragt. Leer heisst: kein
            // Eingabefeld open.
            property var pendingNetwork: null
            property string pendingBtRemoval: ""

            readonly property real rowWidth: 44 * Theme.cellW
            readonly property Item initialFocusItem: wifiRepeater.count > 0
                ? wifiRepeater.itemAt(0).focusTarget
                : (vpnRepeater.count > 0 ? vpnRepeater.itemAt(0)
                    : (btRepeater.count > 0 ? btRepeater.itemAt(0) : null))

            spacing: Theme.cellH * 0.4

            // Solange die Liste open ist, darf sich das WLAN auffrischen --
            // sonst steht dort, was beim letzten Blick zufaellig in der Luft
            // lag. Beim Zugehen geht beides wieder aus: der Scanner kostet
            // Strom, und eine laufende Bluetooth-Suche laesst obendrein
            // Kopfhoerer stottern.
            Component.onCompleted: {
                Net.setScanner(true);
                Net.setTrafficMonitoring(true);
                Net.refreshVpns();
            }
            Component.onDestruction: {
                Net.setScanner(false);
                Net.setTrafficMonitoring(false);
                Bt.scan(false);
            }

            // Laufendes Licht fuer die Suche. `-\|/` gibt es in jeder Schrift
            // -- Braille-Punkte oder Viertelbloecke fehlen manchen Nerd-Fonts,
            // und ein Kaestchen als Anzeige waere albern.
            property int spinIndex: 0
            readonly property string spin: "-\\|/".charAt(spinIndex % 4)

            Timer {
                interval: 150
                repeat: true
                running: Net.scanning || Bt.discovering || Net.vpnBusyUuid !== ""
                onTriggered: panel.spinIndex++
            }

            component Heading: Line {
                color: Theme.fgDim
            }

            component Action: ActionButton {
                property bool on: false
                compact: true
                tone: on ? "primary" : "secondary"
                accentColor: on ? Theme.green : Theme.accent
            }

            // Woran der Rechner haengt, steht jetzt OBEN und nicht mehr
            // irgendwo in der Netzliste: die Kopfzeile nennt die Sache, der
            // Untertitel den Zusammenhang, die Marke rechts die eine Zahl.
            // Abgeschaut bei Omarchys Netz-Panel.
            PanelHead {
                rowWidth: panel.rowWidth
                icon: Net.online ? (Net.activeWifi ? Icons.wifiSignal(Net.activeWifi.signalStrength) : Icons.lan) : Icons.wifiOff
                title: Net.summary
                subtitle: Net.activeWifi ? "Wi-Fi" : (Net.wiredConnected ? "Wired" : "not connected")
                badge: Net.activeWifi ? (Net.percentOf(Net.activeWifi.signalStrength) + " %") : (Net.wiredConnected ? "LAN" : "")
                badgeColor: Net.online ? Theme.green : Theme.fgDim
            }

            Facts {
                rowWidth: panel.rowWidth
                visible: Net.activeWifi !== null
                pairs: Net.activeWifi ? [
                    {
                        "label": "Signal",
                        "value": Net.bars(Net.activeWifi.signalStrength)
                    },
                    {
                        "label": "Security",
                        "value": Net.activeWifi.security !== WifiSecurityType.Open ? "secured" : "open",
                        "color": Net.activeWifi.security !== WifiSecurityType.Open ? Theme.fg : Theme.yellow
                    }
                ] : []
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "TRAFFIC" + (Net.trafficInterface !== "" ? (" · " + Net.trafficInterface) : "")
                visible: Net.online
            }

            Row {
                spacing: Theme.cellW
                visible: Net.online

                Line {
                    width: 10 * Theme.cellW
                    text: "↓ DOWNLOAD"
                    color: Theme.cyan
                }

                LevelBar {
                    cells: 21
                    value: Net.rateLevel(Net.downloadBps)
                    fillColor: Theme.cyan
                    interactive: false
                }

                Line {
                    width: 11 * Theme.cellW
                    horizontalAlignment: Text.AlignRight
                    text: Net.formatRate(Net.downloadBps)
                    color: Theme.fg
                }
            }

            Row {
                spacing: Theme.cellW
                visible: Net.online

                Line {
                    width: 10 * Theme.cellW
                    text: "↑ UPLOAD"
                    color: Theme.green
                }

                LevelBar {
                    cells: 21
                    value: Net.rateLevel(Net.uploadBps)
                    fillColor: Theme.green
                    interactive: false
                }

                Line {
                    width: 11 * Theme.cellW
                    horizontalAlignment: Text.AlignRight
                    text: Net.formatRate(Net.uploadBps)
                    color: Theme.fg
                }
            }

            // ── Helligkeit ────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                label: "BRIGHTNESS"
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

                Line {
                    text: (Brightness.percent + "%").padStart(5, " ")
                    color: Theme.fg
                }

                Action {
                    text: "Displays"
                    onTriggered: {
                        Runtime.displayOpen = true;
                        if (panel.closePopout)
                            panel.closePopout();
                    }
                }
            }

            // ── WLAN ──────────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                label: ""
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 2.4

                Heading {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: "WI-FI"
                }

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: Theme.cellW

                    // Beide oeffnen ein FENSTER, kein Popout: ein Popout
                    // klappt zu, sobald die Maus es verlaesst -- und genau das
                    // tut man, wenn man zum Telefon greift oder eine halbe
                    // Minute auf eine Messung wartet.
                    Action {
                        visible: Net.online
                        text: "Speedtest"
                        onTriggered: {
                            Runtime.speedOpen = true;
                            if (panel.closePopout)
                                panel.closePopout();
                        }
                    }

                    Action {
                        visible: Net.activeWifi !== null
                        text: "WI-FI QR"
                        onTriggered: {
                            Runtime.qrOpen = true;
                            if (panel.closePopout)
                                panel.closePopout();
                        }
                    }

                    Action {
                        visible: Net.wifiEnabled
                        text: Net.scanning ? (panel.spin + " scanning") : "Scan"
                        busy: Net.scanning
                        onTriggered: Net.rescan()
                    }

                    Action {
                        on: Net.wifiEnabled
                        text: Net.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                        onTriggered: Net.setWifiEnabled(!Net.wifiEnabled)
                    }
                }
            }

            // Leere Liste heisst nicht "kaputt" -- meistens heisst es, dass
            // noch niemand gesucht hat.
            Line {
                visible: Net.wifiEnabled && Net.wifiNetworks.length === 0
                text: Net.scanning ? "  scanning …" : "  nothing found"
                color: Theme.fgDim
            }

            Repeater {
                id: wifiRepeater
                model: Net.wifiEnabled ? Net.wifiNetworks.slice(0, 8) : []

                Column {
                    id: entry

                    required property var modelData

                    readonly property bool isCurrent: modelData.connected
                    readonly property bool asksPassword: panel.pendingNetwork === modelData
                    readonly property Item focusTarget: wifiRow

                    spacing: 0

                    PanelRow {
                        id: wifiRow

                        width: panel.rowWidth
                        height: Theme.denseRowHeight
                        interactive: true
                        selected: entry.isCurrent
                        title: (entry.isCurrent ? "▸ " : "  ") + entry.modelData.name
                            + (entry.modelData.known && !entry.isCurrent ? "  ·saved" : "")
                        value: (entry.modelData.security !== WifiSecurityType.Open ? "🔒 " : "   ")
                            + Net.bars(entry.modelData.signalStrength)
                        contentLeftPadding: Theme.cellW / 2
                        accessibleName: entry.modelData.name
                        accessibleDescription: (entry.modelData.security !== WifiSecurityType.Open ? "Secured" : "Open")
                            + "; signal " + Net.bars(entry.modelData.signalStrength)
                        onTriggered: {
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

                    // Passwortzeile, nur fuer unbekannte verschluesselte Netze.
                    Rectangle {
                        width: panel.rowWidth
                        height: entry.asksPassword ? Theme.cellH * 1.6 : 0
                        visible: entry.asksPassword
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: Theme.accent

                        TextField {
                            id: pskField

                            anchors.fill: parent
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.rightMargin: Theme.cellW / 2
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            background: null
                            horizontalPadding: 0
                            password: true
                            accessibleName: "Wi-Fi password"
                            accessibleDescription: "Enter connects to " + String(entry.modelData.ssid ?? entry.modelData.name ?? "the selected network")
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

                            Line {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: pskField.text === ""
                                text: "Password, Enter connects"
                                color: Theme.fgDim
                            }
                        }
                    }
                }
            }

            // ── VPN ──────────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                visible: Net.vpnAvailable
                label: ""
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH
                visible: Net.vpnAvailable

                Heading {
                    anchors.left: parent.left
                    text: "VPN"
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Action {
                        text: "Refresh"
                        onTriggered: Net.refreshVpns()
                    }
                }
            }

            Line {
                width: panel.rowWidth
                visible: Net.vpnAvailable && Net.vpnProfiles.length === 0
                text: "  no saved VPN profiles"
                color: Theme.fgDim
            }

            Repeater {
                id: vpnRepeater
                model: Net.vpnAvailable ? Net.vpnProfiles : []

                PanelRow {
                    id: vpnRow

                    required property var modelData

                    readonly property bool busy: Net.vpnBusyUuid === modelData.uuid

                    width: panel.rowWidth
                    height: Theme.denseRowHeight
                    interactive: true
                    activationBlocked: vpnRow.busy
                    selected: vpnRow.modelData.active
                    title: (vpnRow.modelData.active ? "▸ " : "  ") + vpnRow.modelData.name
                    value: vpnRow.busy ? panel.spin
                        : (vpnRow.modelData.active ? "CONNECTED" : vpnRow.modelData.type.toUpperCase())
                    contentLeftPadding: Theme.cellW / 2
                    accessibleName: vpnRow.modelData.name
                    accessibleDescription: vpnRow.busy ? "Busy"
                        : (vpnRow.modelData.active ? "Connected" : vpnRow.modelData.type)
                    onTriggered: Net.toggleVpn(vpnRow.modelData)
                }
            }

            Line {
                width: panel.rowWidth
                visible: Net.vpnError !== ""
                text: Net.vpnError
                color: Theme.red
                wrapMode: Text.Wrap
            }

            // ── Bluetooth ─────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                visible: Bt.available
                label: ""
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH
                visible: Bt.available

                Heading {
                    anchors.left: parent.left
                    text: "BLUETOOTH"
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW * 2

                    Action {
                        visible: Bt.enabled
                        on: Bt.requested
                        text: Bt.discovering ? (panel.spin + " scanning") : "Scan"
                        busy: Bt.discovering
                        onTriggered: Bt.toggleScan()
                    }

                    Action {
                        on: Bt.enabled
                        text: Bt.enabled ? "Bluetooth on" : "Bluetooth off"
                        onTriggered: Bt.setEnabled(!Bt.enabled)
                    }
                }
            }

            Line {
                visible: Bt.available && Bt.enabled && Bt.sorted.length === 0
                text: Bt.discovering ? "  scanning …" : "  no paired devices"
                color: Theme.fgDim
            }

            Repeater {
                id: btRepeater
                model: Bt.enabled ? Bt.sorted.slice(0, 8) : []

                PanelRow {
                    id: btRow

                    required property var modelData

                    readonly property bool pairing: btRow.modelData.pairing
                        || Bt.pairingAddress === btRow.modelData.address
                    readonly property string stateDescription: btRow.modelData.connected ? "Connected"
                        : (btRow.pairing ? "Pairing"
                            : (btRow.modelData.paired || btRow.modelData.bonded ? "Paired" : "New device"))

                    width: panel.rowWidth
                    height: Theme.denseRowHeight
                    interactive: true
                    selected: btRow.modelData.connected
                    title: (btRow.modelData.connected ? "▸ " : "  ") + Bt.label(btRow.modelData)
                        + (btRow.modelData.batteryAvailable ? ("  " + Math.round(btRow.modelData.battery * 100) + "%") : "")
                        + (btRow.pairing ? "  ·pairing"
                            : (btRow.modelData.paired || btRow.modelData.connected ? "" : "  ·new"))
                    contentLeftPadding: Theme.cellW / 2
                    trailingInset: removeButton.visible ? removeButton.width + Theme.cellW : 0
                    pointerActivationExclusion: removeButton
                    pointerActivationExclusionEnabled: removeButton.visible
                    accessibleName: Bt.label(btRow.modelData)
                    accessibleDescription: btRow.stateDescription
                        + (btRow.modelData.batteryAvailable
                            ? ("; battery " + Math.round(btRow.modelData.battery * 100) + " percent") : "")
                    onTriggered: Bt.toggleDevice(btRow.modelData)

                    Action {
                        id: removeButton

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: btRow.modelData.paired || btRow.modelData.bonded || btRow.modelData.connected
                        text: panel.pendingBtRemoval === btRow.modelData.address ? "Confirm" : "Remove"
                        tone: panel.pendingBtRemoval === btRow.modelData.address ? "danger" : "secondary"
                        onTriggered: {
                            if (panel.pendingBtRemoval === btRow.modelData.address) {
                                panel.pendingBtRemoval = "";
                                Bt.forgetDevice(btRow.modelData);
                            } else {
                                panel.pendingBtRemoval = btRow.modelData.address;
                            }
                        }
                    }
                }
            }
        }
    }
}
