import QtQuick

Item {
    id: root

    property bool checked: false
    property bool busy: false
    property color foreground: "white"
    property color accent: "#7aa2f7"
    signal toggled()

    implicitWidth: 42
    implicitHeight: 24
    opacity: busy ? 0.55 : 1

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        border.width: 1
        border.color: root.checked ? root.accent
                                   : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 4
            x: root.checked ? parent.width - width - 4 : 4
            color: root.checked ? root.accent : root.foreground

            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
