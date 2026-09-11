import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import "TrayPreferences.js" as Preferences

Item {
    id: root
    required property var items
    required property var preferences
    required property var setMode
    property real availableWidth: Theme.cellW * 44
    property real availableHeight: Theme.cellH * 24
    property var closePopout: () => {}
    readonly property Item initialFocusItem: {
        for (let i = 0; i < entries.count; ++i) {
            const control = entries.itemAt(i)?.firstControl;
            if (control?.enabled)
                return control;
        }
        return done;
    }
    implicitWidth: Math.min(Theme.cellW * 44, availableWidth)
    implicitHeight: Math.min(content.implicitHeight, availableHeight)

    function reveal(control) {
        const point = control.mapToItem(content, 0, 0);
        if (point.y < viewport.contentY)
            viewport.contentY = point.y;
        else if (point.y + control.height > viewport.contentY + viewport.height)
            viewport.contentY = point.y + control.height - viewport.height;
    }

    Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar {
            width: Theme.borderWidth * 3
            policy: viewport.contentHeight > viewport.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
            active: policy === ScrollBar.AlwaysOn
            contentItem: Rectangle { color: Theme.accent; radius: Theme.radius }
            background: Rectangle { color: Theme.muted; radius: Theme.radius }
        }
        Column {
            id: content
            width: viewport.width - Theme.cellW
            spacing: Theme.spaceSm
            PanelHead { rowWidth: content.width; title: "Tray icons" }
            Line {
                width: content.width
                text: "Pin keeps an app visible. Hide removes it from the tray."
                wrapMode: Text.WordWrap
                color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
            }
            Repeater {
                id: entries
                model: root.items
                Column {
                    id: entry
                    required property var modelData
                    readonly property Item firstControl: pin
                    width: content.width
                    spacing: Theme.spaceXs
                    readonly property string mode: Preferences.mode(root.preferences, modelData)
                    Line {
                        width: parent.width
                        text: entry.modelData.title || entry.modelData.id || "Unnamed app"
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: Theme.spaceSm
                        ActionButton {
                            id: pin
                            text: entry.mode === "pinned" ? "Unpin" : "Pin"
                            compact: true
                            enabled: Preferences.key(entry.modelData) !== ""
                            tone: entry.mode === "pinned" ? "primary" : "secondary"
                            accessibleName: text + " " + (entry.modelData.title || entry.modelData.id || "app")
                            accessibleCheckable: true
                            accessibleChecked: entry.mode === "pinned"
                            onTriggered: root.setMode(entry.modelData, entry.mode === "pinned" ? "drawer" : "pinned")
                            onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        }
                        ActionButton {
                            text: entry.mode === "hidden" ? "Show" : "Hide"
                            compact: true
                            enabled: Preferences.key(entry.modelData) !== ""
                            tone: entry.mode === "hidden" ? "primary" : "secondary"
                            accessibleName: text + " " + (entry.modelData.title || entry.modelData.id || "app")
                            accessibleCheckable: true
                            accessibleChecked: entry.mode === "hidden"
                            onTriggered: root.setMode(entry.modelData, entry.mode === "hidden" ? "drawer" : "hidden")
                            onActiveFocusChanged: if (activeFocus) root.reveal(this)
                        }
                    }
                    Line {
                        width: parent.width
                        visible: Preferences.key(entry.modelData) === ""
                        text: "This app provides no stable ID."
                        wrapMode: Text.WordWrap
                        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
                    }
                }
            }
            Line {
                visible: root.items.length === 0
                text: "No tray apps running."
                color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
            }
            Line {
                width: content.width
                visible: Config.writeError !== ""
                text: Config.writeError ? "Could not save tray settings: " + Config.writeError : ""
                wrapMode: Text.WrapAnywhere
                color: Theme.readable(Theme.red, Theme.bg, 4.5)
            }
            ActionButton {
                id: done
                text: "Done"
                compact: true
                onTriggered: root.closePopout()
                onActiveFocusChanged: if (activeFocus) root.reveal(this)
            }
        }
    }
}
