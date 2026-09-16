import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// Omarchy-sized passive toast; history retains source/time and full actions.
// Lifetime and hover accounting remain owned by Notify, once across outputs.
PanelSurface {
    id: root
    required property var entry
    signal opened()
    signal removed()

    readonly property bool urgent: entry.urgency === NotificationUrgency.Critical || entry.urgency === 2
    readonly property string plainBody: Notify.plain(entry.body || "")
    readonly property bool singleLine: plainBody.length === 0
    readonly property string glyph: Notify.sourceGlyph(entry)
    readonly property string iconPath: resolveIcon(Notify.sourceIcon(entry))
    readonly property bool iconAvailable: iconPath !== "" && appIcon.status !== Image.Error
    readonly property bool compactGlyph: singleLine && glyph !== "" && !iconAvailable
    readonly property bool hasIcon: iconAvailable || glyph !== ""
    readonly property real verticalInset: singleLine ? Theme.toastCompactPadding : Theme.toastPaddingY

    function resolveIcon(value) {
        const raw=String(value || "");
        if(raw.startsWith("file://") || raw.startsWith("image://")) return raw;
        if(raw.startsWith("/")) return "file://"+raw;
        if(raw==="" || raw.indexOf("://")>=0) return "";
        return Quickshell.iconPath(raw,true);
    }
    function activate() { root.opened(); }

    implicitWidth: Theme.toastWidth
    implicitHeight: Math.max(textColumn.implicitHeight,iconSlot.height)+2*(verticalInset+border.width)
    color: Theme.bg
    accentBorder: true
    border.width: Theme.toastBorderWidth
    border.color: urgent ? Theme.readable(Theme.red,Theme.bg,3) : Theme.focusBorder

    Accessible.role: Accessible.AlertMessage
    Accessible.name: entry.summary || Notify.sourceName(entry)
    Accessible.description: [Notify.sourceName(entry),plainBody,Notify.ago(entry.time),
        urgent ? "Urgent" : "",(entry.repeat || 1)>1 ? "Repeated "+entry.repeat+" times" : ""].filter(part=>part!=="").join("; ")
    Accessible.onPressAction: root.activate()

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: Notify.setPopupHovered(root.entry.key, hovered)
    }
    Component.onDestruction: {
        if(hover.hovered) Notify.setPopupHovered(root.entry.key,false);
    }

    // Keep the existing passive handler path, with explicit close exclusion.
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: function(point,button) {
            if(button===Qt.RightButton) { root.removed(); return; }
            // Child and parent handlers may both observe the tap. Reserve the
            // close hit box even if dismissal hides the child during dispatch.
            const p=closeButton.mapFromItem(root,point.position.x,point.position.y);
            if(p.x>=0 && p.y>=0 && p.x<closeButton.width && p.y<closeButton.height) return;
            root.activate();
        }
    }
    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.toastPaddingX+root.border.width
        anchors.rightMargin: Theme.toastPaddingX+root.border.width
        anchors.topMargin: root.verticalInset+root.border.width
        anchors.bottomMargin: root.verticalInset+root.border.width
        Item {
            id: iconSlot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasIcon
            width: !visible ? 0 : root.compactGlyph ? Theme.toastGlyphSize : Theme.toastIconSize
            height: root.compactGlyph ? glyphText.implicitHeight : width
            Image {
                id: appIcon
                anchors.fill: parent
                source: root.iconPath
                sourceSize.width: Math.ceil(Theme.toastIconSize*Screen.devicePixelRatio)
                sourceSize.height: Math.ceil(Theme.toastIconSize*Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                mipmap: true
                visible: root.iconAvailable
            }
            Line {
                id: glyphText
                anchors.centerIn: parent
                visible: root.glyph!=="" && !root.iconAvailable
                text: root.glyph
                font.pixelSize: root.compactGlyph ? Theme.toastGlyphSize : Theme.toastIconSize
            }
        }
        Column {
            id: textColumn
            anchors.left: iconSlot.right
            anchors.leftMargin: !root.hasIcon ? 0 : root.compactGlyph ? Theme.toastCompactGap : Theme.toastPaddingX
            anchors.right: parent.right
            anchors.rightMargin: Theme.toastCloseReserve
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.toastTextGap
            Line {
                width: parent.width
                visible: text!==""
                text: root.entry.summary || (root.plainBody==="" ? Notify.sourceName(root.entry) : "")
                font.family: Theme.toastFontFamily
                font.pixelSize: Theme.toastFontSize
                font.bold: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Line {
                width: parent.width
                visible: text!==""
                text: root.plainBody
                color: Theme.toastBodyColor
                font.family: Theme.toastFontFamily
                font.pixelSize: Theme.toastFontSize
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }
    InteractiveSurface {
        id: closeButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.border.width+Theme.toastCloseInset
        width: Theme.toastCloseSize
        height: width
        visible: hover.hovered
        keyboardFocusable: false
        accessibleName: "Dismiss notification"
        accessibleDescription: root.entry.summary || Notify.sourceName(root.entry)
        color: closeHover.hovered ? Theme.networkHover : "transparent"
        radius: Theme.radius
        onTriggered: root.removed()
        Line {
            anchors.centerIn: parent
            text: "×"
            font.pixelSize: Theme.toastCloseSize
            color: closeHover.hovered ? Theme.fg : Theme.toastBodyColor
        }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: closeButton.activate() }
    }
}
