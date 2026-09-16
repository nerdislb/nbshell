import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Omarchy-sized battery view; nbshell's tuned and device-battery sources stay.
Column {
    id: panel
    property var closePopout: null
    property real availableWidth: Theme.powerWidth
    // Leave a local gutter for Popout's overlay scroll indicator.
    readonly property real frameWidth: Math.max(1, Math.min(availableWidth,
        Theme.powerWidth - 2 * (Theme.powerPadding + Theme.powerBorderWidth)))
    readonly property real rowWidth: Math.max(1,frameWidth-Theme.networkRowGap)
    readonly property bool batteryAvailable: PowerService.available
    readonly property string batteryStatus: !batteryAvailable ? "UNAVAILABLE" : PowerService.full ? "FULLY CHARGED"
        : PowerService.charging ? "CHARGING" : PowerService.onBattery ? "ON BATTERY" : "PLUGGED IN"
    readonly property color batteryColor: batteryAvailable && PowerService.onBattery && PowerService.percent <= 20
        ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.fg
    readonly property var extraBatteries: {
        const out=Bt.withBattery.map(d=>({label:d.label,percent:d.percent,charging:false,source:"Bluetooth"}));
        for (const d of Kdeconnect.devices) {
            if(d.paired && d.reachable && d.capabilities?.battery && d.charge>=0)
                out.push({label:d.name,percent:d.charge,charging:d.charging,source:"KDE Connect"});
        }
        return out;
    }
    readonly property int missingReports: Math.max(0,Bt.connected.length-Bt.withBattery.length)
    readonly property int selectedIndex: PowerService.profileOptions.findIndex(p=>p.value===PowerService.activeProfile)
    readonly property Item initialFocusItem: selectedIndex>=0 && profiles.count>selectedIndex ? profiles.itemAt(selectedIndex) : refreshButton
    rightPadding: Theme.networkRowGap
    width: frameWidth
    spacing: Theme.powerGap
    Component.onCompleted: PowerService.refreshProfile()

    function focusTargets() {
        const out=[];
        for(let i=0;i<profiles.count;i++) out.push(profiles.itemAt(i));
        if(refreshButton.visible) out.push(refreshButton);
        for(let i=0;i<deviceRows.count;i++) out.push(deviceRows.itemAt(i));
        return out;
    }
    function moveFocus(delta) {
        const items=focusTargets();
        if(!items.length) return;
        const i=items.findIndex(item=>item.activeFocus);
        items[Math.max(0,Math.min(items.length-1,i<0 ? Math.max(0,selectedIndex) : i+delta))].forceActiveFocus(Qt.TabFocusReason);
    }
    Keys.onPressed: event => {
        if(event.modifiers!==Qt.NoModifier) return;
        if([Qt.Key_Left,Qt.Key_Up,Qt.Key_H,Qt.Key_K,Qt.Key_Right,Qt.Key_Down,Qt.Key_L,Qt.Key_J].includes(event.key)) {
            moveFocus([Qt.Key_Left,Qt.Key_Up,Qt.Key_H,Qt.Key_K].includes(event.key) ? -1 : 1);
            event.accepted=true;
        }
    }
    component Caption: Line {
        font.pixelSize:Theme.networkCaptionSize
        color:Theme.networkSecondary
        font.bold:true
        font.letterSpacing:1.2
    }
    component Separator: Rectangle {
        width:panel.rowWidth; height:Math.max(1,Theme.borderWidth)
        color:Theme.mix(Theme.bg,Theme.fg,0.18)
    }
    component Meter: Item {
        property real value:0
        property color ink:Theme.fg
        implicitHeight:Theme.powerMeterHeight
        Accessible.role:Accessible.ProgressBar
        Accessible.name:"Battery charge"
        Accessible.description:Math.round(Math.max(0,Math.min(100,value)))+" percent"
        Rectangle { anchors.fill:parent; radius:height/2; color:Theme.mix(Theme.bg,Theme.fg,0.12) }
        Rectangle {
            width:parent.width*Math.max(0,Math.min(100,parent.value))/100
            height:parent.height; radius:height/2; color:parent.ink
            Behavior on width { NumberAnimation { duration:Theme.motionSpatialFast } }
        }
    }
    Item {
        width:panel.rowWidth
        implicitHeight:Math.max(heroIcon.implicitHeight,heroLabels.implicitHeight,percentage.implicitHeight)
        Line {
            id:heroIcon
            anchors.left:parent.left; anchors.verticalCenter:parent.verticalCenter
            text:PowerService.charging ? Icons.batteryCharge(PowerService.percent) : Icons.battery(PowerService.percent)
            font.pixelSize:Theme.networkHeroSize
            color:panel.batteryColor
        }
        Column {
            id:heroLabels
            anchors.left:heroIcon.right; anchors.leftMargin:Theme.powerGap
            anchors.right:percentage.left; anchors.rightMargin:Theme.networkRowInset
            anchors.verticalCenter:parent.verticalCenter
            spacing:Theme.networkRowGap/2
            Line { text:"Battery"; width:parent.width; elide:Text.ElideRight; font.bold:true; font.pixelSize:Theme.networkTitleSize }
            Caption { text:panel.batteryStatus; width:parent.width; elide:Text.ElideRight }
        }
        Line {
            id:percentage
            anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter
            text:panel.batteryAvailable ? PowerService.percent+"%" : "—"
            font.pixelSize:Theme.powerPercentSize
            font.bold:true
            color:panel.batteryColor
        }
    }
    Meter { width:panel.rowWidth; value:panel.batteryAvailable ? PowerService.percent : 0; ink:panel.batteryColor }
    Grid {
        width:panel.rowWidth
        columns:2
        columnSpacing:Theme.networkRowInset*2
        rowSpacing:Theme.networkRowGap
        Repeater {
            model:[
                {label:PowerService.charging ? "Full in" : "Time left",value:!panel.batteryAvailable || PowerService.full || !PowerService.charging && !PowerService.onBattery ? "—" : PowerService.timeText},
                {label:PowerService.powerLabel,value:panel.batteryAvailable ? PowerService.powerText : "—"},
                {label:"Health",value:panel.batteryAvailable && PowerService.health>0 ? PowerService.health+"%" : "—"},
                {label:"Profile",value:PowerService.activeProfileLabel}
            ]
            Item {
                required property var modelData
                width:(panel.rowWidth-Theme.networkRowInset*2)/2
                implicitHeight:Math.max(label.implicitHeight,value.implicitHeight)
                Line { id:label; width:parent.width/2; text:modelData.label; font.pixelSize:Theme.networkCaptionSize; color:Theme.networkSecondary; elide:Text.ElideRight }
                Line { id:value; x:parent.width/2; width:parent.width/2; text:modelData.value; font.pixelSize:Theme.networkCaptionSize; horizontalAlignment:Text.AlignRight; elide:Text.ElideRight }
            }
        }
    }
    Separator {}
    Caption { text:"POWER PROFILE" }
    Row {
        width:panel.rowWidth
        spacing:Theme.powerProfileGap
        Repeater {
            id:profiles
            model:PowerService.profileOptions
            InteractiveSurface {
                id:choice
                required property var modelData
                required property int index
                readonly property bool current:PowerService.activeProfile===modelData.value
                width:(panel.rowWidth-Theme.powerProfileGap*(profiles.count-1))/Math.max(1,profiles.count)
                implicitHeight:Theme.controlHeight+Theme.networkRowInset
                activationBlocked:PowerService.profileBusy
                accessibleRole:Accessible.RadioButton
                accessibleName:modelData.label
                accessibleCheckable:true
                accessibleChecked:current
                accessibleDescription:PowerService.profileBusy ? "Changing power profile" : current ? "Selected power profile" : "Activate power profile"
                color:current ? Theme.networkSelected : (activeFocus || hover.hovered) ? Theme.networkHover : "transparent"
                border.width:Math.max(1,Theme.borderWidth)
                border.color:activeFocus ? Theme.focusBorder : current ? Theme.networkOutline : Theme.panelBorder
                radius:Theme.radius
                opacity:PowerService.profileBusy ? Theme.controlDisabledOpacity : 1
                onTriggered:PowerService.setProfile(modelData.value)
                Row {
                    anchors.centerIn:parent
                    spacing:Theme.networkRowGap
                    Line {
                        text:choice.modelData.value==="powersave" ? Icons.cp(0xF032A) : choice.modelData.value==="balanced" ? Icons.cp(0xF029A) : Icons.cp(0xF04C5)
                        font.pixelSize:Theme.networkTitleSize
                    }
                    Line {
                        width:Math.max(0,choice.width-Theme.networkIconSlot-Theme.networkRowGap-Theme.networkRowInset)
                        text:choice.modelData.label
                        font.pixelSize:Theme.networkCaptionSize
                        elide:Text.ElideRight
                    }
                }
                HoverHandler { id:hover; cursorShape:Qt.PointingHandCursor }
                TapHandler { onTapped:{choice.forceActiveFocus(Qt.MouseFocusReason);choice.activate();} }
            }
        }
    }
    Line {
        width:panel.rowWidth
        visible:PowerService.profileBusy || PowerService.profileError!==""
        text:PowerService.profileBusy ? "Changing power profile…" : PowerService.profileError
        color:PowerService.profileError!=="" && !PowerService.profileBusy ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.networkSecondary
        wrapMode:Text.WordWrap
    }
    ActionButton {
        id:refreshButton
        visible:PowerService.profileError!=="" || panel.selectedIndex<0
        text:"Refresh power profile"; compact:true
        activationBlocked:PowerService.profileBusy
        onTriggered:PowerService.refreshProfile()
    }
    Separator { visible:panel.extraBatteries.length>0 || panel.missingReports>0 }
    Caption { text:"DEVICE BATTERIES"; visible:panel.extraBatteries.length>0 || panel.missingReports>0 }
    Repeater {
        id:deviceRows
        model:panel.extraBatteries
        Item {
            id:device
            required property var modelData
            width:panel.rowWidth
            implicitHeight:deviceContent.implicitHeight+Theme.networkRowGap*2
            activeFocusOnTab:true
            Accessible.role:Accessible.StaticText
            Accessible.name:modelData.label+", "+modelData.source+", "+modelData.percent+" percent"+(modelData.charging ? ", charging" : "")
            Accessible.focusable:true
            Accessible.focused:activeFocus
            Rectangle { anchors.fill:parent; color:"transparent"; border.width:device.activeFocus ? Theme.borderWidth : 0; border.color:Theme.focusBorder; radius:Theme.radius }
            Column {
                id:deviceContent
                x:Theme.networkRowGap; y:Theme.networkRowGap
                width:parent.width-Theme.networkRowGap*2
                spacing:Theme.networkRowGap
                Item {
                    width:parent.width
                    implicitHeight:deviceName.implicitHeight
                    Line {
                        id:deviceName
                        width:parent.width-devicePercent.implicitWidth-Theme.networkRowInset
                        text:device.modelData.label+" · "+device.modelData.source
                        elide:Text.ElideRight
                    }
                    Line {
                        id:devicePercent
                        anchors.right:parent.right
                        text:device.modelData.percent+"%"+(device.modelData.charging ? " ↑" : "")
                        color:device.modelData.percent<=15 && !device.modelData.charging ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.fg
                    }
                }
                Meter { width:parent.width; value:device.modelData.percent; ink:device.modelData.percent<=15 && !device.modelData.charging ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.fg; Accessible.name:device.modelData.label+" battery" }
            }
        }
    }
    Line {
        width:panel.rowWidth
        visible:panel.missingReports>0
        text:panel.missingReports+(panel.missingReports===1 ? " Bluetooth device connected without a battery report" : " Bluetooth devices connected without battery reports")
        color:Theme.networkSecondary
        wrapMode:Text.WordWrap
    }
}
