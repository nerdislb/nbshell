import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Networking
import qs.Common
import qs.Services
import qs.Widgets

// Network styling is scoped here. VPN, brightness and Bluetooth remain
// nbshell extensions; neither the bar nor their backends are replaced.
Column {
    id: panel
    property var closePopout: null
    property string networkIcon: Icons.wifi
    property real availableWidth: Theme.networkWidth
    readonly property real rowWidth: Math.max(1, Math.min(availableWidth,
        Theme.networkWidth - 2 * (Theme.networkPadding + Theme.networkBorderWidth)))
    property string pendingNetwork: ""
    property string passwordText: ""
    property string pendingBtRemoval: ""
    property var shownNetworks: []
    readonly property Item initialFocusItem: portalAction.visible ? portalAction : wifiRepeater.count > 0
        ? wifiRepeater.itemAt(0).focusTarget : wifiToggle
    width: rowWidth
    spacing: Theme.networkGap

    function refreshNetworks() {
        // Hold delegate identity while typing. Activation still resolves the
        // current backend object by SSID AND security in Net.connect().
        if (pendingNetwork !== "") return;
        shownNetworks = Net.wifiNetworks.slice().sort((a,b) =>
            Number(b.connected)-Number(a.connected) || Number(b.known)-Number(a.known)
            || b.signalStrength-a.signalStrength || a.name.localeCompare(b.name));
    }
    function section(index) {
        const row = shownNetworks[index];
        const label = row.connected ? "CONNECTED" : row.known ? "SAVED NETWORKS" : "OTHER NETWORKS";
        if (index === 0) return label;
        const previous = shownNetworks[index-1];
        return row.connected !== previous.connected || (!row.connected && row.known !== previous.known) ? label : "";
    }
    function cancelPassword(key) {
        passwordText = "";
        pendingNetwork = "";
        Qt.callLater(() => {
            for (let i=0; i<wifiRepeater.count; i++) {
                const row=wifiRepeater.itemAt(i);
                if (row.modelData.key === key) { row.focusTarget.forceActiveFocus(Qt.TabFocusReason); return; }
            }
            wifiToggle.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    onPendingNetworkChanged: if (pendingNetwork === "") refreshNetworks()
    Connections {
        target: Net
        function onWifiNetworksChanged() {
            if (panel.pendingNetwork !== "" && !Net.wifiNetworks.some(n=>n.key===panel.pendingNetwork))
                panel.cancelPassword(panel.pendingNetwork);
            else panel.refreshNetworks();
        }
        function onWifiEnabledChanged() {
            if (!Net.wifiEnabled) panel.cancelPassword(panel.pendingNetwork);
            panel.refreshNetworks();
        }
    }
    Component.onCompleted: {
        refreshNetworks();
        Net.setScanner(true);
        Net.setTrafficMonitoring(true);
        Net.refreshVpns();
        Net.refreshConnectivity();
    }
    Component.onDestruction: {
        passwordText = "";
        Net.setScanner(false);
        Net.setTrafficMonitoring(false);
        Bt.scan(false);
    }

    function controls(item, list) {
        for (let child of item.children) {
            if (!child.visible || !child.enabled) continue;
            if (child.activeFocusOnTab) list.push(child);
            else controls(child, list);
        }
        return list;
    }
    function moveFocus(direction) {
        const items = controls(panel, []);
        if (!items.length) return;
        const index = items.findIndex(item=>item.activeFocus);
        items[(index + direction + items.length) % items.length].forceActiveFocus(Qt.TabFocusReason);
    }
    Keys.onPressed: event => {
        // Password editing owns all printable/navigation keys until cancelled.
        if (pendingNetwork !== "" || event.modifiers !== Qt.NoModifier) return;
        if ([Qt.Key_Up,Qt.Key_K,Qt.Key_Down,Qt.Key_J].includes(event.key)) {
            moveFocus(event.key === Qt.Key_Up || event.key === Qt.Key_K ? -1 : 1);
            event.accepted=true;
        }
    }

    property int spinIndex: 0
    readonly property string spin: Theme.reducedMotion ? "…" : "-\\|/".charAt(spinIndex % 4)
    Timer {
        interval: 150; repeat: true
        running: !Theme.reducedMotion && (Net.scanning || Bt.discovering || Net.vpnBusyUuid !== "")
        onTriggered: panel.spinIndex++
    }
    component Heading: Line { color: Theme.networkSecondary; font.pixelSize: Theme.networkCaptionSize; font.bold: true; font.letterSpacing: 1.2 }
    component Action: ActionButton {
        property bool on: false
        compact: true
        tone: on ? "primary" : "secondary"
        accentColor: on ? Theme.green : Theme.accent
    }
    component Separator: Rectangle {
        width: panel.rowWidth; height: Math.max(1,Theme.borderWidth)
        color: Theme.mix(Theme.bg,Theme.fg,0.18)
    }
    component HeaderAction: InteractiveSurface {
        id: action
        property string glyph: ""
        implicitWidth: Theme.networkIconSlot + Theme.networkRowInset
        implicitHeight: Theme.networkSwitchHeight + Theme.networkRowInset
        color: activeFocus ? Theme.networkHover : "transparent"
        radius: Theme.radius
        border.width: activeFocus ? Theme.borderWidth : 0
        border.color: Theme.networkOutline
        Line { anchors.centerIn: parent; text: action.glyph; font.pixelSize: Theme.networkTitleSize * 1.5 }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) action.forceActiveFocus(Qt.MouseFocusReason) }
        TapHandler { onTapped: { action.forceActiveFocus(Qt.MouseFocusReason); action.activate(); } }
        Controls.ToolTip.visible: hover.hovered
        Controls.ToolTip.text: accessibleName
    }

    Item {
        width: panel.rowWidth
        implicitHeight: Math.max(heroIcon.implicitHeight,heroLabels.implicitHeight,heroActions.height)
        Line {
            id: heroIcon
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: panel.networkIcon
            font.pixelSize: Theme.networkHeroSize
            color: Net.internetRestricted ? Theme.readable(Theme.yellow,Theme.bg,4.5) : Theme.fg
        }
        Row {
            id: heroActions
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.networkRowGap
            HeaderAction {
                visible: Net.activeWifi !== null
                glyph: Icons.cp(0xF0432)
                accessibleName: "Show Wi-Fi QR code"
                onTriggered: { Runtime.qrOpen=true; panel.closePopout?.(); }
            }
            HeaderAction {
                visible: Net.online
                glyph: Icons.cp(0xF04C5)
                accessibleName: "Run a speed test"
                onTriggered: { Runtime.speedOpen=true; panel.closePopout?.(); }
            }
            HeaderAction {
                id: wifiToggle
                glyph: ""
                implicitWidth: Math.round(Theme.networkSwitchHeight * 1.9) + Theme.networkRowInset
                accessibleRole: Accessible.CheckBox
                accessibleCheckable: true
                accessibleChecked: Net.wifiEnabled
                accessibleName: Net.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                accessibleDescription: Net.wifiDevice ? "Wi-Fi radio" : "No Wi-Fi adapter available"
                activationBlocked: !Net.wifiDevice
                onTriggered: Net.setWifiEnabled(!Net.wifiEnabled)
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.round(Theme.networkSwitchHeight * 1.9); height: Theme.networkSwitchHeight
                    radius: Theme.radius > 0 ? height/2 : 0
                    color: Net.wifiEnabled ? Theme.networkSelected : "transparent"
                    border.width: Net.wifiEnabled ? 0 : Theme.borderWidth
                    border.color: Theme.panelBorder
                    opacity: Net.wifiDevice ? 1 : Theme.controlDisabledOpacity
                    Rectangle {
                        width: Math.round(parent.height*0.72); height: width
                        radius: Theme.radius > 0 ? height/2 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        x: Net.wifiEnabled ? parent.width-width-(parent.height-height)/2 : (parent.height-height)/2
                        color: Net.wifiEnabled ? Theme.readable(Theme.accent,Theme.networkSelected,4.5) : Theme.networkSecondary
                        Behavior on x { NumberAnimation { duration: Theme.motionEffectsFast } }
                    }
                }
            }
        }
        Column {
            id: heroLabels
            anchors.left: heroIcon.right; anchors.leftMargin: Theme.networkPadding
            anchors.right: heroActions.left; anchors.rightMargin: Theme.networkGap
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(2*Theme.networkScale)
            Line { width: parent.width; text: Net.summary; font.pixelSize: Theme.networkTitleSize; font.bold: true; elide: Text.ElideRight }
            Heading {
                width: parent.width; text: Net.hasCaptivePortal ? "SIGN-IN REQUIRED" : Net.internetRestricted ? "LIMITED CONNECTIVITY" : Net.online ? "CONNECTED" : "DISCONNECTED"; elide: Text.ElideRight
                color: Net.internetRestricted ? Theme.readable(Theme.yellow,Theme.bg,4.5) : Theme.networkSecondary
            }
        }
    }
    ActionButton {
        id: portalAction
        visible: Net.hasCaptivePortal
        width: panel.rowWidth
        text: "Sign in to network"
        tone: "primary"
        onTriggered: Net.openCaptivePortal()
    }
    Line {
        visible: Net.hasCaptivePortal
        width: panel.rowWidth
        text: "Sign in or accept this network’s terms to access the internet."
        font.pixelSize: Theme.networkCaptionSize
        color: Theme.networkSecondary
        wrapMode: Text.WordWrap
    }
    Separator { visible: Net.online }
    Grid {
        visible: Net.online
        width: panel.rowWidth
        columns: 2
        columnSpacing: Theme.networkRowInset * 2
        rowSpacing: Theme.networkRowGap
        Repeater {
            model: [
                {label:"Receiving",value:Net.formatRate(Net.downloadBps)},
                {label:"Sending",value:Net.formatRate(Net.uploadBps)},
                {label:"Signal",value:Net.activeWifi ? Net.percentOf(Net.activeWifi.signalStrength)+"%" : "Ethernet"},
                {label:"Security",value:Net.activeWifi ? (Net.activeWifi.security !== WifiSecurityType.Open ? "Secured" : "Open") : "Wired"},
                {label:"Interface",value:Net.trafficInterface || "—"},
                {label:"Internet",value:Net.hasCaptivePortal ? "Sign in" : Net.internetRestricted ? "Limited" : Net.connectivity === "full" ? "Available" : "Unknown"}
            ]
            Item {
                required property var modelData
                width: (panel.rowWidth - Theme.networkRowInset * 2) / 2
                implicitHeight: valueLabel.implicitHeight
                Line { width: parent.width/2; text: modelData.label; font.pixelSize: Theme.networkCaptionSize; color: Theme.networkSecondary }
                Line { id:valueLabel; x: parent.width/2; width:parent.width/2; text:modelData.value; font.pixelSize:Theme.networkCaptionSize; elide:Text.ElideRight; horizontalAlignment:Text.AlignRight }
            }
        }
    }
    Flow {
        width: panel.rowWidth
        spacing: Theme.networkRowGap
        ActionButton {
            id: connectivityCheck
            visible: Net.online && Net.connectivityChecksEnabled
            text: "Check connection"; compact:true
            onTriggered: Net.refreshConnectivity()
        }
        ActionButton {
            visible: Net.wifiEnabled && !!Net.wifiDevice
            text: Net.scanning ? "Scanning…" : "Scan"
            compact:true; busy:Net.scanning
            onTriggered: Net.rescan()
        }
    }
    Separator {}
    Heading {
        width:panel.rowWidth
        visible: Net.wifiEnabled && Net.scanning
        text:"SCANNING WI-FI…"
    }
    Line {
        width: panel.rowWidth
        visible: !Net.wifiDevice || !Net.wifiEnabled || panel.shownNetworks.length === 0
        text: !Net.wifiDevice ? "No Wi-Fi adapter available" : !Net.wifiEnabled ? "Wi-Fi is off" : Net.scanning ? "Searching for networks…" : "No networks found"
        color:Theme.networkSecondary; font.pixelSize:Theme.networkCaptionSize
        wrapMode:Text.WordWrap
    }
    Flickable {
        id: wifiViewport
        width:panel.rowWidth
        height:Math.min(wifiColumn.implicitHeight, Math.round(240 * Theme.networkScale))
        contentWidth:width
        contentHeight:wifiColumn.implicitHeight
        clip:true
        boundsBehavior:Flickable.StopAtBounds
        flickableDirection:Flickable.VerticalFlick
        interactive:contentHeight>height
        Controls.ScrollBar.vertical: Controls.ScrollBar {}
        function reveal(item) {
            const p=item.mapToItem(wifiColumn,0,0);
            const bottom=p.y+item.height;
            if (p.y<contentY) contentY=p.y;
            else if (bottom>contentY+height) contentY=bottom-height;
            contentY=Math.max(0,Math.min(contentY,contentHeight-height));
        }
        Column {
        id:wifiColumn
        width:panel.rowWidth
        spacing:Theme.networkRowGap
        Repeater {
            id: wifiRepeater
            // All rows stay reachable; no silent eight-network truncation.
            model: Net.wifiEnabled ? panel.shownNetworks : []
            Column {
                id: entry
                required property var modelData
                required property int index
                readonly property bool asksPassword: panel.pendingNetwork === modelData.key
                readonly property Item focusTarget: wifiRow
                width:panel.rowWidth
                spacing:Theme.networkRowGap
                Heading { width:parent.width; text:panel.section(entry.index); visible:text!=="" }
                InteractiveSurface {
                    id: wifiRow
                    width:panel.rowWidth
                    implicitHeight: labels.implicitHeight + Theme.networkRowInset
                    radius:Theme.radius
                    color: activeFocus ? Theme.networkHover : entry.modelData.connected ? Theme.networkSelected : "transparent"
                    border.width:activeFocus ? Theme.borderWidth : 0
                    border.color:Theme.networkOutline
                    accessibleName: entry.modelData.name
                    accessibleDescription: (entry.modelData.connected ? "Connected; " : entry.modelData.known ? "Saved; " : "")
                        + (entry.modelData.security !== WifiSecurityType.Open ? "Secured" : "Open")
                        + "; signal " + Net.percentOf(entry.modelData.signalStrength) + " percent"
                    accessibleSelected:entry.modelData.connected
                    onActiveFocusChanged:if(activeFocus) wifiViewport.reveal(wifiRow)
                    onTriggered: {
                        if (entry.modelData.connected) { Net.disconnect(entry.modelData); return; }
                        if (Net.needsPassword(entry.modelData)) {
                            panel.passwordText="";
                            panel.pendingNetwork=entry.modelData.key;
                            Qt.callLater(()=>pskField.forceActiveFocus(Qt.TabFocusReason));
                            return;
                        }
                        Net.connect(entry.modelData,"");
                    }
                    Line {
                        x:Theme.networkRowInset; anchors.verticalCenter:parent.verticalCenter
                        width:Theme.networkIconSlot
                        text:Icons.wifiSignal(entry.modelData.signalStrength)
                        font.pixelSize:Theme.networkTitleSize
                    }
                    Column {
                        id:labels
                        x:Theme.networkRowInset+Theme.networkIconSlot+Theme.networkRowInset
                        width:parent.width-x-Theme.networkIconSlot-Theme.networkRowInset*2
                        anchors.verticalCenter:parent.verticalCenter
                        Line { width:parent.width; text:entry.modelData.name; elide:Text.ElideRight }
                        Line {
                            width:parent.width
                            text:entry.modelData.connected ? (Net.hasCaptivePortal ? "Sign-in required" : "Connected") : ""
                            visible:text!==""
                            font.pixelSize:Theme.networkCaptionSize
                            color:Theme.networkSecondary
                        }
                    }
                    Line {
                        anchors.right:parent.right; anchors.rightMargin:Theme.networkRowInset; anchors.verticalCenter:parent.verticalCenter
                        text:entry.modelData.security !== WifiSecurityType.Open ? Icons.cp(0xF033E) : ""
                        font.pixelSize:Theme.networkTitleSize; color:Theme.networkSecondary
                    }
                    HoverHandler { cursorShape:Qt.PointingHandCursor; onHoveredChanged:if(hovered && panel.pendingNetwork==="") wifiRow.forceActiveFocus(Qt.MouseFocusReason) }
                    TapHandler { onTapped:{wifiRow.forceActiveFocus(Qt.MouseFocusReason);wifiRow.activate();} }
                }
                TextField {
                    id:pskField
                    width:panel.rowWidth
                    visible:entry.asksPassword
                    password:true
                    onActiveFocusChanged:if(activeFocus) wifiViewport.reveal(pskField)
                    text:entry.asksPassword ? panel.passwordText : ""
                    placeholderText:"Passphrase, Enter connects"
                    font.pixelSize:Theme.fontSize
                    accessibleName:"Wi-Fi password"
                    accessibleDescription:"Enter connects to "+entry.modelData.name
                    onTextEdited: if(entry.asksPassword) panel.passwordText=text
                    onAccepted: {
                        if(!entry.asksPassword || panel.passwordText.length===0) return;
                        Net.connect(entry.modelData,panel.passwordText);
                        panel.cancelPassword(entry.modelData.key);
                    }
                    Keys.onEscapePressed:panel.cancelPassword(entry.modelData.key)
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
    }}
