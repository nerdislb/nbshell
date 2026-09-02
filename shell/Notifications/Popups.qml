import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// Die Karten, die bei einer neuen Benachrichtigung aufgehen.
//
// Native nbshell toast stack: compact, grid-aligned, passive and focus-safe.
// Low and normal messages use their urgency-aware timeout (and respect a
// longer sender timeout); critical messages remain until explicitly closed.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        // Keep the explicit bottom override for existing users. The native
        // default stays at the top-right, clear of the shell bar.
        readonly property bool atTop: {
            const wish = Config.value("notifyCorner", "auto");
            if (wish === "bottom")
                return false;
            return true;
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
        // Requesting focus while mapping a notification layer can steal the
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
        // no reliable input region here, so hover and action clicks would fail
        // auf den Aktionsknoepfen. Stattdessen nimmt das ganze Fenster
        // Eingaben an und wird per `margins.*` unter die Leiste und vom Rand
        // weg geschoben, damit es nur dort blockiert, wo wirklich eine Karte
        // liegt.
        // Breite = Karte + auf JEDER Seite so viel Rand, wie der Stapel selbst
        // nimmt (Theme.cellH). Vorher stand hier cellW*2, was schmaler war als
        // der rechte Stapelrand -- die linke Kartenkante rutschte dadurch knapp
        // aus dem Fenster und der linke Rahmen wurde abgeschnitten.
        implicitWidth: stack.implicitWidth + Theme.spaceMd * 2
        implicitHeight: Math.min(screen.height * 0.85, stack.implicitHeight + Theme.spaceMd * 2)

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
            anchors.margins: Theme.spaceMd

            spacing: Theme.spaceSm

            Repeater {
                model: Notify.popups

                NotificationToast {
                    required property var modelData
                    width: Math.max(1, Math.min(implicitWidth,
                        win.screen.width - Theme.overlayMarginX * 2))
                    entry: modelData
                    onOpened: {
                        if (!Notify.open(modelData))
                            Notify.dismissPopup(modelData.key);
                    }
                    onRemoved: Notify.dismissPopup(modelData.key)
                }
            }
        }
    }
}
