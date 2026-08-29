import QtQuick

// Canonical interaction and accessibility contract for custom nbshell controls.
// Visual primitives inherit this surface and add their own state styling.
Rectangle {
    id: root

    property bool interactive: true
    property bool keyboardFocusable: interactive
    property bool activationBlocked: false
    property string accessibleName: ""
    property string accessibleDescription: ""
    property int accessibleRole: Accessible.Button
    property bool accessibleSelected: false
    property bool accessiblePressed: false

    signal triggered()

    function activate() {
        if (root.interactive && root.enabled && !root.activationBlocked)
            root.triggered();
    }

    function activateFromKey(event) {
        if (!event.isAutoRepeat)
            root.activate();
        event.accepted = true;
    }

    activeFocusOnTab: keyboardFocusable && interactive && enabled

    Accessible.role: accessibleRole
    Accessible.name: accessibleName
    Accessible.description: accessibleDescription
    Accessible.focusable: activeFocusOnTab
    Accessible.focused: activeFocus
    Accessible.selected: accessibleSelected
    Accessible.pressed: accessiblePressed
    Accessible.onPressAction: root.activate()

    Keys.onReturnPressed: event => root.activateFromKey(event)
    Keys.onEnterPressed: event => root.activateFromKey(event)
    Keys.onSpacePressed: event => root.activateFromKey(event)
}
