import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// One quiet bar entry for the two closely related inboxes. Existing notify
// and clipboard IPC commands still open their respective tab directly.
Cell {
    id: root

    function selectTab(name) {
        Runtime.activityTab = name;
        if (name === "notifications")
            Notify.markSeen();
        if (!root.popoutVisible)
            return;
        // Set the destination first so the old IPC flag can be cleared
        // without briefly closing the shared popout.
        if (name === "clipboard") {
            Runtime.clipOpen = true;
            Runtime.notifyOpen = false;
        } else {
            Runtime.notifyOpen = true;
            Runtime.clipOpen = false;
        }
    }

    interactive: true
    popoutTakesKeyboard: true
    popoutCloseOnLeave: false
    popoutInsetBorder: true
    popoutPadding: Theme.activityPadding
    popoutBorderWidth: Theme.networkBorderWidth
    quiet: false
    slotChars: 0
    label: Notify.dnd ? "DND" : "INBOX"
    icon: Notify.dnd ? Icons.bellOff : Icons.bell
    text: Notify.unreadCount > 0 ? "•" : ""
    color: Notify.dnd ? Theme.fgDim : (Notify.count > 0 ? Theme.text : Theme.textDim)

    onRightClicked: Notify.setDnd(!Notify.dnd)

    preview: Component {
        BarPreview {
            icon: Notify.dnd ? Icons.bellOff : Icons.bell
            title: "Activity"
            subtitle: Notify.dnd ? "Do not disturb" : "Notifications and clipboard"
            badge: Notify.unreadCount > 0 ? "NEW" : ""
            badgeColor: Theme.accent
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Notifications", "value": String(Notify.count) },
                        { "label": "Clipboard", "value": String(Clipboard.entries.length + Clipboard.images.length) }
                    ]
                },
                Repeater {
                    model: Notify.history.slice(0, 2)
                    Line {
                        required property var modelData
                        width: parent.width
                        text: (modelData.appName || "Message") + "  ·  " + (modelData.summary || modelData.body || "")
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                }
            ]
        }
    }

    onPopoutVisibleChanged: {
        if (root.popoutVisible) {
            if (Runtime.activityTab === "clipboard")
                Runtime.clipOpen = true;
            else {
                Runtime.notifyOpen = true;
                Notify.markSeen();
            }
        } else {
            Runtime.notifyOpen = false;
            Runtime.clipOpen = false;
        }
    }

    Connections {
        target: Runtime

        function onNotifyOpenChanged() {
            if (Runtime.notifyOpen) {
                Runtime.activityTab = "notifications";
                Runtime.clipOpen = false;
                root.setPopout(true);
            } else if (!Runtime.clipOpen) {
                root.setPopout(false);
            }
        }

        function onClipOpenChanged() {
            if (Runtime.clipOpen) {
                Runtime.activityTab = "clipboard";
                Runtime.notifyOpen = false;
                root.setPopout(true);
            } else if (!Runtime.notifyOpen) {
                root.setPopout(false);
            }
        }
    }

    popout: Component {
        ActivityPanel {
            availableWidth: root.Screen.width - Config.gap * 2
                - (root.popoutPadding + root.popoutBorderWidth) * 2
            availableHeight: Math.max(1, root.Screen.height - Theme.barHeight - Theme.panelPadding * 4)
            onTabRequested: name => root.selectTab(name)
        }
    }
}
