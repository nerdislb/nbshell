import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import "FocusScroll.js" as FocusScroll

Column {
    id: root
    property real rowWidth: 64 * Theme.cellW
    property string selectedId: ""
    readonly property var selected: ForkUpdates.sources.find(r => r.id === root.selectedId) || null
    width: rowWidth
    spacing: Theme.spaceMd

    function state(row) {
        if (row.status === "error") return row.decision === "approved" ? qsTr("CHECK FAILED · APPROVED TARGET SAVED") : qsTr("CHECK FAILED");
        if (row.status === "unchecked") return qsTr("NOT CHECKED");
        if (row.status === "current") return qsTr("BASE CURRENT");
        if (row.decision === "approved") return qsTr("APPROVED · QUEUED");
        if (row.decision === "deferred") return qsTr("DEFERRED");
        return row.status === "diverged" ? qsTr("BASE NEEDS REVIEW") : qsTr("REVIEW AVAILABLE");
    }

    Line {
        width: parent.width
        text: qsTr("Review upstream changes before porting. Approval queues this exact revision; it does not install anything.")
        wrapMode: Text.Wrap
        color: Theme.fgDim
        font.pixelSize: Theme.fontCaption
    }
    Line {
        width: parent.width
        text: ForkUpdates.checking ? qsTr("Checking upstream sources …")
            : ForkUpdates.error !== "" ? ForkUpdates.error
            : ForkUpdates.checkedAt ? qsTr("Last check: %1").arg(new Date(ForkUpdates.checkedAt).toLocaleString()) + (ForkUpdates.errorCount ? qsTr(" · %1 checks failed").arg(ForkUpdates.errorCount) : "")
            : qsTr("No saved check. Use Refresh to check upstream sources.")
        color: ForkUpdates.error !== "" ? Theme.red : Theme.fgDim
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontCaption
    }
    ScrollView {
        id: scroll
        width: root.rowWidth
        height: Math.min(list.implicitHeight, Theme.rowHeight * (root.selected ? 4 : 8))
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Column {
            id: list
            width: scroll.availableWidth
            spacing: Theme.spaceXs
            Repeater {
                model: ForkUpdates.sources
                ControlButton {
                    required property var modelData
                    width: list.width
                    implicitHeight: Theme.rowHeight * 1.6
                    text: ""
                    selected: root.selectedId === modelData.id
                    accessibleName: modelData.name + ": " + root.state(modelData)
                    onTriggered: root.selectedId = modelData.id
                    onActiveFocusChanged: {
                        if (activeFocus && scroll.contentItem)
                            scroll.contentItem.contentY = FocusScroll.contentYForFocus(y, height,
                                scroll.contentItem.contentY, scroll.height, list.height, Theme.spaceXs);
                    }
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spaceXs
                        Line {
                            width: parent.width
                            text: modelData.name + (modelData.scope === "reference" ? qsTr(" · reference") : "")
                            elide: Text.ElideRight
                            color: parent.parent.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                        }
                        Line {
                            width: parent.width
                            text: root.state(modelData) + " · " + modelData.base.substring(0, 7) + " → " + (modelData.head ? modelData.head.substring(0, 7) : "?")
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontCaption
                            color: parent.parent.selected ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        }
                    }
                }
            }
            Line {
                width: parent.width
                visible: ForkUpdates.sources.length === 0
                text: qsTr("No fork sources loaded")
            }
        }
    }
    Column {
        width: parent.width
        visible: root.selected !== null
        spacing: Theme.spaceSm
        SectionHeader { width: parent.width; text: root.selected ? root.selected.name : ""; detail: qsTr("Upstream review") }
        ScrollView {
            id: detailScroll
            width: parent.width
            height: Math.min(detail.implicitHeight, Theme.rowHeight * 5)
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            Line {
                id: detail
                width: detailScroll.availableWidth
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Theme.fontCaption
                text: {
                    const r = root.selected;
                    if (!r) return "";
                    let result = qsTr("Reviewed upstream base: %1\nTarget: %2\n%3").arg(r.base).arg(r.head || "?").arg(root.state(r));
                    if (r.error) return result + "\n" + r.error + (r.stale ? "\n" + qsTr("Showing last successful target from %1; refresh before approving.").arg(r.lastSuccessAt) : "");
                    if (r.status === "current") return result + "\n" + qsTr("Upstream matches the catalog baseline. This is not an installed-build verification.");
                    result += "\n" + qsTr("Commit titles, not a compatibility assessment. Local ports may already contain these changes.");
                    if (r.changes && r.changes.length) result += "\n\n• " + r.changes.join("\n• ");
                    if (r.totalCommits > (r.changes || []).length) result += "\n" + qsTr("Showing %1 of %2 commits. Open changes for the full comparison.").arg(r.changes.length).arg(r.totalCommits);
                    return result;
                }
            }
        }
        Flow {
            width: parent.width
            spacing: Theme.spaceSm
            ActionButton {
                text: qsTr("Open changes")
                compact: true
                onTriggered: { if (root.selected) ForkUpdates.openChanges(root.selected); }
            }
            ActionButton {
                text: qsTr("Approve port")
                compact: true
                tone: "primary"
                visible: root.selected !== null && root.selected.scope !== "reference" && ["review", "diverged"].indexOf(root.selected.status) >= 0
                enabled: !ForkUpdates.busy && root.selected !== null && root.selected.decision !== "approved"
                onTriggered: ForkUpdates.decide(root.selected, "approved")
            }
            ActionButton {
                text: qsTr("Defer")
                compact: true
                visible: root.selected !== null && root.selected.scope !== "reference" && ["review", "diverged"].indexOf(root.selected.status) >= 0
                enabled: !ForkUpdates.busy && root.selected !== null && root.selected.decision !== "deferred"
                onTriggered: ForkUpdates.decide(root.selected, "deferred")
            }
            ActionButton {
                text: qsTr("Reset decision")
                compact: true
                visible: root.selected !== null && root.selected.scope !== "reference" && root.selected.token && root.selected.decision !== "pending"
                enabled: !ForkUpdates.busy
                onTriggered: ForkUpdates.decide(root.selected, "pending")
            }
        }
    }
}
