import QtQuick
import Quickshell
import qs.Common
import "FocusScroll.js" as FocusScroll

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
    property bool closing: false
    property real lockedContentWidth: 0
    property real lockedContentHeight: 0
    readonly property var focusWindow: loader.item
        && ("initialFocusItem" in loader.item)
        && loader.item.initialFocusItem
        ? loader.item.initialFocusItem.Window.window : null

    // Der Griff ist der ganze Trick beim Schliessen: erst damit weiss der
    // Kompositor, dass hier ein Menue offen ist. Er beendet den Griff, sobald
    // man daneben klickt, und Quickshell blendet das Fenster dann selbst aus.
    // Ohne Griff bekaeme das Popout weder diesen Klick noch eine Taste mit --
    // es bliebe stehen, bis man dieselbe Zelle noch einmal trifft.
    //
    // Der Preis: solange es offen ist, hat das Fenster darunter keine
    // Tastatur. Fuer ein angeklicktes Menue ist das genau richtig.
    // Without the grab the popup receives no reliable pointer events.
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
    // a 1x1 window and resizing it one frame later makes Umbriel visibly
    // re-anchor the intermediate surface.
    visible: false
    // Muss schon VOR dem Mapping des PopupWindow wahr sein. Mit
    // `takesKeyboard && visible` wechselten Sichtbarkeit und Grab im selben
    // frame; creating the surface before its keyboard grab can leave the text
    // reichte danach trotz aktivem TextInput keine Tasten mehr hinein.
    // Unsichtbare PopupWindows beanspruchen keinen Sitz, daher ist die
    // zusaetzliche visible-Bedingung weder noetig noch hilfreich.
    grabFocus: takesKeyboard && requestedVisible && !closing

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

    // Reuse this native popup for preview -> interactive-menu transitions.
    // Creating a second xdg_popup either races the old popup's unmap or loses
    // the click serial while waiting for it. Updating an already mapped host
    // avoids both protocol boundaries; grabFocus is changed while still in the
    // original click handler.
    function show(component, keyboard, delayOverride) {
        leaveTimer.stop();
        contentComponent = component;
        takesKeyboard = keyboard;
        leaveDelayOverride = delayOverride;
        open();
    }

    function open() {
        const replacingContent = visible && loader.sourceComponent !== contentComponent;
        if (requestedVisible && visible && !replacingContent)
            return;
        requestedVisible = true;
        closing = false;
        const previous = Runtime.activePopout;
        // A Wayland popup must be created while the triggering input serial is
        // still valid. Waiting for the old popup's exit animation loses that
        // serial on Umbriel; mapping before it unmaps leaves Qt with a stale
        // topmost grab. Tear the old popup down synchronously, then map this
        // one before returning from the click handler.
        if (previous && previous !== root)
            previous.closeImmediately();
        if (replacingContent)
            surface.cancelTransition();
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
        if (!visible)
            surface.enter();
        visible = true;
        focusInitialItem();
    }

    function initialFocusTarget() {
        if (!takesKeyboard || !loader.item
                || !("initialFocusItem" in loader.item))
            return null;
        return loader.item.initialFocusItem;
    }

    function focusInitialItem() {
        if (!initialFocusTarget())
            return;
        focusRetry.attempts = 0;
        focusRetry.restart();
    }

    function recoverKeyboardFocusAfterPointerEntry() {
        if (!visible || !requestedVisible || closing || !takesKeyboard)
            return;
        const focused = focusWindow ? focusWindow.activeFocusItem : null;
        if (focusIsOnKeyboardControl(focused))
            return;
        // Coalesce pointer-enter and QQuickWindow activation into the next
        // event-loop turn. The handler rechecks focus before starting the
        // bounded retry, so a real control chosen by the user is never reset.
        pointerFocusRecovery.restart();
    }

    function enterKeyboardFocus(reason) {
        const target = initialFocusTarget();
        if (!target || !target.visible || !target.enabled)
            return false;
        target.forceActiveFocus(reason);
        if (target.activeFocus)
            ensureFocusVisible(target);
        return true;
    }

    function focusIsInsideContent(item) {
        for (let cursor = item; cursor; cursor = cursor.parent) {
            if (cursor === loader.item)
                return true;
        }
        return false;
    }

    function focusIsOnKeyboardControl(item) {
        return root.focusIsInsideContent(item)
            && item.visible && item.enabled && item.activeFocusOnTab
            && item.Accessible.focusable;
    }

    function ensureFocusVisible(item) {
        if (!item || !loader.item || !visible)
            return;
        const point = item.mapToItem(loader.item, 0, 0);
        const margin = Theme.spaceSm;
        const top = point.y;
        const bottom = top + item.height;
        if (bottom < 0 || top > loader.height)
            return;
        contentViewport.contentY = FocusScroll.contentYForFocus(
            top, item.height, contentViewport.contentY,
            contentViewport.height, contentViewport.contentHeight, margin);
    }

    function close() {
        requestedVisible = false;
        if (!visible) {
            finalizeClose();
            return;
        }
        if (closing)
            return;
        closing = true;
        surface.dismiss(root.finalizeClose);
    }

    function closeImmediately() {
        requestedVisible = false;
        closing = false;
        surface.cancelTransition();
        if (visible)
            visible = false;
        else
            finalizeClose();
    }

    function finalizeClose() {
        closing = false;
        if (visible) {
            visible = false;
            return;
        }
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
            closing = false;
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
            root.close()
    }

    Timer {
        id: focusRetry

        property int attempts: 0

        interval: 16
        repeat: true
        onTriggered: {
            if (!root.visible || !root.requestedVisible || root.closing
                    || !root.takesKeyboard || !loader.item
                    || !("initialFocusItem" in loader.item)) {
                stop();
                return;
            }
            const target = root.initialFocusTarget();
            if (!target || attempts >= 60) {
                stop();
                return;
            }
            if (target.activeFocus) {
                stop();
                return;
            }
            const focusWindow = target.Window.window;
            const focused = focusWindow ? focusWindow.activeFocusItem : null;
            // A passive loaded root (for example the audio panel's Column)
            // may temporarily become the window's activeFocusItem. That is
            // still a focus proxy, not a successful handoff to a control.
            // Stop only for a real tab target so a user's explicit focus is
            // preserved without accepting a dead container as success.
            if (root.focusIsOnKeyboardControl(focused)) {
                stop();
                return;
            }
            attempts++;
            root.enterKeyboardFocus(Qt.TabFocusReason);
            if (target.activeFocus)
                stop();
        }
    }

    Timer {
        id: pointerFocusRecovery

        interval: 0
        onTriggered: {
            if (!root.visible || !root.requestedVisible || root.closing
                    || !root.takesKeyboard)
                return;
            const focused = root.focusWindow ? root.focusWindow.activeFocusItem : null;
            if (!root.focusIsOnKeyboardControl(focused))
                root.focusInitialItem();
        }
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onInitialFocusItemChanged() { root.focusInitialItem(); }
    }

    Connections {
        target: root.focusWindow
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (root.focusWindow?.active)
                root.recoverKeyboardFocusAfterPointerEntry();
        }
        function onActiveFocusItemChanged() {
            Qt.callLater(() => root.ensureFocusVisible(root.focusWindow
                ? root.focusWindow.activeFocusItem : null));
        }
    }

    MotionSurface {
        id: surface
        anchors.fill: parent
        accentBorder: true
        autoEnter: false
        enterOffsetY: Config.edge === "bottom" ? Theme.spaceSm : -Theme.spaceSm
        transformOrigin: Config.edge === "bottom" ? Item.Bottom : Item.Top

        HoverHandler {
            id: hover
            onHoveredChanged: if (hovered)
                root.recoverKeyboardFocusAfterPointerEntry()
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
                // Loader is a Qt focus scope. Its loaded children cannot gain
                // active focus unless the scope itself participates in the
                // popup's focus chain.
                focus: root.takesKeyboard
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
        // Qt can leave active focus on an internal Flickable/Loader proxy when
        // the Wayland popup becomes active. In that state automatic traversal
        // has no tab-focusable starting item. Let the first Tab or Backtab enter
        // the content explicitly; subsequent traversal remains Qt-native.
        Keys.onTabPressed: event => {
            const focused = root.focusWindow ? root.focusWindow.activeFocusItem : null;
            if (!root.focusIsOnKeyboardControl(focused)) {
                root.enterKeyboardFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
        }
        Keys.onBacktabPressed: event => {
            const focused = root.focusWindow ? root.focusWindow.activeFocusItem : null;
            if (!root.focusIsOnKeyboardControl(focused)) {
                root.enterKeyboardFocus(Qt.BacktabFocusReason);
                event.accepted = true;
            }
        }
        focus: true
    }
}
