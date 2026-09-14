import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Ui as CompatUi

PanelWindow {
    id: root

    property bool modalPreviewOpen: false
    property Item modalPreviewTrigger: null

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:ui-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.uiGalleryOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.uiGalleryOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.priority: Keys.AfterItem
        Keys.onPressed: event => {
            const maximum = Math.max(0, viewport.contentHeight - viewport.height);
            const step = Theme.rowHeight * 2;
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                viewport.contentY = Math.min(maximum, viewport.contentY + step);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                viewport.contentY = Math.max(0, viewport.contentY - step);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                viewport.contentY = Math.min(maximum, viewport.contentY + viewport.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageUp) {
                viewport.contentY = Math.max(0, viewport.contentY - viewport.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                viewport.contentY = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                viewport.contentY = maximum;
                event.accepted = true;
            }
        }

        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 72
            preferredHeight: Theme.overlayHeightMedium
            MouseArea { anchors.fill: parent; onClicked: {} }

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                GalleryContent {
                    id: content
                    width: viewport.width
                    onModalRequested: trigger => {
                        root.modalPreviewTrigger = trigger;
                        root.modalPreviewOpen = true;
                    }
                }
            }
        }

        ModalSurface {
            visible: root.modalPreviewOpen
            z: 20
            blockedItem: box
            initialFocusItem: closeModalPreview
            restoreFocusItem: root.modalPreviewTrigger
            dialogTitle: "Modal preview"
            dialogDescription: "Shared focus, Escape, scrim, and background blocking contract"
            preferredWidth: Theme.overlayWidthMedium
            preferredHeight: modalPreviewContent.implicitHeight + Theme.panelPadding * 2
            onCloseRequested: root.modalPreviewOpen = false

            Column {
                id: modalPreviewContent
                width: parent.width - Theme.panelPadding * 2
                anchors.centerIn: parent
                spacing: Theme.spaceMd

                SectionHeader {
                    width: parent.width
                    text: "Modal surface"
                    detail: "focus trapped · background blocked"
                }
                Line {
                    width: parent.width
                    text: "Escape, the scrim, or the close action returns focus to the opener."
                    color: Theme.fgDim
                    wrapMode: Text.WordWrap
                }
                ActionButton {
                    id: closeModalPreview
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "CLOSE PREVIEW"
                    onTriggered: root.modalPreviewOpen = false
                }
            }
        }
    }
}
