import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root
    property var service: null
    property string sourcePath: ""
    property string filename: ""
    readonly property bool current: service && service.mediaSavePath === sourcePath
    readonly property string error: current ? service.mediaSaveError : ""
    width: Theme.cellW * 16
    spacing: Theme.spaceXs

    ActionButton {
        objectName: "saveMediaButton"
        width: parent.width
        compact: true
        text: root.current && root.service.mediaSaveDone ? "Saved" : "Save as…"
        busy: root.current && root.service.mediaSaveBusy
        enabled: root.service !== null && root.sourcePath.startsWith("/")
            && (!root.service.mediaSaveBusy || root.current)
        accessibleDescription: root.error || "Save attachment to a folder of your choice"
        onTriggered: root.service.saveMedia(root.sourcePath, root.filename)
    }
    Line {
        width: parent.width
        visible: root.error !== ""
        text: root.error
        color: Theme.readable(Theme.red, Theme.bg)
        font.pixelSize: Theme.fontCaption
        wrapMode: Text.Wrap
    }
}
