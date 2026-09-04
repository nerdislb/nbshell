import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Die Leiste -- je nach Betriebsart eine freistehende Insel oder ein
// durchgehender Balken. Ein Fenster je Bildschirm.
//
// Beide Arten sind dasselbe Fenster: es ist immer bildschirmbreit und
// durchsichtig, und nur der Rahmen darin waechst. Ein Layer-Surface bei jedem
// Animationsschritt neu zu vermessen waere unruhig; eine Maske haelt die
// durchsichtige Flaeche derweil klickdurchlaessig.
//
// Der Unterschied zwischen Insel und Balken ist damit fast nur Geometrie:
//
//   Insel   Rahmen so breit wie sein Inhalt, schwebt (exclusiveZone -1),
//           faehrt beim Ueberfahren auf und zeigt dann alle drei Gruppen.
//   Pille   dieselbe Insel, die aber nie zuklappt -- sie schwebt weiter, ist
//           aber immer vollstaendig. Geometrisch ist sie die aufgeklappte
//           Insel, es faellt nur der zugeklappte Zustand weg.
//   Balken  Rahmen ueber die volle Breite, schiebt die Fenster weg
//           (exclusiveZone), Gruppen links/mitte/rechts.
//
// Die drei Gruppen gibt es in beiden Faellen nur EINMAL. Statt sie je nach
// Betriebsart neu zu bauen, sitzen sie in einer Reihe, deren zwei Zwischen-
// raeume ihre Breite wechseln: im Balken so, dass die Mitte wirklich mittig
// steht, in der Insel auf einen Zeichenabstand.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        readonly property bool barMode: Config.mode === "bar"

        // Die Pille ist die Insel, die nie zuklappt: gleiche Geometrie, gleicher
        // Schwebezustand, nur ohne das Zusammenschrumpfen auf die Uhr.
        readonly property bool pillMode: Config.mode === "pill"

        readonly property bool atBottom: Config.edge === "bottom"
        readonly property bool expanded: barMode || pillMode || Runtime.islandOpen || hovering
        property real openProgress: expanded ? 1 : 0
        readonly property real centerHandoff: Math.max(0, Math.min(1, (openProgress - 0.72) / 0.28))
        property string expandedClockGroup: "center"
        property var collapsedWidgetNames: []
        property var expandedLeftWidgetNames: []
        property var expandedCenterWidgetNames: []
        property var expandedRightWidgetNames: []
        readonly property bool reuseCollapsedCenter: !barMode && !pillMode
            && JSON.stringify(collapsedWidgetNames) === JSON.stringify(expandedCenterWidgetNames)
        readonly property var expandedWidgetNames: expandedLeftWidgetNames
            .concat(expandedCenterWidgetNames).concat(expandedRightWidgetNames)
        property bool hovering: false
        property real edgeDragY: 0
        readonly property string wallpaperSource: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")

        // The update signal is a desktop status, not a module users need to
        // position manually. Keep exactly one instance immediately after the
        // clock in both compact and expanded center groups. Legacy configs
        // that placed `updates` elsewhere are normalized at render time only;
        // their stored module lists remain untouched.
        function withUpdateIndicator(widgets, insert) {
            const result = [];
            let inserted = false;
            for (const widget of (widgets || [])) {
                if (widget === "updates")
                    continue;
                result.push(widget);
                if (insert && !inserted && widget === "clock") {
                    result.push("updates");
                    inserted = true;
                }
            }
            if (insert && !inserted)
                result.push("updates");
            return result;
        }

        function sameWidgetModel(current, next) {
            return JSON.stringify(current) === JSON.stringify(next);
        }

        // Config.set replaces the complete JSON object. Keeping these Repeater
        // models bound directly to Config therefore rebuilt every bar widget
        // when the right-tail toggle persisted one boolean. Preserve model
        // identity unless the configured names actually changed.
        function syncWidgetModels() {
            const clockGroup = Config.leftWidgets.indexOf("clock") >= 0 ? "left"
                : (Config.centerWidgets.indexOf("clock") >= 0 ? "center"
                : (Config.rightWidgets.indexOf("clock") >= 0 ? "right" : "center"));
            const nextCollapsed = withUpdateIndicator(Config.collapsedWidgets, true);
            const nextLeft = withUpdateIndicator(Config.leftWidgets, clockGroup === "left");
            const nextCenter = withUpdateIndicator(Config.centerWidgets, clockGroup === "center");
            const nextRight = withUpdateIndicator(Config.rightWidgets, clockGroup === "right");

            expandedClockGroup = clockGroup;
            if (!sameWidgetModel(collapsedWidgetNames, nextCollapsed))
                collapsedWidgetNames = nextCollapsed;
            if (!sameWidgetModel(expandedLeftWidgetNames, nextLeft))
                expandedLeftWidgetNames = nextLeft;
            if (!sameWidgetModel(expandedCenterWidgetNames, nextCenter))
                expandedCenterWidgetNames = nextCenter;
            if (!sameWidgetModel(expandedRightWidgetNames, nextRight))
                expandedRightWidgetNames = nextRight;
        }

        function refreshTransparentContrast() {
            if (!Config.barTransparent || !Config.wallpaperEnabled || !wallpaperSource) {
                Theme.transparentBarSurface = Theme.bg;
                return;
            }
            contrastTimer.restart();
        }

        onWallpaperSourceChanged: refreshTransparentContrast()
        onWidthChanged: refreshTransparentContrast()
        onHeightChanged: refreshTransparentContrast()
        Component.onCompleted: {
            syncWidgetModels();
            refreshTransparentContrast();
        }

        Behavior on openProgress {
            NumberAnimation {
                duration: Theme.motionBar
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.motionCurveEffect
            }
        }

        Connections {
            target: Config
            function onBarTransparentChanged() { win.refreshTransparentContrast(); }
            function onWallpaperEnabledChanged() { win.refreshTransparentContrast(); }
            function onEdgeChanged() { win.refreshTransparentContrast(); }
            function onCollapsedWidgetsChanged() { win.syncWidgetModels(); }
            function onLeftWidgetsChanged() { win.syncWidgetModels(); }
            function onCenterWidgetsChanged() { win.syncWidgetModels(); }
            function onRightWidgetsChanged() { win.syncWidgetModels(); }
        }

        Timer {
            id: contrastTimer
            interval: 120
            onTriggered: {
                if (contrastProc.running)
                    return;
                contrastProc.command = [
                    Qt.resolvedUrl("../scripts/bar-wallpaper-sample.sh").toString().replace("file://", ""),
                    Config.edge,
                    String(Theme.barHeight),
                    String(Math.round(win.modelData?.width ?? win.width)) + "x" + String(Math.round(win.modelData?.height ?? win.height)),
                    win.wallpaperSource
                ];
                contrastProc.running = true;
            }
        }

        Process {
            id: contrastProc
            stdout: StdioCollector {
                onStreamFinished: {
                    const sample = text.trim();
                    if (/^#[0-9A-Fa-f]{6}$/.test(sample))
                        Theme.transparentBarSurface = sample;
                }
            }
        }

        // Die Pille wird beim Regeln fuer zwei Sekunden selbst zur Einblendung.
        // Sie hat dafuer schon alles: zwei Reihen, die einander ueberblenden,
        // und einen Rahmen, dessen Breite mitlaeuft -- es kommt nur eine dritte
        // Reihe dazu. Solange sie steht, tritt der normale Inhalt zurueck.
        readonly property bool osdInPill: pillMode && Config.osdInPill && Osd.showing

        screen: modelData
        color: "transparent"

        WlrLayershell.namespace: "nbshell:bar"
        WlrLayershell.layer: WlrLayershell.Top

        // Nur solange ein Popout offen ist: sonst zoege ein Klick auf die
        // Leiste dem Fenster darunter staendig die Tastatur weg.
        WlrLayershell.keyboardFocus: (Runtime.popoutCount > 0 || Runtime.popoutHover > 0) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.left: true
        anchors.right: true
        anchors.top: !atBottom
        anchors.bottom: atBottom

        implicitHeight: Theme.barHeight + (barMode ? 0 : Config.gap)

        // Reserve the visible shell height in every mode. Island and pill keep
        // their floating shape, but regular windows no longer sit underneath.
        exclusiveZone: Theme.barHeight + (barMode ? 0 : Config.gap)

        mask: Region {
            item: frame
        }

        // Sobald ein Popout offen ist, darf die Leiste Tastatur annehmen
        // (siehe oben) -- dann kommt hier auch Esc an.
        Item {
            anchors.fill: parent
            focus: Runtime.popoutCount > 0
            Keys.onEscapePressed: Runtime.closeAll()
        }

        // Zuklappen nach dem Verlassen -- aber NICHT, solange ein Popout offen
        // ist oder die Maus darauf steht.
        //
        // Ein Popout ist ein eigenes Fenster: wer aus der Leiste hinunter in
        // die Liste faehrt, hat die Leiste damit verlassen, und die Insel klappt
        // ihm unter der Hand weg -- mitten im Auswaehlen. Der Nachlauf allein
        // hilft dagegen nicht, er verschiebt es nur.
        readonly property bool popoutBusy: Runtime.popoutCount > 0 || Runtime.popoutHover > 0

        onPopoutBusyChanged: {
            if (popoutBusy) {
                collapseTimer.stop();
                win.hovering = true;
            } else if (!barMode && !pillMode) {
                // Zurueck ist der Weg durch die Leiste -- deshalb nicht sofort.
                Runtime.clearTransientIsland();
                collapseTimer.restart();
            }
        }

        Timer {
            id: collapseTimer
            interval: Config.collapseDelay
            onTriggered: if (!win.popoutBusy)
                win.hovering = false
        }

        Rectangle {
            id: frame

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: win.atBottom ? undefined : parent.top
            anchors.bottom: win.atBottom ? parent.bottom : undefined
            anchors.topMargin: win.atBottom ? 0 : (win.barMode ? 0 : Config.gap)
            anchors.bottomMargin: win.atBottom ? (win.barMode ? 0 : Config.gap) : 0

            height: Theme.barHeight
            width: {
                if (win.barMode)
                    return win.width;
                if (win.osdInPill)
                    return Math.min(win.width, osdRow.implicitWidth + Theme.padX * 2);
                const closedWidth = Math.min(win.width, collapsed.implicitWidth + Theme.padX * 2);
                const compactOpenWidth = Math.min(win.width, content.compactWidth + Theme.padX * 2);
                const openWidth = Config.islandExpandFullWidth && !win.pillMode ? win.width : compactOpenWidth;
                return closedWidth + (openWidth - closedWidth) * win.openProgress;
            }

            radius: win.barMode ? 0 : Theme.radius
            color: Theme.alpha(Theme.bg, Config.barOpacity)
            border.width: Config.barBorder ? Theme.borderWidth : 0
            border.color: Theme.muted

            Behavior on color {
                ColorAnimation { duration: Theme.motionEffectsDefault }
            }

            // Doppelklick auf die Leiste: Hintergrund transparent bzw. wieder
            // auf die konfigurierte Deckkraft stellen. NoModifier laesst den
            // bestehenden Shift+Drag zum Verschieben der Kante unberuehrt.
            TapHandler {
                acceptedButtons: Qt.LeftButton
                acceptedModifiers: Qt.NoModifier
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onDoubleTapped: Config.toggleBarTransparency()
            }

            // Shift+Linksklick ziehen verschiebt die Leiste an die andere
            // Bildschirmkante. Der Modifier verhindert, dass normale Klicks
            // auf Widgets oder Regler vom Flaechen-Drag verschluckt werden.
            DragHandler {
                id: edgeDrag
                target: null
                acceptedButtons: Qt.LeftButton
                acceptedModifiers: Qt.ShiftModifier
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: {
                    if (active) {
                        win.edgeDragY = 0;
                    } else if (Math.abs(win.edgeDragY) >= Theme.cellH * 3) {
                        Config.set("edge", win.edgeDragY > 0 ? "bottom" : "top");
                    }
                }
                onTranslationChanged: win.edgeDragY = translation.y
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        collapseTimer.stop();
                        win.hovering = true;
                    } else {
                        collapseTimer.restart();
                    }
                    // Stille Bausteine tauchen auf, solange die Maus irgendwo
                    // auf der Leiste steht -- gezaehlt, weil es je Bildschirm
                    // eine Leiste gibt.
                    Runtime.barHover = Math.max(0, Runtime.barHover + (hovered ? 1 : -1));
                }
            }

            // Zugeklappte Insel. Beide Zustaende werden ueberblendet, nicht
            // ueber `visible` geschaltet: ein unsichtbarer Positionierer meldet
            // keine brauchbare implicitWidth mehr -- und genau die braucht der
            // Rahmen oben, um seine Zielbreite zu kennen.
            Row {
                id: collapsed

                anchors.centerIn: parent
                spacing: Theme.barItemGap
                // Keep the compact clock fixed while the shell grows. The
                // second clock in the center group takes over only near the
                // end, avoiding a double-rendered sideways wobble.
                opacity: win.osdInPill || win.barMode || win.pillMode ? 0
                    : (win.reuseCollapsedCenter ? 1 : 1 - win.centerHandoff)
                enabled: (win.reuseCollapsedCenter || win.openProgress < 0.5) && !win.osdInPill

                Repeater {
                    model: win.collapsedWidgetNames

                    WidgetHost {
                        required property var modelData
                        widgetName: modelData
                        screenName: win.modelData?.name ?? ""
                        externalPopoutEligible: win.expandedWidgetNames.indexOf(modelData) < 0
                    }
                }
            }

            Row {
                id: content

                anchors.verticalCenter: parent.verticalCenter
                x: win.barMode ? Theme.padX : (parent.width - width) / 2
                spacing: 0
                opacity: win.osdInPill ? 0 : win.openProgress
                enabled: win.openProgress >= 0.5 && !win.osdInPill

                // Im Balken muessen die Zwischenraeume so breit sein, dass die
                // Mittelgruppe wirklich in der Bildschirmmitte steht -- und
                // nicht dort, wo sie nach zwei gleich grossen Luecken landet.
                readonly property real free: win.width - Theme.padX * 2 - leftGroup.implicitWidth - centerGroup.implicitWidth - rightGroup.implicitWidth
                readonly property real barLeftGap: Math.max(Theme.gap, free / 2 - (leftGroup.implicitWidth - rightGroup.implicitWidth) / 2)
                readonly property real barRightGap: Math.max(Theme.gap, free - barLeftGap)

                // In der Insel geht das nicht ueber die freie Breite -- sie hat
                // keine, sie ist genau so breit wie ihr Inhalt. Die Mitte wird
                // deshalb ueber die Luecken erzwungen: die schmalere Seite
                // bekommt den Unterschied dazu, und damit sitzt die
                // Mittelgruppe genau in der Mitte der Insel. Weil die Insel
                // selbst mittig auf dem Bildschirm steht, sitzt die Uhr damit
                // auch dort -- ausgeklappt wie zugeklappt.
                //
                // Der Preis: die Insel wird um den Unterschied breiter.
                // `islandCenter: false` nimmt beides zurueck.
                readonly property real islandDiff: Config.islandCenter ? Math.abs(leftGroup.implicitWidth - rightGroup.implicitWidth) : 0
                readonly property real islandLeftGap: Theme.gap + (leftGroup.implicitWidth < rightGroup.implicitWidth ? content.islandDiff : 0)
                readonly property real islandRightGap: Theme.gap + (rightGroup.implicitWidth < leftGroup.implicitWidth ? content.islandDiff : 0)
                readonly property real layoutProgress: win.barMode ? 1 : (Config.islandExpandFullWidth && !win.pillMode ? win.openProgress : 0)
                readonly property real compactWidth: leftGroup.implicitWidth + islandLeftGap + centerGroup.implicitWidth + islandRightGap + rightGroup.implicitWidth

                Row {
                    id: leftGroup
                    spacing: Theme.barItemGap

                    Repeater {
                        model: win.expandedLeftWidgetNames

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }
                }

                Item {
                    id: leftSpacer
                    width: content.islandLeftGap + (content.barLeftGap - content.islandLeftGap) * content.layoutProgress
                    height: 1
                }

                Row {
                    id: centerGroup
                    spacing: Theme.barItemGap
                    opacity: win.barMode || win.pillMode ? 1
                        : (win.reuseCollapsedCenter ? 0 : win.centerHandoff)

                    // The side groups can change width while quiet widgets
                    // appear. Counter that layout movement so the clock stays
                    // exactly at the frame center throughout the transition.
                    transform: Translate {
                        x: frame.width / 2 - content.x
                           - leftGroup.implicitWidth - leftSpacer.width
                           - centerGroup.implicitWidth / 2
                    }

                    Repeater {
                        model: win.expandedCenterWidgetNames

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }
                }

                Item {
                    id: rightSpacer
                    width: content.islandRightGap + (content.barRightGap - content.islandRightGap) * content.layoutProgress
                    height: 1
                }

                Item {
                    id: rightGroupSlot
                    width: rightGroup.implicitWidth
                    height: rightGroup.implicitHeight

                    Row {
                        id: rightGroup
                        spacing: Theme.barItemGap

                    readonly property var visibleWidgets: win.expandedRightWidgetNames
                    readonly property int collapseIndex: visibleWidgets.indexOf("sep")
                    readonly property var fixedWidgets: collapseIndex >= 0
                        ? visibleWidgets.slice(0, collapseIndex) : visibleWidgets
                    readonly property var collapsibleWidgets: collapseIndex >= 0
                        ? visibleWidgets.slice(collapseIndex + 1) : []
                    property real sectionProgress: Config.rightSectionExpanded ? 1 : 0

                        Behavior on sectionProgress {
                            enabled: !win.barMode
                            NumberAnimation {
                                duration: Config.rightSectionExpanded ? Theme.motionSpatialDefault : Theme.motionSpatialFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.motionCurveStandard
                            }
                        }

                        function startSectionMotion() {
                            if (!win.barMode)
                                return;

                            sectionMotion.stop();
                            const distance = rightSectionRow.implicitWidth;
                            // The slot has already taken its target width. Keep
                            // the painted row at the old edge, then animate only
                            // composited properties into their target values.
                            rightGroup.x = Config.rightSectionExpanded ? distance : -distance;
                            rightSectionRow.x = Config.rightSectionExpanded ? Theme.cellW * 0.75 : 0;
                            rightSectionClip.opacity = Config.rightSectionExpanded ? 0 : 1;
                            sectionMotion.start();
                        }

                        ParallelAnimation {
                            id: sectionMotion

                            XAnimator {
                                target: rightGroup
                                to: 0
                                duration: Config.rightSectionExpanded ? Theme.motionSpatialDefault : Theme.motionSpatialFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.motionCurveStandard
                            }

                            XAnimator {
                                target: rightSectionRow
                                to: Config.rightSectionExpanded ? 0 : Theme.cellW * 0.75
                                duration: Config.rightSectionExpanded ? Theme.motionSpatialDefault : Theme.motionSpatialFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.motionCurveStandard
                            }

                            OpacityAnimator {
                                target: rightSectionClip
                                to: Config.rightSectionExpanded ? 1 : 0
                                duration: Config.rightSectionExpanded ? Theme.motionEffectsDefault : Theme.motionEffectsFast
                                easing.type: Easing.OutCubic
                            }
                        }

                        Connections {
                            target: Config

                            function onRightSectionExpandedChanged() {
                                rightGroup.startSectionMotion();
                            }
                        }

                    Repeater {
                        model: rightGroup.fixedWidgets

                        WidgetHost {
                            required property var modelData
                            widgetName: modelData
                            screenName: win.modelData?.name ?? ""
                        }
                    }

                    // The configured separator becomes a compact boundary
                    // control. It stays visible while every widget to its right
                    // slides away, and does not touch the tray's own expansion.
                    InteractiveSurface {
                        id: rightSectionToggle
                        visible: rightGroup.collapseIndex >= 0
                        width: visible ? Theme.cellW * 1.8 : 0
                        height: Theme.cellH
                        accessibleName: Config.rightSectionExpanded
                            ? "Collapse right bar section" : "Expand right bar section"
                        accessibleDescription: "Shows or hides the widgets after the separator"
                        accessibleCheckable: true
                        accessibleChecked: Config.rightSectionExpanded
                        accessiblePressed: rightSectionTap.pressed
                        radius: Theme.radius
                        color: visualFocus ? Theme.controlFill(true, false, false) : "transparent"
                        border.width: visualFocus ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder
                        onTriggered: Config.set("rightSectionExpanded", !Config.rightSectionExpanded)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(1, Theme.borderWidth)
                            height: parent.height * 0.6
                            color: Theme.muted
                        }

                        Line {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "«"
                            rotation: Config.rightSectionExpanded ? 0 : 180
                            color: rightSectionHover.hovered ? Theme.text : Theme.textDim

                            Behavior on rotation {
                                RotationAnimator {
                                    duration: Theme.motionSpatialFast
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        HoverHandler {
                            id: rightSectionHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            id: rightSectionTap
                            onTapped: {
                                rightSectionToggle.forceActiveFocus(Qt.MouseFocusReason);
                                rightSectionToggle.activate();
                            }
                        }
                    }

                    Item {
                        id: rightSectionClip
                        visible: rightGroup.collapseIndex >= 0
                        // Bar mode lets the old pixels overflow while the whole
                        // group slides to its new layout position. The frame is
                        // still the final clip boundary.
                        clip: !win.barMode
                        height: Math.max(Theme.cellH, rightSectionRow.implicitHeight)
                        width: !visible ? 0 : (win.barMode
                            ? (Config.rightSectionExpanded ? rightSectionRow.implicitWidth : 0)
                            : rightSectionRow.implicitWidth * rightGroup.sectionProgress)
                        opacity: Config.rightSectionExpanded ? 1 : 0
                        enabled: Config.rightSectionExpanded

                        Row {
                            id: rightSectionRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: Config.rightSectionExpanded ? 0 : Theme.cellW * 0.75
                            spacing: Theme.barItemGap


                            Repeater {
                                model: rightGroup.collapsibleWidgets

                                WidgetHost {
                                    required property var modelData
                                    widgetName: modelData
                                    screenName: win.modelData?.name ?? ""
                                }
                            }
                        }
                    }
                }
                }
            }

            // Die Einblendung, wenn sie in der Pille steht -- dieselben drei
            // Teile wie im eigenen Fenster (Osd/Osd.qml), damit beide Wege
            // gleich aussehen.
            //
            // Sie wird nie abgeschaltet, nur ausgeblendet: der Rahmen oben
            // fragt ihre `implicitWidth` ab, und ein unsichtbarer Positionierer
            // meldet keine brauchbare mehr. Aus demselben Grund gibt es die
            // zugeklappte Reihe zweimal statt einmal geschaltet.
            Row {
                id: osdRow

                anchors.centerIn: parent
                spacing: Theme.cellW * 2
                opacity: win.osdInPill ? 1 : 0
                // Nur Anzeige: der Regler steht im Audiofenster, hier waere er
                // ein Klickziel, das nach zwei Sekunden verschwindet.
                enabled: false

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motionEffectsFast
                    }
                }

                Line {
                    text: Osd.label
                    color: Theme.fgDim
                }

                LevelBar {
                    cells: 24
                    value: Osd.value
                    interactive: false
                    fillColor: Osd.muted ? Theme.muted : Osd.tint
                }

                Line {
                    // Feste Breite in Zeichen, damit die Pille beim Regeln
                    // nicht atmet.
                    text: (Osd.muted ? "muted" : (Osd.value + "%")).padStart(6, " ")
                    color: Osd.muted ? Theme.red : Theme.fg
                }
            }
        }
    }
}
