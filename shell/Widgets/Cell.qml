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

    // Der Name, unter dem dieser Baustein in der Config steht. Die Leiste
    // haengt ihn an -- gebraucht wird er, um ein Popout von aussen zu oeffnen
    // (`nbshell popout wetter`), ohne dass jeder Baustein ein eigenes
    // IPC-Ziel braucht.
    property string widgetId: ""

    // Ein Zeichen aus der Nerd-Font-Schrift vor dem Text. Leer heisst: nur
    // Text. Abschalten laesst sich das fuer alle gemeinsam mit `widgetIcons`.
    property string icon: ""
    property bool iconSpins: false

    // Das Kuerzel, das an die Stelle des Symbols tritt, wenn Symbole aus sind
    // ("VOL", "MSG", …). Ohne das bliebe von der Lautstaerke eine nackte Zahl
    // uebrig, die neben der Uhr nichts mehr bedeutet.
    property string label: ""

    // Mindestbreite in Zeichen. Ohne das wandert die halbe Leiste, sobald die
    // Lautstaerke von 9 % auf 100 % geht oder der Akku eine Stelle verliert --
    // die Zelle wird breiter, und alles rechts davon rutscht. Reserviert wird
    // deshalb Platz fuer den laengsten Fall. (Aus Omarchys Leiste uebernommen,
    // die dafuer feste "status slots" hat.)
    property int slotChars: 0

    // Ein Baustein, der gerade nichts zu sagen hat: keine Meldung, keine
    // Aufnahme, leere Ablage. Er verschwindet -- und taucht auf, sobald die
    // Maus die Leiste beruehrt. Fuenf Symbole, die immer "nichts" anzeigen,
    // sind das Lauteste an einer Textleiste.
    property bool quiet: false

    readonly property bool concealed: root.quiet && Config.quietWidgets && Runtime.barHover === 0 && !root.hovered

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

    // Verschwindet eine Zelle mit offenem Popout -- weil die Bausteinliste
    // sich geaendert hat oder die Shell neu laedt --, bliebe der Zaehler oben
    // stehen. Er haelt danach die Insel offen und die Tastatur bei der Leiste.
    Component.onDestruction: {
        if (root.popoutVisible)
            Runtime.popoutCount = Math.max(0, Runtime.popoutCount - 1);
        if (root.hovered && root.popout)
            Runtime.popoutHover = Math.max(0, Runtime.popoutHover - 1);
    }

    // Nur Zellen mit Popout melden sich: sonst zoege ein Klick auf die
    // Arbeitsflaechen dem Fenster darunter die Tastatur weg.
    onHoveredChanged: {
        if (root.popout)
            Runtime.popoutHover = Math.max(0, Runtime.popoutHover + (hovered ? 1 : -1));
    }

    readonly property string style: Config.widgetStyle
    readonly property bool boxed: style === "box"
    readonly property bool bracketed: style === "bracket"

    readonly property string labelled: (!Config.widgetIcons && root.label !== "") ? (root.label + (root.text !== "" ? " " + root.text : "")) : root.text

    readonly property string shownText: bracketed ? ("[" + labelled + "]") : labelled

    readonly property real contentWidth: Math.max(custom ? contentItem.childrenRect.width : line.implicitWidth, root.slotChars * Theme.cellW)

    implicitWidth: root.concealed ? 0 : contentWidth + Theme.padX * 2
    implicitHeight: Theme.barHeight - Theme.padY

    // Gedaempft, solange er nur zum Vorschein gekommen ist.
    opacity: root.quiet && !root.hovered ? 0.55 : 1

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 140
        }
    }

    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.active || popoutLoader.item?.visible ? Theme.alpha(root.color, 0.15) : (mouse.containsMouse && root.clickable ? Theme.hover : "transparent")
        border.width: root.boxed ? Theme.borderWidth : 0
        border.color: root.active || popoutLoader.item?.visible ? root.color : Theme.muted
    }

    IconText {
        id: line

        visible: !root.custom
        anchors.centerIn: parent
        icon: root.icon
        spins: root.iconSpins
        text: root.shownText
        color: root.color
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    Connections {
        target: Runtime

        function onCloseTokenChanged() {
            root.setPopout(false);
        }

        function onPopoutTokenChanged() {
            if (root.widgetId !== "" && Runtime.popoutTarget === root.widgetId)
                root.setPopout(!root.popoutVisible);
        }
    }

    // Popout von aussen schalten (Tastenkuerzel, IPC).
    function setPopout(open) {
        // Nur die Zelle, die gerade zu sehen ist: ein Baustein kann in der
        // zugeklappten Insel UND im Balken stehen (`clock` tut das), und dann
        // oeffnete ein Tastenkuerzel beide Popouts uebereinander. `enabled`
        // ist das richtige Merkmal -- die Leiste schaltet damit die Reihe ab,
        // die gerade ausgeblendet ist. `visible` taugt nicht: beide Reihen
        // werden ueberblendet, nicht geschaltet.
        if (open && !root.enabled)
            return;
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
