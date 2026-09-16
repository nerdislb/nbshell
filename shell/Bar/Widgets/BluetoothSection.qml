import QtQuick
import QtQuick.Controls as Controls
import qs.Common
import qs.Services
import qs.Widgets

// Omarchy's Bluetooth hierarchy inside nbshell's combined control panel.
// The backend and its bounded, explicitly requested scan remain unchanged.
Column {
    id: section
    property real rowWidth: Theme.networkWidth
    property string pendingRemoval: ""
    property var shownDevices: []
    readonly property Item initialFocusItem: radio
    readonly property var liveRows: Bt.sorted.map(d => ({
        address: String(d.address || ""), label: Bt.label(d),
        connected: !!d.connected, paired: !!d.paired, bonded: !!d.bonded,
        pairing: !!d.pairing, batteryAvailable: !!d.batteryAvailable,
        battery: Number(d.battery || 0)
    })).sort((a,b) => rank(a)-rank(b) || a.label.localeCompare(b.label))
    width: rowWidth
    spacing: Theme.bluetoothGap

    function rank(d) { return d.connected ? 0 : d.paired || d.bonded ? 1 : 2; }
    function groupTitle(index) {
        const r=rank(shownDevices[index]);
        return index > 0 && rank(shownDevices[index-1]) === r ? "" : ["CONNECTED","PAIRED","AVAILABLE"][r];
    }
    function deviceFor(address) {
        return Bt.devices.find(d => String(d.address || "") === address) ?? null;
    }
    function focusBookmark() {
        if (!devices) return null;
        for (let i=0; i<devices.count; i++) {
            const entry=devices.itemAt(i);
            if (entry.action.activeFocus || entry.forgetAction.activeFocus)
                return {address:entry.modelData.address,forget:entry.forgetAction.activeFocus};
        }
        return null;
    }
    function restoreFocus(bookmark) {
        if (!bookmark) return;
        for (let i=0; i<devices.count; i++) {
            const entry=devices.itemAt(i);
            if (entry.modelData.address !== bookmark.address) continue;
            (bookmark.forget && entry.canForget ? entry.forgetAction : entry.action).forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        radio.forceActiveFocus(Qt.TabFocusReason);
    }
    function refresh() {
        const bookmark=focusBookmark();
        if (!Bt.enabled || !liveRows.some(d => d.address === pendingRemoval)) pendingRemoval="";
        shownDevices=Bt.enabled ? liveRows : [];
        Qt.callLater(() => restoreFocus(bookmark));
    }
    onLiveRowsChanged: refresh()
    Connections { target:Bt; function onEnabledChanged() { section.refresh(); } }
    Component.onCompleted: refresh()

    function forget(address) {
        const device=deviceFor(address);
        if (!device || !Bt.enabled || Bt.pairingAddress === address) { pendingRemoval=""; return; }
        if (pendingRemoval !== address) { pendingRemoval=address; return; }
        pendingRemoval="";
        Bt.forgetDevice(device);
    }
    Keys.onEscapePressed: event => {
        if (pendingRemoval !== "") { pendingRemoval=""; event.accepted=true; }
        else event.accepted=false;
    }

    component Caption: Line {
        font.pixelSize: Theme.networkCaptionSize
        font.bold: true
        font.letterSpacing: 1.2
        color: Theme.networkSecondary
    }
    Item {
        width:section.rowWidth
        implicitHeight:Math.max(hero.implicitHeight, labels.implicitHeight, radio.implicitHeight)
        Line {
            id:hero
            anchors.left:parent.left; anchors.verticalCenter:parent.verticalCenter
            text:Bt.enabled ? (Bt.connected.length ? Icons.bluetoothConnected : Icons.bluetooth) : Icons.bluetoothOff
            font.pixelSize:Theme.networkHeroSize
            color:Bt.enabled ? Theme.fg : Theme.networkSecondary
        }
        Column {
            id:labels
            anchors.left:hero.right; anchors.leftMargin:Theme.bluetoothGap
            anchors.right:radio.left; anchors.rightMargin:Theme.networkGap
            anchors.verticalCenter:parent.verticalCenter
            spacing:Theme.networkRowGap/2
            Line { width:parent.width; text:"Bluetooth"; font.bold:true; font.pixelSize:Theme.networkTitleSize; elide:Text.ElideRight }
            Caption {
                width:parent.width; elide:Text.ElideRight
                text:!Bt.available ? "NO ADAPTER" : !Bt.enabled ? "OFF" : Bt.discovering ? "SCANNING…"
                    : Bt.connected.length ? Bt.connected.length+" CONNECTED" : "ON"
            }
        }
        InteractiveSurface {
            id:radio
            anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter
            implicitWidth:Math.round(Theme.networkSwitchHeight*1.9)+Theme.networkRowInset
            implicitHeight:Theme.networkSwitchHeight+Theme.networkRowInset
            activationBlocked:!Bt.available
            accessibleName:Bt.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
            accessibleDescription:Bt.available ? "Bluetooth radio" : "No Bluetooth adapter available"
            accessibleRole:Accessible.CheckBox
            accessibleCheckable:true
            accessibleChecked:Bt.enabled
            color:activeFocus ? Theme.networkHover : "transparent"
            border.width:activeFocus ? Theme.borderWidth : 0
            border.color:Theme.networkOutline
            radius:Theme.radius
            onTriggered:Bt.setEnabled(!Bt.enabled)
            Rectangle {
                anchors.centerIn:parent
                width:Math.round(Theme.networkSwitchHeight*1.9); height:Theme.networkSwitchHeight
                radius:Theme.radius > 0 ? height/2 : 0
                color:Bt.enabled ? Theme.networkSelected : "transparent"
                border.width:Bt.enabled ? 0 : Theme.borderWidth
                border.color:Theme.panelBorder
                opacity:Bt.available ? 1 : Theme.controlDisabledOpacity
                Rectangle {
                    x:Bt.enabled ? parent.width-width-3 : 3
                    anchors.verticalCenter:parent.verticalCenter
                    width:parent.height-6; height:width
                    radius:Theme.radius > 0 ? height/2 : 0
                    color:Bt.enabled ? Theme.accent : Theme.networkSecondary
                }
            }
            HoverHandler { id:radioHover; cursorShape:Qt.PointingHandCursor; onHoveredChanged:if(hovered) radio.forceActiveFocus(Qt.MouseFocusReason) }
            TapHandler { onTapped:{radio.forceActiveFocus(Qt.MouseFocusReason);radio.activate();} }
            Controls.ToolTip.visible:radioHover.hovered
            Controls.ToolTip.text:radio.accessibleName
        }
    }
    ActionButton {
        id:scan
        visible:Bt.available && Bt.enabled
        text:Bt.requested ? "Stop scanning" : "Scan for devices"
        compact:true
        accessibleName:text
        // Discovery by another client is status, not ownership of our scan.
        onTriggered:Bt.toggleScan()
    }
    Line {
        width:section.rowWidth
        visible:!Bt.available || !Bt.enabled || section.shownDevices.length===0
        text:!Bt.available ? "No Bluetooth adapter available" : !Bt.enabled ? "Turn Bluetooth on to scan"
            : Bt.discovering ? "Scanning for devices…" : "No devices found. Put a device in pairing mode and scan."
        color:Theme.networkSecondary
        wrapMode:Text.WordWrap
    }
    Line {
        width:section.rowWidth
        visible:Bt.pairingError!=="" && Bt.pairingAddress===""
        text:Bt.pairingError
        color:Theme.readable(Theme.red,Theme.bg,4.5)
        wrapMode:Text.WordWrap
    }
    Flickable {
        id:viewport
        width:section.rowWidth
        height:Math.min(deviceColumn.implicitHeight,Theme.bluetoothListHeight)
        contentWidth:width
        contentHeight:deviceColumn.implicitHeight
        clip:true
        boundsBehavior:Flickable.StopAtBounds
        flickableDirection:Flickable.VerticalFlick
        interactive:contentHeight>height
        Controls.ScrollBar.vertical:Controls.ScrollBar {}
        function reveal(item) {
            const p=item.mapToItem(deviceColumn,0,0);
            if (p.y<contentY) contentY=p.y;
            else if (p.y+item.height>contentY+height) contentY=p.y+item.height-height;
            contentY=Math.max(0,Math.min(contentY,Math.max(0,contentHeight-height)));
        }
        Column {
            id:deviceColumn
            width:section.rowWidth
            spacing:Theme.bluetoothRowGap
            Repeater {
                id:devices
                model:section.shownDevices
                Column {
                    id:entry
                    required property var modelData
                    required property int index
                    property alias action:deviceAction
                    property alias forgetAction:removeButton
                    readonly property bool canForget:modelData.connected || modelData.paired || modelData.bonded
                    readonly property bool pairing:modelData.pairing || Bt.pairingAddress===modelData.address
                    readonly property string status:pairing ? "Pairing…" : modelData.connected
                        ? (modelData.batteryAvailable ? Math.round(modelData.battery*100)+"% battery" : "Connected") : ""
                    width:section.rowWidth
                    spacing:Theme.bluetoothRowGap
                    Caption { width:parent.width; text:section.groupTitle(entry.index); visible:text!=="" }
                    Item {
                        width:section.rowWidth
                        implicitHeight:Math.max(deviceLabels.implicitHeight,Theme.networkSwitchHeight)+Theme.networkRowInset
                        InteractiveSurface {
                            id:deviceAction
                            anchors.fill:parent
                            // Separate sibling remove control: pointer/key/AT paths cannot
                            // accidentally activate both connect and forget.
                            accessibleName:entry.modelData.label
                            accessibleDescription:(entry.modelData.connected ? "Disconnect; " : entry.canForget ? "Connect; " : "Pair; ")+entry.status
                            accessibleSelected:entry.modelData.connected
                            activationBlocked:!Bt.enabled || entry.pairing || entry.modelData.address===""
                            color:activeFocus ? Theme.networkHover : entry.modelData.connected ? Theme.networkSelected : "transparent"
                            border.width:activeFocus ? Theme.borderWidth : 0
                            border.color:Theme.networkOutline
                            radius:Theme.radius
                            onActiveFocusChanged:if(activeFocus) viewport.reveal(deviceAction)
                            onTriggered: {
                                section.pendingRemoval="";
                                const device=section.deviceFor(entry.modelData.address);
                                if(device) Bt.toggleDevice(device);
                            }
                            HoverHandler { id:rowHover; cursorShape:Qt.PointingHandCursor; onHoveredChanged:if(hovered && !removeHover.hovered) deviceAction.forceActiveFocus(Qt.MouseFocusReason) }
                            TapHandler {
                                enabled:!removeHover.hovered
                                onTapped:eventPoint => {
                                    const p=eventPoint.position;
                                    if (removeButton.visible && p.x>=removeButton.x && p.x<=removeButton.x+removeButton.width
                                            && p.y>=removeButton.y && p.y<=removeButton.y+removeButton.height) return;
                                    deviceAction.forceActiveFocus(Qt.MouseFocusReason);
                                    deviceAction.activate();
                                }
                            }
                        }
                        Line {
                            x:Theme.networkRowInset; anchors.verticalCenter:parent.verticalCenter
                            text:entry.modelData.connected ? Icons.bluetoothConnected : Icons.bluetooth
                            font.pixelSize:Theme.networkTitleSize*1.3
                        }
                        Column {
                            id:deviceLabels
                            x:Theme.networkRowInset*2+Theme.networkIconSlot
                            width:parent.width-x-Theme.networkRowInset-removeButton.width
                            anchors.verticalCenter:parent.verticalCenter
                            spacing:Theme.networkRowGap/4
                            Line { width:parent.width; text:entry.modelData.label; elide:Text.ElideRight }
                            Line { width:parent.width; text:entry.status; visible:text!==""; font.pixelSize:Theme.networkCaptionSize; color:Theme.networkSecondary; elide:Text.ElideRight }
                        }
                        InteractiveSurface {
                            id:removeButton
                            anchors.right:parent.right; anchors.rightMargin:Theme.networkRowInset/2; anchors.verticalCenter:parent.verticalCenter
                            implicitWidth:Theme.networkIconSlot+Theme.networkRowInset
                            implicitHeight:Theme.networkSwitchHeight+Theme.networkRowInset
                            readonly property bool confirming:section.pendingRemoval===entry.modelData.address
                            visible:entry.canForget && (rowHover.hovered || deviceAction.activeFocus || activeFocus || confirming)
                            activationBlocked:entry.pairing || !Bt.enabled || entry.modelData.address===""
                            accessibleName:(confirming ? "Confirm forget " : "Forget ")+entry.modelData.label
                            accessibleDescription:confirming ? "Remove saved pairing; activate again to confirm, Escape cancels" : "Requires confirmation"
                            color:activeFocus ? Theme.networkHover : "transparent"
                            radius:Theme.radius
                            border.width:activeFocus ? Theme.borderWidth : 0
                            border.color:confirming ? Theme.readable(Theme.red,Theme.bg,3) : Theme.networkOutline
                            onActiveFocusChanged:if(activeFocus) viewport.reveal(removeButton)
                            onTriggered:section.forget(entry.modelData.address)
                            Line { anchors.centerIn:parent; text:removeButton.confirming ? Icons.cp(0xF012C) : Icons.cp(0xF0159); color:removeButton.confirming ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.networkSecondary }
                            HoverHandler { id:removeHover; cursorShape:Qt.PointingHandCursor; onHoveredChanged:if(hovered) removeButton.forceActiveFocus(Qt.MouseFocusReason) }
                            TapHandler { onTapped:{removeButton.forceActiveFocus(Qt.MouseFocusReason);removeButton.activate();} }
                            Controls.ToolTip.visible:removeHover.hovered
                            Controls.ToolTip.text:removeButton.accessibleName
                        }
                    }
                }
            }
        }
    }
}
