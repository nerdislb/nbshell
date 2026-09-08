import QtQuick
import QtQuick.Dialogs
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: root
    signal back()
    implicitHeight: contents.height
    Keys.onEscapePressed: root.back()

    FileDialog {
        id: chooser
        property int phaseIndex: -1
        property string field: "image"
        title: field === "image" ? "Choose a still wallpaper" : "Choose a wallpaper loop"
        fileMode: FileDialog.OpenFile
        nameFilters: field === "image" ? ["Images (*.png *.jpg *.jpeg *.webp)"] : ["Videos (*.mp4 *.webm *.mkv *.mov)"]
        onAccepted: {
            var url = String(selectedFile);
            if (url.indexOf("file:///") === 0)
                DynamicWallpaper.update(field, decodeURIComponent(url.slice(7)), phaseIndex);
        }
    }
    function choose(field, index) {
        chooser.field = field;
        chooser.phaseIndex = index;
        chooser.open();
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        clip: true
        contentHeight: contents.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: contents
            width: scroll.width
            spacing: Theme.spaceLg
            Row {
                spacing: Theme.spaceSm
                ControlButton { focus: true; text: "BACK"; onTriggered: root.back() }
                Line { text: "DYNAMIC WALLPAPER"; height: Theme.controlHeight; verticalAlignment: Text.AlignVCenter }
            }
            Line {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Settings save immediately. Times use your local clock. Empty image slots use the current theme wallpaper."
                color: Theme.fgDim
            }
            Flow {
                width: parent.width
                spacing: Theme.spaceSm
                ControlButton {
                    text: "DAYTIME " + (selected ? "ON" : "OFF")
                    selected: DynamicWallpaper.settings.daytimeEnabled
                    onTriggered: DynamicWallpaper.update("daytimeEnabled", !selected)
                }
                ControlButton {
                    text: "VIDEO " + (selected ? "ON" : "OFF")
                    selected: DynamicWallpaper.settings.videoEnabled
                    onTriggered: DynamicWallpaper.update("videoEnabled", !selected)
                }
            }
            Line {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Loops are silent and only run on mains power (or a desktop without a battery). Any window on this screen's active workspace, the native lock, idle screen-off or Reduced Motion switches to the still image and releases the player."
                color: Theme.fgDim
            }
            Line {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: DynamicWallpaper.reason(Compositor.focusedScreen?.name ?? "")
                color: DynamicWallpaper.error ? Theme.red : Theme.accent
            }
            Repeater {
                model: DynamicWallpaper.settings.daytimeEnabled ? 4 : 1
                Column {
                    id: slot
                    required property int index
                    readonly property int phaseIndex: DynamicWallpaper.settings.daytimeEnabled ? index : -1
                    readonly property var entry: phaseIndex >= 0 ? DynamicWallpaper.settings.phases[phaseIndex] : DynamicWallpaper.settings
                    width: contents.width
                    spacing: Theme.spaceSm
                    Row {
                        spacing: Theme.spaceMd
                        Line {
                            text: slot.phaseIndex >= 0 ? slot.entry.name : "ALL DAY"
                            width: Theme.cellW * 12
                            height: Theme.controlHeight
                            verticalAlignment: Text.AlignVCenter
                        }
                        TextField {
                            visible: slot.phaseIndex >= 0
                            width: Theme.cellW * 10
                            text: slot.entry.time || ""
                            placeholderText: "HH:MM"
                            accessibleName: slot.entry.name + " start time"
                            maximumLength: 5
                            onEditingFinished: {
                                if (!DynamicWallpaper.update("time", text, slot.phaseIndex))
                                    text = slot.entry.time;
                            }
                        }
                    }
                    Repeater {
                        model: ["image", "video"]
                        Column {
                            id: fileRow
                            required property string modelData
                            width: slot.width
                            spacing: Theme.spaceXs
                            Row {
                                spacing: Theme.spaceSm
                                ControlButton {
                                    text: fileRow.modelData === "image" ? "CHOOSE IMAGE" : "CHOOSE VIDEO"
                                    accessibleName: text + " · " + (slot.entry.name || "All day")
                                    onTriggered: root.choose(fileRow.modelData, slot.phaseIndex)
                                }
                                ControlButton {
                                    text: "CLEAR"
                                    enabled: !!slot.entry[fileRow.modelData]
                                    accessibleName: "Clear " + fileRow.modelData + " · " + (slot.entry.name || "All day")
                                    onTriggered: DynamicWallpaper.update(fileRow.modelData, "", slot.phaseIndex)
                                }
                            }
                            Line {
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                text: slot.entry[fileRow.modelData] || (fileRow.modelData === "image" ? "Current theme wallpaper" : "No loop assigned")
                                color: Theme.fgDim
                                font.pixelSize: Theme.fontCaption
                            }
                        }
                    }
                }
            }
            Line {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fgDim
                text: "Start with a short 720p or 1080p loop at 24–30 fps. Each screen plays its own video. A matching still image makes battery and window transitions unobtrusive."
            }
        }
    }
    // Keep keyboard-focused controls visible even on a small screen.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            var item = root.Window.window.activeFocusItem;
            if (!root.visible || !item) return;
            var ancestor = item;
            while (ancestor && ancestor !== contents) ancestor = ancestor.parent;
            if (!ancestor) return;
            var point = item.mapToItem(contents, 0, 0);
            if (point.y < scroll.contentY) scroll.contentY = Math.max(0, point.y);
            else if (point.y + item.height > scroll.contentY + scroll.height)
                scroll.contentY = Math.min(Math.max(0, contents.height - scroll.height), point.y + item.height - scroll.height);
        }
    }
}
