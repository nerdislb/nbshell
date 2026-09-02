import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Standalone theme browser. It is deliberately independent from the optional
// bar widget so every menu, IPC, and desktop gesture opens the same surface.
PanelWindow {
    id: root

    property int selected: 0
    property string query: ""
    readonly property var filteredThemes: {
        const needle = query.trim().toLocaleLowerCase();
        if (!needle)
            return ThemeIndex.list;
        return ThemeIndex.list.filter(theme => String(theme.name || "").toLocaleLowerCase().includes(needle));
    }
    readonly property var current: filteredThemes[selected] ?? null

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:themes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.themePickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function themeIndex() {
        const index = filteredThemes.findIndex(theme => theme.name === Config.theme);
        return index >= 0 ? index : 0;
    }
    function select(index) {
        if (!filteredThemes.length)
            return;
        selected = (index + filteredThemes.length) % filteredThemes.length;
    }
    function move(delta) { select(selected + delta); }
    function apply() {
        if (!current)
            return;
        ThemeIndex.apply(current.name);
        close();
    }
    function close() { frame.dismiss(() => Runtime.themePickerOpen = false); }
    function requestClose(done) { frame.dismiss(done); }
    function requestOpen() { frame.enter(); }

    onVisibleChanged: if (visible) {
        query = "";
        ThemeIndex.refresh();
        selected = themeIndex();
        searchInput.forceActiveFocus();
        Qt.callLater(() => strip.positionViewAtIndex(selected, ListView.Center));
    }

    onQueryChanged: {
        selected = themeIndex();
        Qt.callLater(() => {
            if (filteredThemes.length)
                strip.positionViewAtIndex(selected, ListView.Center);
        });
    }

    Connections {
        target: ThemeIndex
        function onListChanged() {
            root.selected = root.themeIndex();
            Qt.callLater(() => {
                if (root.filteredThemes.length)
                    strip.positionViewAtIndex(root.selected, ListView.Center);
            });
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: frame.opacity * 0.55 }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onLeftPressed: root.move(-1)
        Keys.onRightPressed: root.move(1)
        Keys.onReturnPressed: root.apply()
        Keys.onEnterPressed: root.apply()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                root.select(0);
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                root.select(root.filteredThemes.length - 1);
                event.accepted = true;
            }
        }

        MotionSurface {
            id: frame
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.spaceXl * 4, Theme.cellW * 116)
            height: Math.min(parent.height - Theme.spaceXl * 4, Theme.cellH * 39)
            accentBorder: true
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceMd

                PanelHead {
                    rowWidth: parent.width
                    icon: Icons.palette
                    title: root.current?.name || "Themes"
                    subtitle: root.current?.name === Config.theme ? "Current theme" : "Preview"
                    badge: ThemeIndex.loading ? "…" : String(ThemeIndex.list.length)
                }

                Rule { rowWidth: parent.width }

                Rectangle {
                    width: parent.width
                    height: Theme.controlHeight
                    radius: Theme.radius
                    color: Theme.controlFill(searchHover.hovered || searchInput.activeFocus, false, false)
                    border.width: searchInput.activeFocus ? Theme.borderWidth : Theme.controlBorderWidth(searchHover.hovered, false, false)
                    border.color: searchInput.activeFocus ? Theme.focusBorder : Theme.controlBorder(searchHover.hovered, false, false)

                    Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }

                    Line {
                        id: searchPrompt
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spaceLg
                        anchors.verticalCenter: parent.verticalCenter
                        text: ">"
                        color: Theme.accent
                        font.pixelSize: Theme.fontBody
                        Accessible.ignored: true
                    }

                    TextField {
                        id: searchInput
                        anchors.left: searchPrompt.right
                        anchors.right: matchCount.left
                        anchors.leftMargin: Theme.spaceSm
                        anchors.rightMargin: Theme.spaceLg
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query
                        color: Theme.fg
                        selectionColor: Theme.selectedSurface(Theme.accent)
                        selectedTextColor: Theme.selectedForeground(Theme.accent)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBody
                        background: null
                        horizontalPadding: 0
                        clip: true
                        activeFocusOnTab: true
                        accessibleName: "Search themes"
                        accessibleDescription: "Filters the available themes"
                        Accessible.name: "Search themes"
                        onTextEdited: root.query = text
                        Keys.onEscapePressed: root.close()
                        Keys.onLeftPressed: root.move(-1)
                        Keys.onRightPressed: root.move(1)
                        Keys.onReturnPressed: root.apply()
                        Keys.onEnterPressed: root.apply()
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Home) {
                                root.select(0);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_End) {
                                root.select(root.filteredThemes.length - 1);
                                event.accepted = true;
                            }
                        }
                    }

                    Line {
                        anchors.left: searchInput.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "type to search themes"
                        color: Theme.muted
                        font.pixelSize: Theme.fontBody
                        Accessible.ignored: true
                    }

                    Line {
                        id: matchCount
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spaceLg
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.filteredThemes.length) + " / " + String(ThemeIndex.list.length)
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                    }

                    HoverHandler { id: searchHover; cursorShape: Qt.IBeamCursor }
                    TapHandler { onTapped: searchInput.forceActiveFocus() }
                }

                ListView {
                    id: strip
                    readonly property real cardWidth: Math.min(Theme.cellW * 35, width * 0.36)
                    width: parent.width
                    height: parent.height - Theme.cellH * 10.2
                    orientation: ListView.Horizontal
                    model: root.filteredThemes
                    currentIndex: root.selected
                    spacing: Theme.spaceLg
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - cardWidth) / 2
                    preferredHighlightEnd: preferredHighlightBegin + cardWidth
                    highlightMoveDuration: Theme.reducedMotion ? 0 : Theme.motionMove
                    highlightMoveVelocity: -1
                    keyNavigationWraps: true

                    function centerSelection() {
                        if (!root.filteredThemes.length)
                            return;
                        const center = strip.contentX + strip.width / 2;
                        let closest = root.selected;
                        let distance = Number.MAX_VALUE;
                        for (let index = 0; index < count; index++) {
                            const item = itemAtIndex(index);
                            if (!item)
                                continue;
                            const itemCenter = item.x + item.width / 2;
                            const candidate = Math.abs(itemCenter - center);
                            if (candidate < distance) {
                                distance = candidate;
                                closest = index;
                            }
                        }
                        root.select(closest);
                    }

                    onMovementEnded: centerSelection()

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: wheelEvent => {
                            const delta = Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y)
                                ? wheelEvent.angleDelta.x : wheelEvent.angleDelta.y;
                            root.move(delta > 0 ? -1 : 1);
                        }
                    }

                    Line {
                        anchors.centerIn: parent
                        visible: root.filteredThemes.length === 0
                        text: "No themes match ‘" + root.query + "’"
                        color: Theme.muted
                        font.pixelSize: Theme.fontBody
                    }

                    delegate: Item {
                        id: cardSlot
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.selected
                        width: strip.cardWidth
                        height: strip.height

                        Rectangle {
                            id: card
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height * 0.92
                            scale: cardSlot.selected ? 1 : 0.88
                            opacity: cardSlot.selected ? 1 : 0.52
                            color: cardSlot.modelData.background || Theme.bgDarker
                            radius: Theme.radius
                            border.width: cardSlot.selected ? Math.max(2, Theme.borderWidth * 2) : Theme.borderWidth
                            border.color: cardSlot.modelData.accent || Theme.panelBorder

                            Behavior on scale {
                                enabled: !Theme.reducedMotion
                                NumberAnimation {
                                    duration: Theme.motionMove
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.motionCurveEffect
                                }
                            }
                            Behavior on opacity {
                                enabled: !Theme.reducedMotion
                                NumberAnimation { duration: Theme.motionEffect }
                            }

                            Image {
                                id: wallpaper
                                anchors.fill: parent
                                anchors.margins: card.border.width
                                source: String(cardSlot.modelData.wallpaper || "") !== ""
                                    ? "file://" + String(cardSlot.modelData.wallpaper) : ""
                                visible: status === Image.Ready
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: Math.max(1, Math.ceil(width))
                                sourceSize.height: Math.max(1, Math.ceil(height))
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.alpha(cardSlot.modelData.background || Theme.bgDarker,
                                    cardSlot.selected ? 0.36 : 0.58)
                                radius: parent.radius
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.76
                                height: parent.height * 0.52
                                color: Theme.alpha(cardSlot.modelData.background || Theme.bgDarker, 0.94)
                                radius: Theme.radius
                                border.width: Theme.borderWidth
                                border.color: cardSlot.modelData.accent || Theme.panelBorder

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spaceLg
                                    spacing: Theme.spaceSm

                                    Row {
                                        spacing: Theme.spaceXs
                                        Repeater {
                                            model: [cardSlot.modelData.red, cardSlot.modelData.yellow, cardSlot.modelData.green]
                                            Rectangle {
                                                required property var modelData
                                                width: Theme.cellH * 0.46
                                                height: width
                                                radius: width / 2
                                                color: modelData || Theme.muted
                                            }
                                        }
                                    }
                                    Line {
                                        width: parent.width
                                        text: "$ nbshell theme " + cardSlot.modelData.name
                                        color: cardSlot.modelData.accent || Theme.accent
                                        font.pixelSize: Theme.fontCaption
                                        elide: Text.ElideRight
                                    }
                                    Line {
                                        width: parent.width
                                        text: "Umbriel  ·  nbshell"
                                        color: cardSlot.modelData.foreground || Theme.fg
                                        font.pixelSize: Theme.fontBody
                                        elide: Text.ElideRight
                                    }
                                    Item { width: 1; height: Theme.spaceSm }
                                    Row {
                                        width: parent.width
                                        spacing: 1
                                        Repeater {
                                            model: [
                                                cardSlot.modelData.red, cardSlot.modelData.yellow,
                                                cardSlot.modelData.green, cardSlot.modelData.cyan,
                                                cardSlot.modelData.blue, cardSlot.modelData.magenta,
                                                cardSlot.modelData.accent, cardSlot.modelData.foreground
                                            ]
                                            Rectangle {
                                                required property var modelData
                                                width: (parent.width - 7) / 8
                                                height: Theme.cellH
                                                color: modelData || "transparent"
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Theme.cellH * 4
                                color: Theme.alpha(cardSlot.modelData.background || Theme.bgDarker, 0.92)
                                radius: parent.radius

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.spaceXl * 2
                                    spacing: Theme.spaceXs
                                    Line {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width
                                        text: cardSlot.modelData.name
                                        color: cardSlot.modelData.foreground || Theme.fg
                                        font.pixelSize: Theme.fontTitle
                                        font.bold: cardSlot.selected
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                    Line {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cardSlot.modelData.name === Config.theme ? "ACTIVE" : (cardSlot.selected ? "ENTER TO APPLY" : "")
                                        color: cardSlot.modelData.accent || Theme.accent
                                        font.pixelSize: Theme.fontCaption
                                    }
                                }
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: root.select(cardSlot.index)
                                onDoubleTapped: {
                                    root.select(cardSlot.index);
                                    root.apply();
                                }
                            }
                        }
                    }
                }

                Rule { rowWidth: parent.width }

                Row {
                    width: parent.width
                    height: Theme.controlHeight
                    spacing: Theme.spaceSm

                    Line {
                        width: parent.width - applyButton.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "type to search  ·  ← → browse  ·  scroll or swipe  ·  Enter apply  ·  Esc close"
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }
                    ControlButton {
                        id: applyButton
                        width: Theme.cellW * 22
                        height: Theme.controlHeight
                        text: root.current?.name === Config.theme ? "CURRENT" : "APPLY THEME"
                        enabled: !!root.current && root.current?.name !== Config.theme
                        onTriggered: root.apply()
                    }
                }
            }
        }
    }
}
