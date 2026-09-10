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
        readonly property real heightBudget: Math.max(0, Math.min(screen.height * 0.85,
            screen.height - barSpace) - Theme.spaceMd * 2)
        readonly property real toastWidth: Math.max(1, Math.min(Theme.cellW * 48,
            screen.width - margins.right - Theme.spaceMd * 2))
        property int shownCount: 0
        readonly property int overflowCount: Math.max(0, cards.count - shownCount)

        function reflow() {
            let total = 0;
            const heights = [];
            for (let i = 0; i < cards.count; i++) {
                const card = cards.itemAt(i);
                if (!card)
                    return;
                heights.push(card.implicitHeight);
                total += card.implicitHeight + (i > 0 ? stack.spacing : 0);
            }
            const budget = total <= heightBudget ? heightBudget
                : Math.max(0, heightBudget - more.implicitHeight - stack.spacing);
            let used = 0;
            let count = 0;
            for (const height of heights) {
                const next = used + height + (count > 0 ? stack.spacing : 0);
                if (next > budget)
                    break;
                used = next;
                count++;
            }
            shownCount = count;
        }
        onHeightBudgetChanged: Qt.callLater(reflow)

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
        implicitWidth: toastWidth + Theme.spaceMd * 2
        implicitHeight: stack.implicitHeight + Theme.spaceMd * 2

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
                id: cards
                model: Notify.popups
                onItemAdded: win.reflow()
                onItemRemoved: Qt.callLater(win.reflow)
                onCountChanged: Qt.callLater(win.reflow)

                NotificationToast {
                    required property var modelData
                    required property int index
                    width: win.toastWidth
                    visible: index < win.shownCount
                    onImplicitHeightChanged: Qt.callLater(win.reflow)
                    entry: modelData
                    onOpened: {
                        if (!Notify.open(modelData))
                            Notify.dismissPopup(modelData.key);
                    }
                    onRemoved: Notify.dismissPopup(modelData.key)
                }
            }

            ActionButton {
                id: more
                width: win.toastWidth
                visible: win.overflowCount > 0
                text: "+" + win.overflowCount + " more · Open history"
                onImplicitHeightChanged: Qt.callLater(win.reflow)
                onTriggered: Runtime.notificationCenterOpen = true
            }
        }
    }
}
