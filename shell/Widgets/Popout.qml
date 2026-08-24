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
    property bool requestedVisible: false
    property real lockedContentWidth: 0
    property real lockedContentHeight: 0

    // Der Griff ist der ganze Trick beim Schliessen: erst damit weiss der
    // Kompositor, dass hier ein Menue offen ist. Er beendet den Griff, sobald
    // man daneben klickt, und Quickshell blendet das Fenster dann selbst aus.
    // Ohne Griff bekaeme das Popout weder diesen Klick noch eine Taste mit --
    // es bliebe stehen, bis man dieselbe Zelle noch einmal trifft.
    //
    // Der Preis: solange es offen ist, hat das Fenster darunter keine
    // Tastatur. Fuer ein angeklicktes Menue ist das genau richtig.
    // WIEDER an: ohne Griff bekommt das Popup unter niri gar keine
    // Zeigerereignisse -- die Liste klappt auf, aber man kann nichts
    // anfassen. Das Schliessen macht es trotzdem selbst (siehe unten): der
    // Griff wird zwar erteilt, aber beim Klick daneben nicht beendet.
    property bool takesKeyboard: true
    property int leaveDelayOverride: -1

    // Zeit, bis ein Popout von selbst zugeht, nachdem die Maus es und seine
    // Zelle verlassen hat. Der Kompositor meldet uns keinen Klick daneben --
    // ohne diesen Nachlauf bliebe es stehen, bis man dieselbe Zelle noch
    // einmal trifft.
    readonly property int leaveDelay: leaveDelayOverride >= 0
        ? leaveDelayOverride : Config.value("popoutLeaveDelay", 2500)

    readonly property bool pointerInside: hover.hovered || (root.anchorItem?.hovered ?? false)

    // Innenabstand in Zellen, damit auch das Popout auf dem Raster sitzt.
    readonly property real padding: Theme.panelPadding

    color: "transparent"
    // Load and lay out the content before mapping the Wayland popup. Mapping
    // a 1x1 window and resizing it one frame later is mostly hidden by Niri,
    // but Umbriel visibly re-anchors that intermediate surface.
    visible: false
    // Muss schon VOR dem Mapping des PopupWindow wahr sein. Mit
    // `takesKeyboard && visible` wechselten Sichtbarkeit und Grab im selben
    // Frame; niri sah das Fenster beim Erzeugen noch ohne Keyboard-Grab und
    // reichte danach trotz aktivem TextInput keine Tasten mehr hinein.
    // Unsichtbare PopupWindows beanspruchen keinen Sitz, daher ist die
    // zusaetzliche visible-Bedingung weder noetig noch hilfreich.
    grabFocus: takesKeyboard

    implicitWidth: lockedContentWidth > 0 ? lockedContentWidth + padding * 2 + Theme.borderWidth * 2 : 1
    implicitHeight: lockedContentHeight > 0 ? lockedContentHeight + padding * 2 + Theme.borderWidth * 2 : 1

    anchor.item: root.anchorItem
    anchor.rect.y: Config.edge === "bottom" ? -Config.gap : (root.anchorItem?.height ?? 0) + Config.gap
    anchor.gravity: Config.edge === "bottom" ? Edges.Top : Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX

    function toggle() {
        if (requestedVisible)
            close();
        else
            open();
    }

    function open() {
        requestedVisible = true;
        // Loader creation is synchronous by default. Assigning the component
        // before mapping gives the popup its final initial geometry while we
        // are still in the input/IPC activation cycle required by Wayland.
        loader.sourceComponent = contentComponent;
        mapWhenReady();
    }

    function mapWhenReady() {
        if (!requestedVisible || loader.status !== Loader.Ready || !loader.item)
            return;
        // Freeze only the outer Wayland geometry. Live service data may still
        // grow the content; the viewport below makes that overflow scrollable
        // instead of asking the compositor to resize and re-anchor the popup.
        lockedContentWidth = Math.max(1, loader.item.implicitWidth);
        lockedContentHeight = Math.max(1, loader.item.implicitHeight);
        visible = true;
    }

    function close() {
        requestedVisible = false;
        visible = false;
        loader.sourceComponent = null;
        lockedContentWidth = 0;
        lockedContentHeight = 0;
    }

    onPointerInsideChanged: {
        if (pointerInside)
            leaveTimer.stop();
        else if (visible)
            leaveTimer.restart();
    }

    onVisibleChanged: {
        if (visible) {
            // Nur EIN Popout gleichzeitig: ein schon offenes zuerst schliessen,
            // sonst ueberlappen sie sich.
            const prev = Runtime.activePopout;
            if (prev && prev !== root)
                prev.close();
            Runtime.activePopout = root;
            if (!pointerInside)
                leaveTimer.restart();
        } else {
            leaveTimer.stop();
            if (Runtime.activePopout === root)
                Runtime.activePopout = null;
            // A compositor may dismiss a popup grab itself. Mirror that
            // external close into our request state so the visibility binding
            // cannot map the same popup again on the next evaluation.
            if (requestedVisible && loader.status === Loader.Ready)
                requestedVisible = false;
            loader.sourceComponent = null;
            lockedContentWidth = 0;
            lockedContentHeight = 0;
        }
    }

    Timer {
        id: leaveTimer
        interval: root.leaveDelay
        onTriggered: if (!root.pointerInside)
            root.visible = false
    }

    PanelSurface {
        anchors.fill: parent
        accentBorder: true

        HoverHandler {
            id: hover
        }
        Flickable {
            id: contentViewport

            anchors.fill: parent
            anchors.margins: root.padding
            contentWidth: loader.width
            contentHeight: loader.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Loader {
                id: loader

                width: item ? Math.max(contentViewport.width, item.implicitWidth) : 1
                height: item ? item.implicitHeight : 1
                sourceComponent: null

                onStatusChanged: root.mapWhenReady()

                // Der Inhalt darf sich selbst schliessen, ohne die Kette nach oben
                // zu kennen.
                onLoaded: if (item && "closePopout" in item)
                    item.closePopout = root.close
            }

            Rectangle {
                anchors.right: parent.right
                y: contentViewport.visibleArea.yPosition * contentViewport.height
                width: Math.max(2, Theme.borderWidth * 2)
                height: Math.max(Theme.cellH, contentViewport.visibleArea.heightRatio * contentViewport.height)
                radius: width / 2
                color: Theme.alpha(Theme.accent, 0.7)
                visible: contentViewport.contentHeight > contentViewport.height
            }
        }

        // Escape schliesst -- erwartet man bei allem, was sich aufklappt.
        Keys.onEscapePressed: root.close()
        focus: true
    }
}
