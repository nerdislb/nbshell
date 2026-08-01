import QtQuick
import Quickshell
import qs.Common

// Ein Fenster, das an einer Zelle haengt.
//
// Ein echtes Wayland-Popup (`PopupWindow`), kein weiteres Layer-Fenster: der
// Kompositor kennt die Beziehung zur Leiste, haelt es an der richtigen Stelle,
// wenn sich die Leiste bewegt, und beendet den Griff selbst, sobald man
// daneben klickt. Ein nachgebautes Overlay muesste all das von Hand tun --
// samt einer bildschirmgrossen, unsichtbaren Klickflaeche.
//
// `anchor.item` ist die Zelle, `gravity` schiebt es je nach Bildschirmrand
// nach unten oder oben weg.
PopupWindow {
    id: root

    property Item anchorItem: null
    property Component contentComponent: null

    // Nur wo getippt wird (Passwort im Control Center): ein Griff auf die
    // Tastatur nimmt sie dem Fenster darunter weg.
    property bool takesKeyboard: false

    // Innenabstand in Zellen, damit auch das Popout auf dem Raster sitzt.
    readonly property real padding: Theme.cellW * 2

    color: "transparent"
    visible: false
    grabFocus: takesKeyboard && visible

    implicitWidth: loader.item ? loader.item.implicitWidth + padding * 2 + Theme.borderWidth * 2 : 1
    implicitHeight: loader.item ? loader.item.implicitHeight + padding * 2 + Theme.borderWidth * 2 : 1

    anchor.item: root.anchorItem
    anchor.rect.y: Config.edge === "bottom" ? -Config.gap : (root.anchorItem?.height ?? 0) + Config.gap
    anchor.gravity: Config.edge === "bottom" ? Edges.Top : Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX

    function toggle() {
        visible = !visible;
    }

    function close() {
        visible = false;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.muted

        Loader {
            id: loader

            anchors.fill: parent
            anchors.margins: root.padding
            sourceComponent: root.visible ? root.contentComponent : null

            // Der Inhalt darf sich selbst schliessen, ohne die Kette nach oben
            // zu kennen.
            onLoaded: if (item && "closePopout" in item)
                item.closePopout = root.close
        }

        // Escape schliesst -- erwartet man bei allem, was sich aufklappt.
        Keys.onEscapePressed: root.close()
        focus: true
    }
}
