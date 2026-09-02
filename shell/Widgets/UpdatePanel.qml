import QtQuick
import qs.Common
import qs.Services
import qs.Ui

Column {
    id: root

    property real rowWidth: 64 * Theme.cellW
    property bool showClose: false
    property var closePanel: null
    property var closePopout: null
    property Item initialFocusItem: refreshButton

    readonly property bool checking: Updates.checking
        || ShellUpdates.checking || ShellUpdates.compositorChecking
    readonly property int availableKinds: (Updates.count > 0 ? 1 : 0)
        + (ShellUpdates.updateAvailable ? 1 : 0)
        + (ShellUpdates.compositorUpdateAvailable ? 1 : 0)

    width: rowWidth
    spacing: Theme.spaceMd

    function closeAfter(action) {
        action();
        root.requestClose();
    }

    function requestClose() {
        if (root.closePanel)
            root.closePanel();
        else if (root.closePopout)
            root.closePopout();
    }

    function refreshAll() {
        Updates.refresh();
        ShellUpdates.refresh();
    }

    function compositorRevision(project, field) {
        const projects = ShellUpdates.compositorProjects || ({});
        const row = projects[project];
        return row && row[field] !== undefined ? row[field] : "unknown";
    }

    function compositorDetail() {
        if (ShellUpdates.compositorChecking)
            return qsTr("Checking official repositories …");
        if (ShellUpdates.compositorBlockedReason !== "")
            return ShellUpdates.compositorBlockedReason;
        if (ShellUpdates.compositorError !== "")
            return ShellUpdates.compositorError;
        if (!ShellUpdates.compositorReady)
            return qsTr("Umbriel and portal have not been checked yet");
        if (!ShellUpdates.compositorInstalled)
            return qsTr("Umbriel stack is not installed");
        const umbriel = root.compositorProjectDetail("umbriel", qsTr("Umbriel"));
        const portal = root.compositorProjectDetail("xdg-desktop-portal-umbriel", qsTr("Portal"));
        return ShellUpdates.compositorUpdateAvailable
            ? umbriel + " · " + portal + " · " + qsTr("active after next login")
            : umbriel + " · " + portal;
    }

    function compositorProjectDetail(project, label) {
        const current = root.compositorRevision(project, "current");
        return root.compositorRevision(project, "available") === true
            ? qsTr("%1 %2 → %3").arg(label).arg(current).arg(root.compositorRevision(project, "latest"))
            : qsTr("%1 %2").arg(label).arg(current);
    }

    function systemState() {
        if (Updates.checking)
            return qsTr("CHECKING");
        if (!Updates.ready)
            return qsTr("PENDING");
        return Updates.count > 0 ? "" : qsTr("CURRENT");
    }

    function shellState() {
        if (ShellUpdates.checking)
            return qsTr("CHECKING");
        if (ShellUpdates.error !== "")
            return qsTr("ERROR");
        if (!ShellUpdates.ready)
            return qsTr("PENDING");
        return ShellUpdates.updateAvailable ? "" : qsTr("CURRENT");
    }

    function compositorState() {
        if (ShellUpdates.compositorChecking)
            return qsTr("CHECKING");
        if (!ShellUpdates.compositorReady)
            return qsTr("PENDING");
        if (!ShellUpdates.compositorInstalled)
            return qsTr("NOT INSTALLED");
        if (ShellUpdates.compositorUpdateAvailable && !ShellUpdates.compositorInstallable)
            return qsTr("BLOCKED");
        if (ShellUpdates.compositorError !== "")
            return qsTr("ERROR");
        return ShellUpdates.compositorUpdateAvailable ? "" : qsTr("CURRENT");
    }

    Item {
        width: root.rowWidth
        height: Theme.cellH * 2.7

        PanelHead {
            anchors.left: parent.left
            rowWidth: root.rowWidth - headerActions.width - Theme.spaceLg
            icon: root.checking ? Icons.refresh : Icons.download
            title: qsTr("Updates")
            subtitle: root.checking ? qsTr("Checking all sources")
                : (root.availableKinds > 0 ? qsTr("Ready to install") : qsTr("Everything is current"))
            badge: root.checking ? "…" : String(root.availableKinds)
            badgeColor: root.availableKinds > 0 ? Theme.yellow : Theme.green
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceMd

            ActionButton {
                id: refreshButton
                text: qsTr("Check again")
                busy: root.checking
                compact: true
                onTriggered: root.refreshAll()
            }

            ActionButton {
                visible: root.showClose
                text: qsTr("Close")
                compact: true
                onTriggered: root.requestClose()
            }
        }
    }

    PanelSeparator { width: root.rowWidth }

    PanelRow {
        id: systemRow
        width: root.rowWidth
        height: Theme.rowHeight * 1.15
        glyph: Icons.download
        title: qsTr("System packages")
        detail: Updates.checking ? qsTr("Checking repositories, AUR and Flatpak …")
            : (!Updates.ready ? qsTr("Not checked yet")
            : (Updates.count > 0
                ? qsTr("%1 repositories · %2 AUR · %3 Flatpak").arg(Updates.repo.length).arg(Updates.aur.length).arg(Updates.flatpak.length)
                : qsTr("Repositories, AUR and Flatpak are current")))
        value: root.systemState()
        tone: Updates.count > 0 ? Theme.yellow : Theme.green
        selected: Updates.count > 0
        trailingInset: systemAction.visible ? systemAction.width + Theme.spaceLg : 0

        ActionButton {
            id: systemAction
            anchors.right: parent.right
            anchors.rightMargin: Theme.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            visible: Updates.count > 0
            text: qsTr("Update")
            tone: "primary"
            accentColor: Theme.green
            compact: true
            onTriggered: root.closeAfter(() => Updates.update())
        }
    }

    PanelRow {
        id: shellRow
        width: root.rowWidth
        height: Theme.rowHeight * 1.15
        glyph: Icons.refresh
        title: qsTr("nbshell")
        detail: ShellUpdates.checking ? qsTr("Checking published %1 releases …").arg(ShellUpdates.channel)
            : (ShellUpdates.error !== "" ? ShellUpdates.error
            : (!ShellUpdates.ready ? qsTr("Not checked yet")
            : (ShellUpdates.updateAvailable
                ? qsTr("%1 → %2 · checksum verified").arg(ShellUpdates.current || "unknown").arg(ShellUpdates.latest)
                : qsTr("Version %1 is current").arg(ShellUpdates.current || "unknown"))))
        value: root.shellState()
        tone: ShellUpdates.updateAvailable || ShellUpdates.error !== "" ? Theme.yellow : Theme.green
        selected: ShellUpdates.updateAvailable
        trailingInset: shellAction.visible ? shellAction.width + Theme.spaceLg : 0

        ActionButton {
            id: shellAction
            anchors.right: parent.right
            anchors.rightMargin: Theme.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            visible: ShellUpdates.updateAvailable
            enabled: ShellUpdates.installable
            text: ShellUpdates.installable ? qsTr("Update") : qsTr("Blocked")
            tone: "primary"
            accentColor: Theme.green
            compact: true
            onTriggered: root.closeAfter(() => ShellUpdates.install())
        }
    }

    PanelRow {
        id: umbrielRow
        width: root.rowWidth
        height: Theme.rowHeight * 1.15
        glyph: Icons.refresh
        title: qsTr("Umbriel stack")
        detail: root.compositorDetail()
        value: root.compositorState()
        tone: ShellUpdates.compositorUpdateAvailable || ShellUpdates.compositorError !== "" ? Theme.yellow : Theme.green
        selected: ShellUpdates.compositorUpdateAvailable
        trailingInset: umbrielAction.visible ? umbrielAction.width + Theme.spaceLg : 0

        ActionButton {
            id: umbrielAction
            anchors.right: parent.right
            anchors.rightMargin: Theme.spaceMd
            anchors.verticalCenter: parent.verticalCenter
            visible: ShellUpdates.compositorUpdateAvailable
            enabled: ShellUpdates.compositorInstallable
            text: ShellUpdates.compositorInstallable ? qsTr("Update") : qsTr("Blocked")
            tone: "primary"
            accentColor: Theme.green
            compact: true
            onTriggered: root.closeAfter(() => ShellUpdates.installCompositor())
        }
    }

    Row {
        width: root.rowWidth
        spacing: Theme.spaceMd

        ActionButton {
            visible: ShellUpdates.releaseUrl !== ""
            text: qsTr("nbshell release notes")
            compact: true
            onTriggered: ShellUpdates.openNotes()
        }

        Line {
            width: root.rowWidth - (parent.children[0].visible ? parent.children[0].width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Updates run visibly in a terminal")
            horizontalAlignment: Text.AlignRight
            color: Theme.muted
            elide: Text.ElideRight
        }
    }
}
