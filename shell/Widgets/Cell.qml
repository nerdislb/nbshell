import QtQuick
import qs.Common

// Ein Baustein der Leiste: ein Kasten mit Text, auf dem Zeichenraster.
//
// Alles in der Shell besteht daraus. Es gibt bewusst keine Fuellfarbe, keinen
// Schatten und keine Erhebung -- ein Kasten ist entweder umrandet ("box"),
// in eckigen Klammern ("bracket") oder blanker Text ("plain"). Welches davon,
// sagt `Config.widgetStyle` fuer alle gemeinsam.
Item {
    id: root

    property string text: ""

    // Ein Baustein blendet sich hierueber aus, nicht ueber `visible` -- siehe
    // die Erklaerung in Bar/WidgetHost.qml.
    property bool shown: true
    property color color: Theme.fg
    property bool interactive: false
    property bool active: false
    property alias hovered: mouse.containsMouse

    // Ersetzt den Text durch eigenen Inhalt, wenn eine Zelle mehr zeigen soll
    // als eine Zeichenkette (die Workspaces etwa).
    default property alias content: contentItem.data
    property bool custom: false

    signal clicked
    signal rightClicked
    signal wheel(int delta)

    readonly property string style: Config.widgetStyle
    readonly property bool boxed: style === "box"
    readonly property bool bracketed: style === "bracket"

    readonly property string shownText: bracketed ? ("[" + text + "]") : text

    implicitWidth: (custom ? contentItem.childrenRect.width : label.implicitWidth) + Theme.padX * 2
    implicitHeight: Theme.barHeight - Theme.padY

    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.active ? Theme.alpha(root.color, 0.15) : (mouse.containsMouse && root.interactive ? Theme.selection : "transparent")
        border.width: root.boxed ? Theme.borderWidth : 0
        border.color: root.active ? root.color : Theme.muted
    }

    Text {
        id: label
        visible: !root.custom
        anchors.centerIn: parent
        text: root.shownText
        color: root.color
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouseEvent => {
            if (mouseEvent.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
        onWheel: wheelEvent => root.wheel(wheelEvent.angleDelta.y)
    }
}
