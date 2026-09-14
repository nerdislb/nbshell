import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Ui
import qs.Widgets as W

Item {
    id: root

    property real rowWidth: 64 * Theme.cellW
    property string tab: "updates"
    property bool showClose: false
    property var closePanel: null
    property var closePopout: null
    property Item initialFocusItem: refreshButton

    readonly property bool checking: Updates.checking
        || ShellUpdates.checking || ShellUpdates.compositorChecking || ForkUpdates.checking
    readonly property int availableKinds: (Updates.count > 0 ? 1 : 0)
        + (ShellUpdates.updateAvailable ? 1 : 0)
        + (ShellUpdates.compositorUpdateAvailable ? 1 : 0)
        + (ForkUpdates.attentionCount > 0 ? 1 : 0)
    readonly property var packageRows: root.updatePackages()

    width: rowWidth
    implicitWidth: rowWidth
    // Popouts lock their Wayland geometry on open. Reserve review space so
    // switching tabs does not leave Fork in the smaller package viewport.
    implicitHeight: Math.max(Theme.rowHeight * 18, panelContent.implicitHeight)


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

    function updatePackages() {
        const rows = [];
        function append(packages, source) {
            for (let i = 0; i < packages.length; ++i) {
                const item = packages[i];
                rows.push({
                    "name": item.name,
                    "from": item.from,
                    "to": item.to,
                    "source": source
                });
            }
        }
        append(Updates.repo, qsTr("REPOSITORY"));
        append(Updates.aur, qsTr("AUR"));
        append(Updates.flatpak, qsTr("FLATPAK"));
        return rows;
    }

    function packageVersion(item) {
        return item.from === item.to
            ? qsTr("New build %1").arg(item.to)
            : qsTr("%1 → %2").arg(item.from).arg(item.to);
    }

    function compositorRevision(project, field) {
        const projects = ShellUpdates.compositorProjects || ({});
        const row = projects[project];
        return row && row[field] !== undefined ? row[field] : "unknown";
    }

    function compositorDetail() {
        if (ShellUpdates.compositorChecking)
            return qsTr("Checking official repositories …");
        if (ShellUpdates.compositorError !== "")
            return ShellUpdates.compositorError;
        if (ShellUpdates.compositorBlockedReason !== "")
            return ShellUpdates.compositorBlockedReason;
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
        if (Updates.error !== "")
            return qsTr("ERROR");
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
        if (ShellUpdates.compositorError !== "")
            return qsTr("ERROR");
        if (ShellUpdates.compositorBlockedReason !== "")
            return qsTr("PAUSED");
        if (!ShellUpdates.compositorReady)
            return qsTr("PENDING");
        if (!ShellUpdates.compositorInstalled)
            return qsTr("NOT INSTALLED");
        if (ShellUpdates.compositorUpdateAvailable && !ShellUpdates.compositorInstallable)
            return qsTr("BLOCKED");
        return ShellUpdates.compositorUpdateAvailable ? "" : qsTr("CURRENT");
    }

    Column {
        id: panelContent
        width: root.rowWidth
        spacing: Theme.spaceMd

    Item {
        id: updateHeader
        width: root.rowWidth
        height: Theme.cellH * 2.7

        PanelHead {
            anchors.left: parent.left
            rowWidth: root.rowWidth - headerActions.width - Theme.spaceLg
            icon: root.checking ? Icons.refresh : Icons.download
            title: qsTr("Updates")
            subtitle: root.tab === "fork" ? qsTr("%1 need review · %2 approved").arg(ForkUpdates.attentionCount).arg(ForkUpdates.approvedCount) : ShellUpdates.summary
            badge: root.checking ? "…" : String(root.availableKinds)
            badgeColor: ForkUpdates.errorCount > 0 || ForkUpdates.error !== "" ? Theme.red : (ForkUpdates.attentionCount > 0 || !ShellUpdates.allCurrent) ? Theme.yellow : Theme.green
        }

        Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceMd

            ActionButton {
                id: refreshButton
                text: root.tab === "fork" ? qsTr("Refresh") : qsTr("Check again")
                busy: root.tab === "fork" ? ForkUpdates.busy : root.checking
                compact: true
                onTriggered: root.tab === "fork" ? ForkUpdates.refresh() : root.refreshAll()
            }

            ActionButton {
                visible: root.showClose
                text: qsTr("Close")
                compact: true
                onTriggered: root.requestClose()
            }
        }
    }

    PanelSeparator { id: updateSeparator; width: root.rowWidth }

    W.Segments {
        id: updateTabs
        rowWidth: root.rowWidth
        options: [{label: qsTr("Updates"), value: "updates"}, {label: qsTr("Fork"), value: "fork"}]
        current: root.tab
        onChosen: value => { root.tab = value; if (value === "fork") ForkUpdates.load(); }
    }

    W.ForkUpdatePanel {
        id: forkContent
        rowWidth: root.rowWidth
        visible: root.tab === "fork"
    }

    Column {
        id: systemContent
        width: root.rowWidth
        spacing: Theme.spaceMd
        visible: root.tab === "updates"

    PanelRow {
        id: systemRow
        width: root.rowWidth
        height: Theme.rowHeight * 1.15
        glyph: Icons.download
        title: qsTr("System packages")
        detail: Updates.checking ? qsTr("Checking repositories, AUR and Flatpak …")
            : (Updates.error !== "" ? Updates.error : !Updates.ready ? qsTr("Not checked yet")
            : (Updates.count > 0
                ? qsTr("%1 repositories · %2 AUR · %3 Flatpak").arg(Updates.repo.length).arg(Updates.aur.length).arg(Updates.flatpak.length)
                : qsTr("Repositories, AUR and Flatpak are current")))
        value: root.systemState()
        tone: Updates.count > 0 ? Theme.yellow : Theme.green
        selected: Updates.count > 0
    }

    PanelSurface {
        id: packageReview

        width: root.rowWidth
        height: Math.min(
            Theme.controlHeight + root.packageRows.length * Theme.rowHeight + Theme.spaceMd * 2,
            Theme.rowHeight * 6.5)
        visible: Updates.ready && Updates.count > 0
        raised: true

        Accessible.role: Accessible.List
        Accessible.name: qsTr("%1 package updates").arg(Updates.count)

        ScrollView {
            id: packageScroll

            anchors.fill: parent
            anchors.margins: Theme.spaceMd
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: packageList

                width: packageScroll.availableWidth
                spacing: Theme.spaceXs

                SectionHeader {
                    width: parent.width
                    text: qsTr("Packages")
                    detail: qsTr("%1 ready").arg(Updates.count)
                }

                Repeater {
                    model: root.packageRows

                    PanelRow {
                        required property var modelData

                        width: packageList.width
                        title: modelData.name
                        detail: root.packageVersion(modelData)
                        value: modelData.source
                    }
                }
            }
        }
    }

    Row {
        width: root.rowWidth
        height: systemAction.implicitHeight
        spacing: Theme.spaceMd
        visible: packageReview.visible

        Line {
            width: parent.width - systemAction.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("A terminal shows the password prompt and update progress")
            color: Theme.fgDim
            elide: Text.ElideRight
        }

        ActionButton {
            id: systemAction
            text: qsTr("Install updates")
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
        value: shellAction.visible ? "" : root.shellState()
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
        value: umbrielAction.visible ? "" : root.compositorState()
        tone: ShellUpdates.compositorUpdateAvailable || ShellUpdates.compositorError !== ""
            || ShellUpdates.compositorBlockedReason !== "" ? Theme.yellow : Theme.green
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

    Line {
        width: root.rowWidth
        visible: !ShellUpdates.compositorChecking && ShellUpdates.compositorBlockedReason !== ""
        text: ShellUpdates.compositorBlockedReason
        wrapMode: Text.Wrap
        color: Theme.fg
        font.pixelSize: Theme.fontCaption
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
    }
}
