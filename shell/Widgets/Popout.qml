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

    // Der Griff ist der ganze Trick beim Schliessen: erst damit weiss der
    // Kompositor, dass hier ein Menue offen ist. Er beendet den Griff, sobald
    // man daneben klickt, und Quickshell blendet das Fenster dann selbst aus.
    // Ohne Griff bekaeme das Popout weder diesen Klick noch eine Taste mit --
    // es bliebe stehen, bis man dieselbe Zelle noch einmal trifft.
    //
    // Der Preis: solange es offen ist, hat das Fenster darunter keine
    // Tastatur. Fuer ein angeklicktes Menue ist das genau richtig.
    property bool takesKeyboard: false

    // Zeit, bis ein Popout von selbst zugeht, nachdem die Maus es und seine
    // Zelle verlassen hat. Der Kompositor meldet uns keinen Klick daneben --
    // ohne diesen Nachlauf bliebe es stehen, bis man dieselbe Zelle noch
    // einmal trifft.
    readonly property int leaveDelay: Config.value("popoutLeaveDelay", 2500)

    readonly property bool pointerInside: hover.hovered || (root.anchorItem?.hovered ?? false)

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

    onPointerInsideChanged: {
        if (pointerInside)
            leaveTimer.stop();
        else if (visible)
            leaveTimer.restart();
    }

    onVisibleChanged: {
        if (!visible)
            leaveTimer.stop();
        else if (!pointerInside)
            leaveTimer.restart();
    }

    Timer {
        id: leaveTimer
        interval: root.leaveDelay
        onTriggered: if (!root.pointerInside)
            root.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        HoverHandler {
            id: hover
        }
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
