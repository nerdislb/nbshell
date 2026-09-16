import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Visual geometry adapted from Omarchy's ImagePicker at 6ea3215 (MIT).
// Only the view is shared: nbshell keeps its theme store and apply backend.
PanelWindow {
    id: root
    property string query: ""
    property string selectedName: Config.theme
    property bool closing: false
    readonly property var filteredThemes: ThemeIndex.list.filter(theme => {
        const needle = query.trim().toLocaleLowerCase();
        return String(theme.name).toLocaleLowerCase().includes(needle)
            || label(theme.name).toLocaleLowerCase().includes(needle);
    })
    readonly property int selected: filteredThemes.findIndex(theme => theme.name === selectedName)
    readonly property var current: selected >= 0 ? filteredThemes[selected] : null
    // These are the upstream image-fan dimensions, not a new control scale.
    readonly property real fit: Math.max(0.1, Math.min(1, (width - Theme.spaceXl * 2) / 900,
        (height - Theme.spaceXl * 2) / (475 + 30 * Theme.menuScale + chromeHeight)))
    readonly property real previewWidth: 768 * fit
    readonly property real previewHeight: 475 * fit
    readonly property real sliceWidth: 108 * fit
    readonly property real sliceHeight: 432 * fit
    readonly property real sliceSpacing: -30 * fit
    readonly property real skew: 28 * fit
    readonly property real chromeHeight: Math.max(104, Theme.audioHeroSize + Theme.audioTitleSize + Theme.spaceLg * 3)
    readonly property real topSpace: 30 * Theme.menuScale * fit

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:themes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.themePickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function label(name) {
        return String(name || "").replace(/[-_]+/g, " ").replace(/\b\w/g, ch => ch.toUpperCase());
    }
    function reconcile() {
        if (filteredThemes.length && !filteredThemes.some(theme => theme.name === selectedName))
            selectedName = filteredThemes[0].name;
    }
    function select(index) {
        if (!filteredThemes.length || closing) return;
        selectedName = filteredThemes[(index + filteredThemes.length) % filteredThemes.length].name;
    }
    function move(delta) { select(Math.max(0, selected) + delta); }
    function apply() {
        if (!current || closing || ThemeIndex.loading) return;
        closing = true;
        ThemeIndex.apply(current.name);
        Runtime.themePickerOpen = false;
    }
    function close() { closing = true; Runtime.themePickerOpen = false; }
    function requestClose(done) { closing = true; done(); }
    function requestOpen() { closing = false; Qt.callLater(() => keys.forceActiveFocus()); }
    function handleEscape() { if (query) query = ""; else close(); }
    onFilteredThemesChanged: reconcile()
    Component.onCompleted: {
        ThemeIndex.refresh();
        Qt.callLater(() => { reconcile(); keys.forceActiveFocus(); });
    }

    Rectangle { anchors.fill: parent; color: Theme.menuScrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
        id: keys
        anchors.fill: parent
        clip: true
        focus: true
        Accessible.role: Accessible.List
        Accessible.name: "Choose theme"
        Accessible.description: "Type to search. Left, Right or Tab to browse. Enter to apply. Escape to clear search or close. " + (root.current ? root.label(root.current.name) : "No matches")
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.handleEscape();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat) root.apply();
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) root.move(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.move(1);
            else if (event.key === Qt.Key_Home) root.select(0);
            else if (event.key === Qt.Key_End) root.select(root.filteredThemes.length - 1);
            else if (event.key === Qt.Key_Backspace) root.query = event.modifiers & Qt.ControlModifier ? "" : root.query.slice(0, -1);
            else if (event.key === Qt.Key_U && event.modifiers & Qt.ControlModifier) root.query = "";
            else if (event.text && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.charCodeAt(0) >= 32) root.query += event.text;
            else return;
            event.accepted = true;
        }

        Item {
            id: frame
            anchors.centerIn: parent
            width: parent.width
            height: root.previewHeight + root.topSpace + root.chromeHeight
            MouseArea { anchors.fill: parent; onClicked: {} }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                    if (delta !== 0) root.move(delta > 0 ? -1 : 1);
                    event.accepted = true;
                }
            }
            DragHandler {
                id: swipe
                target: null
                yAxis.enabled: false
                property real distance: 0
                onTranslationChanged: if (active) distance = activeTranslation.x
                onActiveChanged: {
                    if (active) distance = 0;
                    else if (Math.abs(distance) > Theme.spaceXl) root.move(distance > 0 ? -1 : 1);
                }
            }
            Item {
                id: carousel
                y: root.topSpace
                width: parent.width
                height: root.previewHeight
                readonly property real previewX: (width - root.previewWidth) / 2
                readonly property real itemStep: root.sliceWidth + root.sliceSpacing
                Repeater {
                    model: root.filteredThemes
                    delegate: InteractiveSurface {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property int relativeIndex: index - root.selected
                        readonly property bool selected: index === root.selected
                        // Allocate masks/textures only for slices intersecting this output.
                        readonly property bool nearby: x + width >= 0 && x <= carousel.width
                        readonly property string previewPath: modelData.preview || modelData.wallpaper || ""
                        visible: nearby
                        color: "transparent"
                        keyboardFocusable: false
                        accessibleRole: Accessible.ListItem
                        accessibleName: root.label(modelData.name)
                        accessibleSelected: selected
                        accessibleDescription: selected ? "Apply theme" : "Preview theme"
                        onTriggered: {
                            keys.forceActiveFocus();
                            if (selected) root.apply(); else root.select(index);
                        }
                        x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.previewWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
                        width: selected ? root.previewWidth : root.sliceWidth
                        height: selected ? root.previewHeight : root.sliceHeight
                        y: selected ? 0 : (root.previewHeight - root.sliceHeight) / 2
                        z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)
                        Item {
                            id: maskShape
                            anchors.fill: parent
                            visible: false
                            layer.enabled: tile.nearby
                            Shape {
                                anchors.fill: parent
                                antialiasing: true
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "white"
                                    strokeColor: "transparent"
                                    startX: root.skew; startY: 0
                                    PathLine { x: tile.width; y: 0 }
                                    PathLine { x: tile.width - root.skew; y: tile.height }
                                    PathLine { x: 0; y: tile.height }
                                    PathLine { x: root.skew; y: 0 }
                                }
                            }
                        }
                        Item {
                            anchors.fill: parent
                            layer.enabled: tile.nearby
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: maskShape
                                maskThresholdMin: 0.3
                                maskSpreadAtMin: 0.3
                            }
                            Rectangle { anchors.fill: parent; color: tile.modelData.background || Theme.bg }
                            Image {
                                id: wallpaper
                                anchors.fill: parent
                                source: tile.nearby && tile.previewPath ? "file://" + tile.previewPath.split("/").map(encodeURIComponent).join("/") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: Math.round(root.previewWidth * (root.screen?.devicePixelRatio || 1))
                                sourceSize.height: Math.round(root.previewHeight * (root.screen?.devicePixelRatio || 1))
                            }
                            Column {
                                anchors.centerIn: parent
                                width: parent.width * 0.75
                                spacing: Theme.spaceMd
                                visible: wallpaper.status !== Image.Ready
                                Line {
                                    width: parent.width
                                    text: root.label(tile.modelData.name)
                                    color: tile.modelData.foreground || Theme.fg
                                    font.pixelSize: Theme.audioTitleSize
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                                Row {
                                    width: parent.width
                                    Repeater {
                                        model: [tile.modelData.red, tile.modelData.yellow, tile.modelData.green, tile.modelData.cyan, tile.modelData.blue, tile.modelData.magenta]
                                        Rectangle {
                                            required property var modelData
                                            width: parent.width / 6
                                            height: Theme.cellH
                                            color: modelData || Theme.muted
                                        }
                                    }
                                }
                            }
                            Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, tile.selected ? 0 : 0.42) }
                        }
                        Shape {
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: tile.selected ? Theme.accent : Theme.alpha(Theme.fg, 0.28)
                                strokeWidth: tile.selected ? 3 : 1
                                startX: root.skew; startY: 0
                                PathLine { x: tile.width; y: 0 }
                                PathLine { x: tile.width - root.skew; y: tile.height }
                                PathLine { x: 0; y: tile.height }
                                PathLine { x: root.skew; y: 0 }
                            }
                        }
                        TapHandler { onTapped: tile.activate() }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
            Line {
                id: nameLabel
                anchors.top: carousel.bottom
                anchors.topMargin: Math.round(16 * Theme.menuScale)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.previewWidth, parent.width - Theme.spaceXl * 2)
                text: root.current ? root.label(root.current.name) : (ThemeIndex.loading ? "Loading themes…" : (root.query ? "No matches" : "No themes installed"))
                color: Theme.fg
                style: Text.Outline
                styleColor: Theme.alpha(Theme.bg, 0.7)
                font.pixelSize: Theme.audioHeroSize
                font.family: "sans-serif"
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Line {
                anchors.top: nameLabel.bottom
                anchors.topMargin: Theme.spaceSm
                anchors.horizontalCenter: parent.horizontalCenter
                width: nameLabel.width
                text: root.query
                color: Theme.fg
                opacity: 0.85
                style: Text.Outline
                styleColor: Theme.alpha(Theme.bg, 0.7)
                font.pixelSize: Theme.audioTitleSize
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
