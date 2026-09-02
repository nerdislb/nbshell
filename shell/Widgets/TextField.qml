import QtQuick
import QtQuick.Controls as Controls
import qs.Common

// Native single-line editor. Because this derives from the Controls TextField,
// callers retain the complete text API (validator, echoMode, accepted,
// editingFinished, selection, and key handlers) without adapter properties.
Controls.TextField {
    id: root

    property color foreground: Theme.fg
    property bool password: false
    property string accessibleName: ""
    property string accessibleDescription: ""
    property bool hasCursor: false
    property bool visualFocus: activeFocus
    property real horizontalPadding: Theme.spaceMd

    readonly property bool visualHover: hovered || hasCursor
    readonly property color visualFill: Theme.textFieldFill(visualHover, visualFocus, readOnly)
    readonly property color visualBorder: Theme.textFieldBorder(visualHover, visualFocus, readOnly)

    implicitHeight: Theme.controlHeight
    leftPadding: horizontalPadding
    rightPadding: horizontalPadding
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    selectByMouse: true
    echoMode: password ? TextInput.Password : TextInput.Normal
    color: foreground
    selectionColor: Theme.textFieldSelection
    selectedTextColor: Theme.textFieldSelectedText
    placeholderTextColor: Theme.fgDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBody
    opacity: enabled ? 1 : Theme.controlDisabledOpacity

    Accessible.role: Accessible.EditableText
    Accessible.name: accessibleName.length > 0 ? accessibleName : placeholderText
    Accessible.description: accessibleDescription
    Accessible.focusable: activeFocusOnTab && enabled
    Accessible.focused: activeFocus
    Accessible.passwordEdit: password || echoMode !== TextInput.Normal
    Accessible.readOnly: readOnly

    background: Rectangle {
        color: root.visualFill
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: root.visualBorder

        Behavior on color {
            ColorAnimation { duration: Theme.motionEffectsFast }
        }
        Behavior on border.color {
            ColorAnimation { duration: Theme.motionEffectsFast }
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: Theme.motionEffectsFast }
    }
}
