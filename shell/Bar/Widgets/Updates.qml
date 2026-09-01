import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One update signal for the whole desktop. It stays silent while everything is
// current and opens the same update surface used by the dashboard.
Cell {
    id: root

    readonly property bool checking: Updates.checking
        || ShellUpdates.checking || ShellUpdates.compositorChecking
    readonly property int availableKinds: (Updates.count > 0 ? 1 : 0)
        + (ShellUpdates.updateAvailable ? 1 : 0)
        + (ShellUpdates.compositorUpdateAvailable ? 1 : 0)

    shown: root.availableKinds > 0
    interactive: true
    popoutTakesKeyboard: true
    slotChars: 1

    label: "UPD"
    icon: Icons.download
    text: String(root.availableKinds)
    color: Updates.rebootRecommended ? Theme.red : Theme.yellow
    active: root.availableKinds > 0

    onClicked: {
        if (!Updates.ready)
            Updates.refresh();
        if (!ShellUpdates.ready || !ShellUpdates.compositorReady)
            ShellUpdates.refresh();
    }
    onRightClicked: {
        Updates.refresh();
        ShellUpdates.refresh();
    }

    preview: Component {
        BarPreview {
            icon: Icons.download
            title: qsTr("Updates available")
            subtitle: qsTr("System, nbshell and Umbriel")
            badge: String(root.availableKinds)
            badgeColor: Updates.rebootRecommended ? Theme.red : Theme.yellow
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": qsTr("System"), "value": Updates.count > 0 ? String(Updates.count) : qsTr("current"), "color": Updates.count > 0 ? Theme.yellow : Theme.fg },
                        { "label": qsTr("nbshell"), "value": ShellUpdates.updateAvailable ? ShellUpdates.latest : qsTr("current"), "color": ShellUpdates.updateAvailable ? Theme.yellow : Theme.fg },
                        { "label": qsTr("Umbriel"), "value": ShellUpdates.compositorUpdateAvailable ? qsTr("available") : qsTr("current"), "color": ShellUpdates.compositorUpdateAvailable ? Theme.yellow : Theme.fg }
                    ]
                }
            ]
        }
    }

    popout: Component {
        UpdatePanel {}
    }
}
