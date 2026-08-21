import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// Die Karten, die bei einer neuen Benachrichtigung aufgehen.
//
// Sie stehen gegenueber der Leiste am rechten Rand, gestapelt, neueste oben.
// Jede laeuft nach `notifyTimeout` von selbst ab; dringende bleiben stehen,
// bis man sie wegklickt -- so, wie es die Spezifikation vorsieht.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        // Vorgabe: gegenueber der Leiste. Wer es anders will, setzt
        // `notifyCorner` auf "top" oder "bottom".
        readonly property bool atTop: {
            const wish = Config.value("notifyCorner", "auto");
            if (wish === "top")
                return true;
            if (wish === "bottom")
                return false;
            return Config.edge !== "top";
        }

        // Steht die Leiste auf derselben Seite, muss der Stapel UNTER ihr
        // anfangen. Von allein tut er das nicht: das Fenster liegt auf der
        // Overlay-Ebene und ignoriert die reservierte Zone
        // (`ExclusionMode.Ignore`) -- was richtig ist, sonst schoebe jede
        // Karte die Fenster darunter beiseite. Es muss sich den Platz also
        // selbst nehmen.
        //
        // In der Insel und in der Pille kommt der Abstand zum Rand dazu; im
        // Balken sitzt die Leiste direkt an der Kante.
        readonly property bool sameSideAsBar: atTop === (Config.edge === "top")
        readonly property real barSpace: sameSideAsBar ? Theme.barHeight + (Config.mode === "bar" ? 0 : Config.gap) : 0

        screen: modelData
        visible: Notify.popups.length > 0
        color: "transparent"

        WlrLayershell.namespace: "nbshell:notifications"
        WlrLayershell.layer: WlrLayershell.Overlay
        // Toasts duerfen niemals Tastaturfokus anfordern. Mit OnDemand nahm
        // Niri 26.04 beim Mappen des neuen Layer-Fensters Herdr bereits den
        // aktiven Sitz weg, obwohl niemand die Karte angeklickt hatte. Pointer-
        // Eingaben (Hover, Aktionen, Rechtsklick) brauchen keinen Keyboard-
        // Fokus; nur die bewusst geoeffnete NotificationCenter-Oberflaeche
        // verwendet weiterhin Exclusive.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors.right: true
        anchors.top: atTop
        anchors.bottom: !atTop

        // Fenster genau so gross wie der Kartenstapel -- KEINE Maske: eine
        // Region-Maske (egal ob `item:` oder explizite Koordinaten) liefert
        // unter niri keinen Eingabebereich, also kein Hover und keine Klicks
        // auf den Aktionsknoepfen. Stattdessen nimmt das ganze Fenster
        // Eingaben an und wird per `margins.*` unter die Leiste und vom Rand
        // weg geschoben, damit es nur dort blockiert, wo wirklich eine Karte
        // liegt.
        // Breite = Karte + auf JEDER Seite so viel Rand, wie der Stapel selbst
        // nimmt (Theme.cellH). Vorher stand hier cellW*2, was schmaler war als
        // der rechte Stapelrand -- die linke Kartenkante rutschte dadurch knapp
        // aus dem Fenster und der linke Rahmen wurde abgeschnitten.
        implicitWidth: stack.implicitWidth + Theme.cellH * 2
        implicitHeight: Math.min(screen.height * 0.85, stack.implicitHeight + Theme.cellH * 2)

        margins.top: win.atTop ? win.barSpace : 0
        margins.bottom: win.atTop ? 0 : win.barSpace
        margins.right: Theme.cellW

        Column {
            id: stack

            // Der Abstand zur Leiste sitzt jetzt am Fenster (margins.*), nicht
            // mehr hier -- die Karten fuellen das (schon bar-freie) Fenster mit
            // gleichmaessigem Rand.
            anchors.right: parent.right
            anchors.top: win.atTop ? parent.top : undefined
            anchors.bottom: win.atTop ? undefined : parent.bottom
            anchors.margins: Theme.cellH

            spacing: Theme.cellH * 0.5

            Repeater {
                model: Notify.popups

                PanelSurface {
                    id: card

                    required property var modelData

                    // Angezeigt wird der Eintrag, nicht die Benachrichtigung:
                    // was aus dem Archiv auf der Platte kommt, hat kein
                    // lebendes Objekt mehr. Nur die Aktionsknoepfe brauchen es
                    // -- die gibt es dann eben nicht.
                    readonly property var n: modelData.notification
                    readonly property bool urgent: modelData.urgency === NotificationUrgency.Critical

                    width: Theme.cellW * 48
                    height: body.implicitHeight + Theme.cellH

                    accentBorder: true
                    border.color: card.urgent ? Theme.red : Theme.focusBorder

                    // Dringendes bleibt stehen, bis es jemand wegklickt.
                    Timer {
                        interval: Notify.popupTimeout
                        running: !card.urgent && !hover.hovered
                        onTriggered: Notify.dismissPopup(card.modelData.key)
                    }

                    HoverHandler {
                        id: hover
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.cellW
                        spacing: Theme.cellH * 0.2

                        Line {
                            width: parent.width
                            text: (card.urgent ? "! " : "") + (card.modelData.appName || "System") + "  ·  " + Notify.ago(card.modelData.time)
                            color: card.urgent ? Theme.red : Theme.fgDim
                            elide: Text.ElideRight
                        }

                        Line {
                            width: parent.width
                            visible: text !== ""
                            text: card.modelData.summary ?? ""
                            color: Theme.fgBright
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Line {
                            width: parent.width
                            visible: text !== ""
                            // Der Text darf Auszeichnung enthalten; als
                            // RichText gelesen bleibt <b> ein Fettdruck statt
                            // sichtbarer Klammern.
                            text: card.modelData.body ?? ""
                            textFormat: Text.RichText
                            color: Theme.fg
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: Theme.cellW
                            visible: (card.n?.actions?.length ?? 0) > 0

                            Repeater {
                                model: card.n?.actions ?? []

                                ActionButton {
                                    id: actionButton

                                    required property var modelData

                                    text: actionButton.modelData.text
                                    compact: true
                                    onTriggered: Notify.invoke(card.modelData.key, actionButton.modelData)
                                }
                            }
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Rechtsklick entfernt nur die sichtbare Karte. Im
                        // Verlauf bleibt die Meldung zum spaeteren Nachlesen.
                        // Die inneren Aktionsknoepfe gewinnen ihren eigenen
                        // Pointer-Grab und funktionieren weiterhin separat.
                        onTapped: Notify.dismissPopup(card.modelData.key)
                    }
                }
            }
        }
    }
}
