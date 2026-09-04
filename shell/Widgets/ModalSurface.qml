import QtQuick
import QtQuick.Window
import qs.Common

// Full modal contract for shell-local dialogs: background input is disabled,
// pointer events cannot leak through, keyboard focus stays inside the dialog,
// and closing restores the control that opened it.
FocusScope {
    id: root

    property Item blockedItem: null
    property Item initialFocusItem: null
    property Item restoreFocusItem: null
    property string dialogTitle: ""
    property string dialogDescription: ""
    property bool closeOnScrim: true
    property real scrimRadius: 0

    property alias preferredWidth: surface.preferredWidth
    property alias preferredHeight: surface.preferredHeight
    property alias edgeMarginX: surface.edgeMarginX
    property alias edgeMarginY: surface.edgeMarginY
    property alias dockedTop: surface.dockedTop
    property alias dockOffset: surface.dockOffset
    readonly property alias panel: surface
    default property alias contentData: contentHost.data

    signal closeRequested()

    property Item previousFocusItem: null

    function containsFocusItem(item) {
        let current = item;
        while (current) {
            if (current === root)
                return true;
            current = current.parent;
        }
        return false;
    }

    function focusInitial(reason) {
        const target = root.initialFocusItem;
        if (target && target.visible && target.enabled) {
            target.forceActiveFocus(reason ?? Qt.TabFocusReason);
            return;
        }
        root.forceActiveFocus(reason ?? Qt.OtherFocusReason);
    }

    function moveFocus(forward) {
        const focusWindow = root.Window.window;
        const focused = focusWindow ? focusWindow.activeFocusItem : null;
        let next = focused ? focused.nextItemInFocusChain(forward) : null;
        let attempts = 0;
        while (next && next !== focused && attempts < 128) {
            if (next !== root && root.containsFocusItem(next)
                    && next.visible && next.enabled && next.activeFocusOnTab) {
                next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                return;
            }
            next = next.nextItemInFocusChain(forward);
            attempts++;
        }
        root.focusInitial(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }

    function enterModal() {
        const focusWindow = root.Window.window;
        const focused = focusWindow ? focusWindow.activeFocusItem : null;
        previousFocusItem = restoreFocusItem
            || (!root.containsFocusItem(focused) ? focused : null);
        root.forceActiveFocus(Qt.OtherFocusReason);
        Qt.callLater(() => root.focusInitial(Qt.TabFocusReason));
    }

    anchors.fill: parent
    Accessible.role: Accessible.Dialog
    Accessible.name: dialogTitle
    Accessible.description: dialogDescription
    Accessible.focusable: true
    Accessible.focused: activeFocus

    onVisibleChanged: {
        if (visible)
            root.enterModal();
        else {
            const target = restoreFocusItem || previousFocusItem;
            if (target && target.visible && target.enabled)
                Qt.callLater(() => target.forceActiveFocus(Qt.OtherFocusReason));
            previousFocusItem = null;
        }
    }
    Component.onCompleted: if (visible && !activeFocus) root.enterModal()

    Binding {
        target: root.blockedItem
        property: "enabled"
        value: false
        when: root.visible && root.blockedItem !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    Shortcut {
        enabled: root.visible
        sequence: "Tab"
        context: Qt.WindowShortcut
        onActivated: root.moveFocus(true)
    }
    Shortcut {
        enabled: root.visible
        sequence: "Shift+Tab"
        context: Qt.WindowShortcut
        onActivated: root.moveFocus(false)
    }

    Keys.priority: Keys.AfterItem
    Keys.onEscapePressed: event => {
        root.closeRequested();
        event.accepted = true;
    }
    Keys.onTabPressed: event => {
        event.accepted = true;
        root.moveFocus(true);
    }
    Keys.onBacktabPressed: event => {
        event.accepted = true;
        root.moveFocus(false);
    }
    Keys.onPressed: event => {
        // Unhandled shortcuts must not bubble into the disabled background.
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        radius: root.scrimRadius
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => {
            if (root.closeOnScrim && mouse.button === Qt.LeftButton)
                root.closeRequested();
            mouse.accepted = true;
        }
        onWheel: wheel => wheel.accepted = true
    }

    OverlaySurface {
        id: surface

        Accessible.ignored: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: mouse => mouse.accepted = true
            onWheel: wheel => wheel.accepted = true
        }

        Item {
            id: contentHost
            anchors.fill: parent
        }
    }
}
