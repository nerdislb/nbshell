import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

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
    quiet: !root.linked
    slotChars: 4
    interactive: true
    label: "KDE"
    icon: String.fromCodePoint(0xF011C) // nf-md-cellphone
    text: (root.dev && root.dev.capabilities.battery && root.dev.charge >= 0) ? (root.dev.charge + "%") : ""
    color: root.linked ? (root.dev.capabilities.battery && root.dev.charge >= 0 && root.dev.charge <= 15 ? Theme.red : Theme.barAccent) : Theme.textDim

    onClicked: Kdeconnect.refresh()

    // LocalSend nur suchen, solange jemand hinsieht.
    onPopoutVisibleChanged: Nearby.wanted = root.popoutVisible

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            readonly property real rowWidth: 56 * Theme.cellW

            // Welcher Composer offen ist: "text" (Text/Link teilen) oder
            // "ping" (Ping mit Text). Leer = keiner.
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
                                return "Kein Geraet gefunden";
                            if (!panel.dev.paired)
                                return "Nicht gekoppelt";
                            return panel.dev.reachable ? "Gekoppelt & erreichbar" : "Gekoppelt, nicht erreichbar";
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
                                parts.push(panel.dev.charging ? "Laden" : "Entladen");
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
                text: "Keine Geraete — ist KDE Connect am Handy verbunden?"
                color: Theme.muted
            }

            Repeater {
                model: Kdeconnect.devices

                Rectangle {
                    id: devRow
                    required property var modelData

                    width: panel.rowWidth
                    height: Theme.cellH * 1.6
                    radius: Theme.radius
                    color: (Kdeconnect.selectedDevice && Kdeconnect.selectedDevice.id === modelData.id) ? Theme.alpha(Theme.accent, 0.12) : Theme.alpha(Theme.fg, 0.05)
                    border.width: Theme.borderWidth
                    border.color: (Kdeconnect.selectedDevice && Kdeconnect.selectedDevice.id === modelData.id) ? Theme.accent : Theme.alpha(Theme.fg, 0.12)

                    Line {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: modelData.reachable ? Theme.fg : Theme.fgDim
                        elide: Text.ElideRight
                        width: panel.rowWidth * 0.55
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: Kdeconnect.selectedId = devRow.modelData.id
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.cellW

                        Line {
                            text: "●"
                            color: devRow.modelData.reachable ? Theme.green : Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Line {
                            text: {
                                if (!devRow.modelData.paired)
                                    return "Pair";
                                return panel.confirmUnpair === devRow.modelData.id ? "Sicher?" : "Unpair";
                            }
                            color: unpairHover.hovered ? Theme.readable(Theme.accent, Theme.bg) : (panel.confirmUnpair === devRow.modelData.id ? Theme.red : Theme.fgDim)
                            anchors.verticalCenter: parent.verticalCenter

                            HoverHandler { id: unpairHover }
                            TapHandler {
                                onTapped: {
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
                        height: Theme.cellH * 1.4
                        radius: Theme.radius
                        color: actBtn.active ? Theme.selection : (actMouse.containsMouse ? Theme.hover : "transparent")
                        border.width: Theme.borderWidth
                        border.color: actBtn.active ? Theme.accent : Theme.alpha(Theme.fg, 0.15)

                        Line {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.modelData.label
                            color: actBtn.active ? Theme.readable(Theme.selection, Theme.fg) : Theme.fg
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

            // Composer (Text/Link teilen bzw. Ping mit Text)
            Line {
                visible: panel.composer !== "" && panel.dev
                text: (panel.composer === "ping" ? "Ping-Text an " : "Text oder Link teilen mit ") + (panel.dev ? panel.dev.name : "")
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
                            text: panel.composer === "ping" ? "Nachricht (optional)…" : "z.B. https://…"
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
            Item {
                width: panel.rowWidth
                height: cmdHeader.implicitHeight + Theme.cellH * 0.6
                visible: panel.dev && panel.dev.capabilities.commands

                Line {
                    id: cmdHeader
                    anchors.verticalCenter: parent.verticalCenter
                    text: (panel.cmdsOpen ? "⌄ " : "> ") + "REMOTE COMMANDS"
                    color: cmdHover.hovered ? Theme.accent : Theme.fgDim
                    font.pixelSize: Theme.fontSize - 1

                    HoverHandler { id: cmdHover }
                    TapHandler {
                        onTapped: {
                            panel.cmdsOpen = !panel.cmdsOpen;
                            if (panel.cmdsOpen && panel.dev)
                                Kdeconnect.loadCommands(panel.dev.id);
                        }
                    }
                }
            }

            Line {
                visible: panel.cmdsOpen && Kdeconnect.commands.length === 0
                text: "Keine Befehle — am Handy unter KDE Connect → Befehle ausfuehren anlegen."
                color: Theme.muted
                font.pixelSize: Theme.fontSize - 1
            }

            Repeater {
                model: panel.cmdsOpen ? Kdeconnect.commands : []

                Rectangle {
                    required property var modelData
                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: cmdRowMouse.containsMouse ? Theme.hover : "transparent"

                    Line {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▶ " + modelData.name
                        color: Theme.fg
                        elide: Text.ElideRight
                        width: panel.rowWidth - Theme.cellW * 2
                    }

                    MouseArea {
                        id: cmdRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (panel.dev) Kdeconnect.runCommand(panel.dev.id, modelData.key)
                    }
                }
            }

            // ── NEARBY (LocalSend) ─────────────────────────────────────────
            // Handy ohne gekoppelte App: LocalSend findet Geraete im gleichen
            // Netz. Je Geraet die zwei Dinge, die man wirklich schnell
            // hinueberschiebt -- Zwischenablage und letztes Bildschirmfoto.
            Rule {
                rowWidth: panel.rowWidth
                label: "NEARBY · LOCALSEND"
                visible: Nearby.enabled
            }

            Line {
                visible: Nearby.enabled && Nearby.devices.length === 0
                width: panel.rowWidth
                text: Nearby.scanning ? "  sucht …" : "  niemand da — die Gegenstelle muss LocalSend offen haben"
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

                            component Knopf: Line {
                                id: knopf
                                signal triggered

                                color: kmaus.hovered ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim

                                HoverHandler {
                                    id: kmaus
                                    margin: Theme.cellW / 2
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    margin: Theme.cellW / 2
                                    onTapped: knopf.triggered()
                                }
                            }

                            Knopf {
                                text: "[ Zwischenablage ]"
                                onTriggered: Nearby.sendText(nbRow.modelData, Clipboard.entries.length > 0 ? Clipboard.entries[0] : "")
                            }

                            Knopf {
                                text: "[ letztes Bild ]"
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
                color: Nearby.status.indexOf("ging nicht") === 0 ? Theme.red : Theme.green
                wrapMode: Text.WordWrap
            }

            Line {
                visible: Nearby.enabled
                text: "  Dateien: nbshell nearby send <datei>"
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
}
