import QtQuick
import qs.Common

// Ein Baustein der Leiste: ein Kasten mit Text, auf dem Zeichenraster.
//
// Alles in der Shell besteht daraus. Es gibt bewusst keine Fuellfarbe, keinen
// Schatten und keine Erhebung -- a widget is either outlined ("box") or
// plain text ("plain"). Old "bracket" values are rendered as plain text so
// legacy configs cannot bring the retired action-bracket language back.
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
    property color color: Theme.barFg
    property bool interactive: false

    // Klappt beim Klick auf. Der Inhalt bekommt `closePopout` gesetzt.
    property Component popout: null

    // Popouts gehen sonst erst auf Klick auf. Fuer Bausteine, die nur etwas
    // ZEIGEN und nichts zu bedienen haben, ist das eine Bedienung zu viel.
    property bool popoutOnHover: false

    readonly property bool nimmtKlicks: root.interactive || (root.popout !== null && !root.popoutOnHover)
    property bool popoutTakesKeyboard: false
    property bool active: false
    property int pendingPopoutToken: -1
    property alias hovered: mouse.containsMouse

    // Ersetzt den Text durch eigenen Inhalt, wenn eine Zelle mehr zeigen soll
    // als eine Zeichenkette (die Workspaces etwa).
    default property alias content: contentItem.data
    property bool custom: false

    signal clicked
    signal rightClicked
    signal wheel(int delta)

    readonly property bool clickable: interactive || popout !== null

    // Nimmt die Zelle SELBST Klicks an?
    //
    // Nicht, wenn ihr Popout schon beim Ueberfahren aufgeht: dann hat ihr
    // Inhalt eigene Knoepfe (die Wiedergabetasten), und die Mausflaeche der
    // Zelle liegt darueber -- sie schluckte jeden Druck darauf.
    //
    // `enabled: false` waere die falsche Loesung: damit fiele auch das
    // Ueberfahren weg, und das Popout ginge nie wieder auf. `Qt.NoButton`
    // laesst die Druecker durch und behaelt das Hovern.

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
        // Beim Ueberfahren aufgehen, wenn der Baustein das will. Nur oeffnen,
        // nicht schliessen: das Popout hat dafuer seinen eigenen Nachlauf und
        // weiss auch, ob der Zeiger inzwischen IN ihm steht -- ein Schliessen
        // von hier wuerde es genau in dem Moment wegnehmen, in dem man
        // hineinfaehrt.
        if (root.popoutOnHover && root.hovered)
            root.setPopout(true);
    }

    // ── Aussehen je Baustein ─────────────────────────────────────────────
    //
    // Form, Symbol und Farbe gelten fuer alle gemeinsam -- ausser fuer die
    // Bausteine, die in `widgets` einen eigenen Eintrag haben:
    //
    //   "widgets": {
    //       "sys":   { "display": "icon", "color": "green" },
    //       "clock": { "style": "plain" }
    //   }
    //
    // Nachgebaut nach Shibumi-Shell, wo dieselben drei Regler je Baustein
    // stehen (DISPLAY / SURFACE / COLOR). Was nicht dort steht -- oder auf
    // "auto" --, kommt weiter aus der allgemeinen Einstellung: wer nichts
    // eintraegt, merkt von der ganzen Sache nichts, und die Config bleibt
    // kurz.
    //
    // Nachschlagen kann die Zelle das selbst, weil sie ihre `widgetId` schon
    // kennt -- die Leiste haengt sie ohnehin an.
    readonly property var overrides: {
        const all = Config.value("widgets", ({}));
        if (root.widgetId === "" || !all)
            return ({});
        return all[root.widgetId] ?? ({});
    }

    function pick(key, fallback) {
        const v = root.overrides[key];
        return (v === undefined || v === null || v === "" || v === "auto") ? fallback : v;
    }

    readonly property string style: pick("style", Config.widgetStyle)
    readonly property bool boxed: style === "box"

    // full = Symbol und Text, icon = nur Symbol, text = nur Text (mit Kuerzel).
    readonly property string display: pick("display", Config.widgetIcons ? "full" : "text")

    readonly property bool wantIcon: (root.display === "full" || root.display === "icon") && root.icon !== ""

    // "icon" bei einem Baustein ohne Symbol waere eine leere Zelle -- dann
    // gilt weiter der Text.
    readonly property bool wantText: root.display !== "icon" || root.icon === ""

    readonly property string labelled: {
        if (!root.wantText)
            return "";
        return (!root.wantIcon && root.label !== "") ? (root.label + (root.text !== "" ? " " + root.text : "")) : root.text;
    }

    readonly property string shownText: labelled

    // Die Farbe wird nur ersetzt, wenn der Baustein die NEUTRALE benutzt. Ein
    // roter Akku und eine rote Prozessorlast sind Warnungen, keine Gestaltung
    // -- sie einzufaerben hiesse, die einzige Aussage zu loeschen, die die
    // Zelle in dem Moment hat. Die gedaempfte Fassung bleibt gedaempft.
    readonly property color shownColor: {
        const role = root.pick("color", "");
        if (role === "")
            return root.color;
        const dim = Qt.colorEqual(root.color, Theme.textDim);
        if (!dim && !Qt.colorEqual(root.color, Theme.text))
            return root.color;
        const tinted = Theme.roleColor(role);
        return dim ? Theme.readable(Theme.mix(tinted, Theme.barSurface, 0.45), Theme.barSurface, 3.0) : Theme.readable(tinted, Theme.barSurface, 4.5);
    }

    readonly property real contentWidth: Math.max(custom ? contentItem.childrenRect.width : line.implicitWidth, root.slotChars * Theme.cellW)

    implicitWidth: root.concealed ? 0 : contentWidth + Theme.barItemPadding * 2
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
        color: root.active || popoutLoader.item?.visible ? Theme.mix(Theme.barSurface, root.shownColor, 0.15) : (mouse.containsMouse && root.clickable ? Theme.barHover : "transparent")
        border.width: root.boxed ? Theme.borderWidth : 0
        border.color: root.active || popoutLoader.item?.visible ? root.shownColor : Theme.muted
    }

    IconText {
        id: line

        visible: !root.custom
        anchors.centerIn: parent
        icon: root.icon
        icons: root.wantIcon
        spins: root.iconSpins
        text: root.shownText
        color: root.shownColor
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
            if (root.widgetId !== "" && Runtime.popoutTarget === root.widgetId) {
                if (!root.enabled) {
                    // An IPC request can reveal a collapsed island and target
                    // a widget in the same frame. Its expanded row is not
                    // enabled until the handoff animation reaches it, so keep
                    // the request instead of silently dropping it.
                    root.pendingPopoutToken = Runtime.popoutToken;
                } else {
                    root.pendingPopoutToken = -1;
                    root.setPopout(!root.popoutVisible);
                }
            }
        }
    }

    onEnabledChanged: {
        if (enabled && pendingPopoutToken === Runtime.popoutToken) {
            pendingPopoutToken = -1;
            root.setPopout(true);
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
        acceptedButtons: root.nimmtKlicks ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
        cursorShape: root.nimmtKlicks ? Qt.PointingHandCursor : Qt.ArrowCursor
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
