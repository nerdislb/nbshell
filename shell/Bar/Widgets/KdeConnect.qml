import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import "../../Widgets/FocusScroll.js" as FocusScroll

// KDE Connect: Geraetestatus in der Leiste, volles Panel im Popout.
// Optik nach Vorbild von OmaConnect, in nbshells Bausteinen nachgebaut.
//
// Das Popout beherbergt zusaetzlich LocalSend ("NEARBY"): beides ist "etwas
// ans Handy geben", darum teilen sie sich einen Bar-Platz. Gesucht wird bei
// LocalSend nur, solange das Popout offen ist.
Cell {
    id: root

    readonly property var dev: Kdeconnect.selectedDevice
    readonly property bool linked: dev && dev.paired && dev.reachable

    shown: Kdeconnect.enabled
    // Der Telefonzugang ist auch im getrennten Zustand wichtig: dauerhaft
    // sichtbar lassen, damit Verbinden und Fehlersuche immer erreichbar sind.
    quiet: false
    // Keine pauschale Zeichenreserve: ohne Akkutext soll das Telefonsymbol
    // exakt denselben Seitenabstand wie die benachbarten Symbolzellen haben.
    slotChars: 0
    interactive: true
    popoutTakesKeyboard: true
    label: "KDE"
    icon: String.fromCodePoint(0xF011C) // nf-md-cellphone
    text: (root.dev && root.dev.capabilities.battery && root.dev.charge >= 0) ? (root.dev.charge + "%") : ""
    color: root.linked ? (root.dev.capabilities.battery && root.dev.charge >= 0 && root.dev.charge <= 15 ? Theme.red : Theme.barAccent) : Theme.textDim

    onClicked: Kdeconnect.refresh()

    preview: Component {
        BarPreview {
            icon: String.fromCodePoint(0xF011C)
            title: root.dev ? root.dev.name : "KDE Connect"
            subtitle: root.linked ? "Paired and reachable" : "Phone unavailable"
            badge: root.dev && root.dev.capabilities.battery && root.dev.charge >= 0 ? root.dev.charge + " %" : ""
            badgeColor: root.linked ? Theme.green : Theme.fgDim
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Connection", "value": root.linked ? "online" : "offline", "color": root.linked ? Theme.green : Theme.fgDim },
                        { "label": "Battery", "value": root.dev && root.dev.charge >= 0 ? root.dev.charge + " %" : "unavailable" },
                        { "label": "Phone mirror", "value": Phone.mirroring ? "running" : "stopped", "color": Phone.mirroring ? Theme.green : Theme.fgDim },
                        { "label": "Webcam", "value": Phone.cameraActive ? "running" : "stopped", "color": Phone.cameraActive ? Theme.green : Theme.fgDim }
                    ]
                }
            ]
        }
    }

    onPopoutVisibleChanged: {
        Nearby.wanted = root.popoutVisible;
        if (root.popoutVisible)
            Phone.refresh();
    }

    popout: Component {
        Item {
            id: viewport

            property var closePopout: null
            readonly property real rowWidth: 56 * Theme.cellW
            readonly property Item initialFocusItem: deviceRepeater.count > 0
                ? deviceRepeater.itemAt(0) : null
            implicitWidth: rowWidth
            implicitHeight: Theme.cellH * 28

            Flickable {
                id: scroll

                anchors.fill: parent
                contentWidth: width
                contentHeight: panel.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                function revealItem(item) {
                    if (!item)
                        return;
                    const mapped = item.mapToItem(panel, 0, 0);
                    contentY = FocusScroll.contentYForFocus(
                        mapped.y, item.height, contentY, height, contentHeight, Theme.spaceMd);
                }

                Column {
                    id: panel

                    readonly property var closePopout: viewport.closePopout
                    readonly property real rowWidth: viewport.rowWidth

                    // Welcher Composer offen ist: "text" (Text/Link teilen) oder
                    // "ping" (Ping mit Text). Leer = noneer.
                    property string composer: ""
                    property string draft: ""
                    property bool cmdsOpen: false
                    property string confirmUnpair: ""

                    readonly property var dev: Kdeconnect.selectedDevice

                    spacing: Theme.cellH * 0.2

            // ── Kopf ───────────────────────────────────────────────────────
            Item {
                width: panel.rowWidth
                height: headCol.implicitHeight

                Column {
                    id: headCol
                    anchors.left: parent.left
                    spacing: Theme.cellH * 0.15

                    Line {
                        text: panel.dev ? panel.dev.name : "KDE Connect"
                        color: Theme.fg
                        font.bold: true
                        font.pixelSize: Theme.fontSize + 3
                    }
                    Line {
                        text: {
                            if (!panel.dev)
                                return "No device found";
                            if (!panel.dev.paired)
                                return "Not paired";
                            return panel.dev.reachable ? "Gekoppelt & erreichbar" : "Paired, not reachable";
                        }
                        color: Theme.fgDim
                    }
                    Line {
                        visible: panel.dev && panel.dev.reachable
                        text: {
                            if (!panel.dev)
                                return "";
                            var parts = [];
                            if (panel.dev.capabilities.battery && panel.dev.charge >= 0)
                                parts.push(String.fromCodePoint(0xF0079) + " " + panel.dev.charge + "%");
                            if (panel.dev.capabilities.battery)
                                parts.push(panel.dev.charging ? "Charging" : "Discharging");
                            const cell = Kdeconnect.cellLabel(panel.dev);
                            if (cell !== "")
                                parts.push(cell);
                            return parts.join("  •  ");
                        }
                        color: Theme.fg
                    }
                }

                // Refresh rechts oben
                Line {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: String.fromCodePoint(0xF0450) // nf-md-refresh
                    color: refreshHover.hovered ? Theme.accent : Theme.fgDim
                    HoverHandler { id: refreshHover }
                    TapHandler { onTapped: Kdeconnect.refresh() }
                }
            }

            // ── DEVICES ────────────────────────────────────────────────────
            Rule { rowWidth: panel.rowWidth; label: "DEVICES" }

            Line {
                visible: Kdeconnect.devices.length === 0
                text: "No devices — is KDE Connect running on the phone?"
                color: Theme.muted
            }

            Repeater {
                id: deviceRepeater
                model: Kdeconnect.devices

                PanelRow {
                    id: devRow
                    required property var modelData

                    readonly property bool isSelected: Kdeconnect.selectedDevice
                        && Kdeconnect.selectedDevice.id === devRow.modelData.id

                    width: panel.rowWidth
                    height: Theme.cellH * 1.6
                    interactive: true
                    selected: devRow.isSelected
                    title: (devRow.isSelected ? "▸ " : "  ") + devRow.modelData.name
                    contentLeftPadding: Theme.cellW
                    trailingInset: deviceActions.implicitWidth + Theme.cellW
                    pointerActivationExclusion: pairButton
                    pointerActivationExclusionEnabled: pairButton.visible
                    accessibleName: devRow.modelData.name
                    accessibleDescription: (devRow.modelData.reachable ? "Reachable" : "Not reachable")
                        + (devRow.modelData.paired ? "; paired" : "; not paired")
                    onActiveFocusChanged: if (devRow.activeFocus) scroll.revealItem(devRow)
                    onTriggered: Kdeconnect.selectedId = devRow.modelData.id

                    Row {
                        id: deviceActions
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.cellW

                        Line {
                            text: "●"
                            color: devRow.modelData.reachable ? Theme.green : Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                            Accessible.ignored: true
                        }

                        ActionButton {
                            id: pairButton
                            compact: true
                            text: !devRow.modelData.paired ? "Pair"
                                : (panel.confirmUnpair === devRow.modelData.id ? "Confirm" : "Unpair")
                            tone: panel.confirmUnpair === devRow.modelData.id ? "danger" : "secondary"
                            onTriggered: {
                                const id = devRow.modelData.id;
                                if (!devRow.modelData.paired) {
                                    Kdeconnect.pair(id);
                                } else if (panel.confirmUnpair === id) {
                                    Kdeconnect.unpair(id);
                                    panel.confirmUnpair = "";
                                } else {
                                    panel.confirmUnpair = id;
                                }
                            }
                        }
                    }
                }
            }

            // ── PHONE ACTIONS ──────────────────────────────────────────────
            Rule {
                rowWidth: panel.rowWidth
                label: "PHONE ACTIONS"
                visible: panel.dev && panel.dev.reachable
            }

            Flow {
                width: panel.rowWidth
                spacing: Theme.cellW
                visible: panel.dev && panel.dev.reachable

                Repeater {
                    model: {
                        if (!panel.dev)
                            return [];
                        const c = panel.dev.capabilities;
                        var a = [];
                        if (c.ring) a.push({ "id": "ring", "label": "Ring" });
                        if (c.clipboard) a.push({ "id": "clipboard", "label": "Clipboard" });
                        if (c.file) a.push({ "id": "file", "label": "File" });
                        if (c.sms) a.push({ "id": "sms", "label": "SMS" });
                        if (c.ping) a.push({ "id": "ping", "label": "Ping" });
                        if (c.text) a.push({ "id": "text", "label": "Text" });
                        return a;
                    }

                    Rectangle {
                        id: actBtn
                        required property var modelData
                        readonly property bool active: panel.composer === modelData.id

                        width: actLabel.implicitWidth + Theme.cellW * 2
                        height: Theme.denseRowHeight
                        radius: Theme.radius
                        color: actBtn.active ? Theme.selectedSurface() : (actMouse.containsMouse ? Theme.hover : "transparent")
                        border.width: Theme.borderWidth
                        border.color: actBtn.active ? Theme.accent : Theme.alpha(Theme.fg, 0.15)

                        Line {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.modelData.label
                            color: actBtn.active ? Theme.selectedForeground() : Theme.fg
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const id = panel.dev.id;
                                const a = actBtn.modelData.id;
                                if (a === "ring") Kdeconnect.ring(id);
                                else if (a === "clipboard") Kdeconnect.sendClipboard(id);
                                else if (a === "file") Kdeconnect.shareFile(id);
                                else if (a === "sms") Kdeconnect.openSms(id);
                                else if (a === "text" || a === "ping") {
                                    panel.composer = (panel.composer === a) ? "" : a;
                                    panel.draft = "";
                                    if (panel.composer !== "")
                                        composerInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // ── PHONE MIRROR ──────────────────────────────────────────────
            Rule {
                rowWidth: panel.rowWidth
                label: "PHONE MIRROR · NBPHONE"
            }

            Line {
                width: panel.rowWidth
                text: {
                    if (!Phone.available)
                        return "nbphone is not installed — see github.com/nerdislb/nbphone";
                    if (!Phone.scrcpyAvailable)
                        return "scrcpy is missing — sudo pacman -S scrcpy";
                    if (!Phone.connected)
                        return "No ADB device — enable USB debugging or run nbphone connect";
                    const name = Phone.model !== "" ? Phone.model : Phone.serial;
                    return name + "  •  " + (Phone.wireless ? "WLAN" : "USB") + "  •  " + (Phone.mirroring ? "mirror running" : "ready");
                }
                color: Phone.connected && Phone.scrcpyAvailable ? Theme.fg : Theme.yellow
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Theme.cellW
                visible: Phone.available

                ActionButton {
                    text: Phone.mirroring ? "Stop" : "Open"
                    busy: Phone.busy
                    enabled: Phone.mirroring || (Phone.connected && Phone.scrcpyAvailable)
                    onTriggered: Phone.mirroring ? Phone.stop() : Phone.start(false)
                }

                ActionButton {
                    text: "Private"
                    busy: Phone.busy
                    enabled: !Phone.mirroring && Phone.connected && Phone.scrcpyAvailable
                    onTriggered: Phone.start(true)
                }

                ActionButton {
                    text: "Refresh"
                    enabled: !Phone.busy
                    onTriggered: Phone.refresh()
                }

                ActionButton {
                    text: Phone.wireless ? "WI-FI ✓" : "WI-FI"
                    busy: Phone.busy
                    enabled: !Phone.busy && !Phone.mirroring
                    onTriggered: Phone.connectWireless()
                }
            }

            Line {
                visible: Phone.status !== ""
                width: panel.rowWidth
                text: Phone.status
                color: Phone.status.indexOf("fehlt") !== -1 || Phone.status.indexOf("none") !== -1 ? Theme.yellow : Theme.green
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSize - 1
            }

            // ── PHONE CAMERA ──────────────────────────────────────────────
            Rule {
                rowWidth: panel.rowWidth
                label: "PHONE CAMERA · WEBCAM"
            }

            Line {
                width: panel.rowWidth
                text: {
                    if (!Phone.available)
                        return "Install nbphone to use the phone camera";
                    if (!Phone.webcamReady)
                        return "One-time setup required for Phone Camera";
                    if (Phone.cameraActive)
                        return Phone.cameraMode.toUpperCase() + " CAMERA  •  LIVE  •  " + Phone.cameraDevice;
                    if (!Phone.connected)
                        return "Connect the phone through USB or wireless ADB";
                    return "Phone Camera  •  " + Phone.cameraDevice + "  •  ready for OBS";
                }
                color: Phone.cameraActive ? Theme.green : (Phone.webcamReady && Phone.connected ? Theme.fg : Theme.yellow)
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Theme.cellW
                visible: Phone.available

                ActionButton {
                    text: "Back"
                    busy: Phone.busy
                    enabled: Phone.connected && Phone.webcamReady && (!Phone.cameraActive || Phone.cameraMode !== "back")
                    onTriggered: Phone.camera("back")
                }

                ActionButton {
                    text: "Front"
                    busy: Phone.busy
                    enabled: Phone.connected && Phone.webcamReady && (!Phone.cameraActive || Phone.cameraMode !== "front")
                    onTriggered: Phone.camera("front")
                }

                ActionButton {
                    text: "Stop"
                    busy: Phone.busy
                    enabled: Phone.cameraActive
                    onTriggered: Phone.camera("off")
                }

                ActionButton {
                    text: "Preview"
                    enabled: Phone.cameraActive && !Phone.busy
                    onTriggered: Phone.previewCamera()
                }

                ActionButton {
                    text: Phone.webcamReady ? "OBS" : "Setup"
                    enabled: !Phone.busy
                    onTriggered: Phone.webcamReady ? Phone.openObs() : Phone.setupCamera()
                }
            }

            // Composer (Text/Link teilen bzw. Ping mit Text)
            Line {
                visible: panel.composer !== "" && panel.dev
                text: (panel.composer === "ping" ? "Ping text to " : "Share text or a link with ") + (panel.dev ? panel.dev.name : "")
                color: Theme.fg
                font.bold: true
            }

            Row {
                visible: panel.composer !== ""
                width: panel.rowWidth
                spacing: Theme.cellW

                Rectangle {
                    width: panel.rowWidth * 0.6
                    height: Theme.cellH * 1.6
                    radius: Theme.radius
                    color: Theme.bgDark
                    border.width: Theme.borderWidth
                    border.color: composerInput.activeFocus ? Theme.accent : Theme.alpha(Theme.fg, 0.15)

                    TextInput {
                        id: composerInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.cellW
                        anchors.rightMargin: Theme.cellW
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.fg
                        selectByMouse: true
                        selectionColor: Theme.selection
                        text: panel.draft
                        onTextChanged: panel.draft = text

                        Keys.onReturnPressed: sendBtn.go()
                        Keys.onEnterPressed: sendBtn.go()
                        Keys.onEscapePressed: { panel.composer = ""; panel.draft = ""; }

                        Line {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: composerInput.text === ""
                            text: panel.composer === "ping" ? "Message (optional)…" : "e.g. https://…"
                            color: Theme.fgDim
                        }
                    }
                }

                Line {
                    id: sendBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Send"
                    color: sendHover.hovered ? Theme.readable(Theme.accent, Theme.bg) : Theme.accent
                    function go() {
                        if (!panel.dev)
                            return;
                        if (panel.composer === "ping")
                            Kdeconnect.ping(panel.dev.id, panel.draft);
                        else if (panel.composer === "text")
                            Kdeconnect.shareText(panel.dev.id, panel.draft);
                        panel.composer = "";
                        panel.draft = "";
                    }
                    HoverHandler { id: sendHover }
                    TapHandler { onTapped: sendBtn.go() }
                }

                Line {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel"
                    color: cancelHover.hovered ? Theme.readable(Theme.red, Theme.bg) : Theme.fgDim
                    HoverHandler { id: cancelHover }
                    TapHandler { onTapped: { panel.composer = ""; panel.draft = ""; } }
                }
            }

            // ── REMOTE COMMANDS ────────────────────────────────────────────
            PanelRow {
                id: cmdHeader
                width: panel.rowWidth
                height: Theme.denseRowHeight
                visible: panel.dev && panel.dev.capabilities.commands
                interactive: true
                selected: panel.cmdsOpen
                title: (panel.cmdsOpen ? "⌄ " : "> ") + "REMOTE COMMANDS"
                accessibleName: "Remote commands"
                accessibleDescription: panel.cmdsOpen ? "Expanded" : "Collapsed"
                onActiveFocusChanged: if (cmdHeader.activeFocus) scroll.revealItem(cmdHeader)
                onTriggered: {
                    panel.cmdsOpen = !panel.cmdsOpen;
                    if (panel.cmdsOpen && panel.dev)
                        Kdeconnect.loadCommands(panel.dev.id);
                }
            }

            Line {
                visible: panel.cmdsOpen && Kdeconnect.commands.length === 0
                text: "No commands — add commands in KDE Connect on the phone."
                color: Theme.muted
                font.pixelSize: Theme.fontSize - 1
            }

            Repeater {
                id: commandRepeater
                model: panel.cmdsOpen ? Kdeconnect.commands : []

                PanelRow {
                    id: commandRow
                    required property var modelData
                    width: panel.rowWidth
                    height: Theme.denseRowHeight
                    interactive: true
                    title: "▶ " + commandRow.modelData.name
                    contentLeftPadding: Theme.cellW
                    accessibleName: commandRow.modelData.name
                    accessibleDescription: "Run remote command"
                    onActiveFocusChanged: if (commandRow.activeFocus) scroll.revealItem(commandRow)
                    onTriggered: if (panel.dev)
                        Kdeconnect.runCommand(panel.dev.id, commandRow.modelData.key)
                }
            }

            // ── NEARBY (LocalSend) ─────────────────────────────────────────
            // Handy ohne gekoppelte App: LocalSend findet Geraete im gleichen
            // Netz. Je Geraet die zwei Dinge, die man wirklich schnell
            // hinueberschiebt -- Clipboard und letztes Bildschirmfoto.
            Rule {
                rowWidth: panel.rowWidth
                label: "NEARBY · LOCALSEND"
                visible: Nearby.enabled
            }

            Line {
                visible: Nearby.enabled && Nearby.devices.length === 0
                width: panel.rowWidth
                text: Nearby.scanning ? "  scanning …" : "  no devices — LocalSend must be open on the other device"
                color: Theme.muted
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Nearby.enabled ? Nearby.devices : []

                Rectangle {
                    id: nbRow
                    required property var modelData

                    width: panel.rowWidth
                    height: nbBody.implicitHeight + Theme.cellH
                    radius: Theme.radius
                    color: Theme.alpha(Theme.fg, 0.05)
                    border.width: Theme.borderWidth
                    border.color: Theme.alpha(Theme.fg, 0.12)

                    Column {
                        id: nbBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW
                        anchors.rightMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.cellH * 0.2

                        Item {
                            width: parent.width
                            height: nbAlias.implicitHeight

                            Line {
                                id: nbAlias
                                anchors.left: parent.left
                                text: nbRow.modelData.alias
                                color: Theme.fg
                            }
                            Line {
                                anchors.right: parent.right
                                text: nbRow.modelData.model + "  " + nbRow.modelData.ip
                                color: Theme.muted
                            }
                        }

                        Row {
                            spacing: Theme.cellW * 2

                            component Knopf: ActionButton {
                                compact: true
                            }

                            Knopf {
                                text: "Clipboard"
                                onTriggered: Nearby.sendText(nbRow.modelData, Clipboard.entries.length > 0 ? Clipboard.entries[0] : "")
                            }

                            Knopf {
                                text: "Latest image"
                                onTriggered: Nearby.sendLastShot(nbRow.modelData)
                            }
                        }
                    }
                }
            }

            Line {
                visible: Nearby.enabled && Nearby.status !== ""
                width: panel.rowWidth
                text: "  " + Nearby.status
                color: Nearby.status.indexOf("failed") === 0 ? Theme.red : Theme.green
                wrapMode: Text.WordWrap
            }

            Line {
                visible: Nearby.enabled
                text: "  Files: nbshell nearby send <file>"
                color: Theme.muted
                font.pixelSize: Theme.fontSize - 1
            }

            // ── Rueckmeldung ───────────────────────────────────────────────
                    Line {
                        visible: Kdeconnect.status !== ""
                        text: "✓ " + Kdeconnect.status
                        color: Theme.green
                        font.pixelSize: Theme.fontSize - 1
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Theme.borderWidth
                y: scroll.visibleArea.yPosition * viewport.height
                width: Math.max(2, Theme.borderWidth * 2)
                height: Math.max(Theme.cellH, scroll.visibleArea.heightRatio * viewport.height)
                radius: width / 2
                color: Theme.alpha(Theme.accent, 0.7)
                visible: scroll.contentHeight > scroll.height
            }
        }
    }
}
