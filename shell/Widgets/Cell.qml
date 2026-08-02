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

    // Klappt beim Klick auf. Der Inhalt bekommt `closePopout` gesetzt.
    property Component popout: null
    property bool popoutTakesKeyboard: false
    property bool active: false
    property alias hovered: mouse.containsMouse

    // Ersetzt den Text durch eigenen Inhalt, wenn eine Zelle mehr zeigen soll
    // als eine Zeichenkette (die Workspaces etwa).
    default property alias content: contentItem.data
    property bool custom: false

    signal clicked
    signal rightClicked
    signal wheel(int delta)

    readonly property bool clickable: interactive || popout !== null

    // Damit ein Baustein mitbekommt, wenn der Kompositor das Popout von sich
    // aus geschlossen hat -- sonst denkt ein Tastenkuerzel, es sei noch offen,
    // und der naechste Druck taete scheinbar nichts.
    readonly property bool popoutVisible: popoutLoader.item ? popoutLoader.item.visible : false

    onPopoutVisibleChanged: Runtime.popoutCount = Math.max(0, Runtime.popoutCount + (popoutVisible ? 1 : -1))

    // Nur Zellen mit Popout melden sich: sonst zoege ein Klick auf die
    // Arbeitsflaechen dem Fenster darunter die Tastatur weg.
    onHoveredChanged: {
        if (root.popout)
            Runtime.popoutHover = Math.max(0, Runtime.popoutHover + (hovered ? 1 : -1));
    }

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
        color: root.active || popoutLoader.item?.visible ? Theme.alpha(root.color, 0.15) : (mouse.containsMouse && root.clickable ? Theme.selection : "transparent")
        border.width: root.boxed ? Theme.borderWidth : 0
        border.color: root.active || popoutLoader.item?.visible ? root.color : Theme.muted
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

    // Popout von aussen schalten (Tastenkuerzel, IPC).
    function setPopout(open) {
        if (popoutLoader.item)
            popoutLoader.item.visible = open;
    }

    // Erst wenn ein Baustein wirklich eines hat, entsteht das Popupfenster.
    Loader {
        id: popoutLoader
        active: root.popout !== null
        sourceComponent: popoutComponent
    }

    Component {
        id: popoutComponent

        Popout {
            anchorItem: root
            contentComponent: root.popout
            takesKeyboard: root.popoutTakesKeyboard
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouseEvent => {
            if (mouseEvent.button === Qt.RightButton) {
                root.rightClicked();
                return;
            }
            if (popoutLoader.item)
                popoutLoader.item.toggle();
            root.clicked();
        }
        onWheel: wheelEvent => root.wheel(wheelEvent.angleDelta.y)
    }
}
