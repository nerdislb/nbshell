import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// One lightweight library over nbshell's existing, separately reviewed
// theme, wallpaper, and plugin paths. The window is lazy loaded, and it never
// downloads or activates content merely because it was browsed.
PanelWindow {
    id: root

    property string tab: "themes"
    property string query: ""
    property int selected: 0
    property real previewScale: 1
    property real previewOpacity: 1

    readonly property var sourceItems: tab === "themes" ? ThemeIndex.list
        : tab === "wallpapers" ? Wallpapers.list : Plugins.plugins
    readonly property var items: sourceItems.filter(item => {
        const needle = query.trim().toLowerCase();
        if (!needle) return true;
        return [label(item), detail(item), item?.theme, item?.category, item?.author]
            .some(value => String(value || "").toLowerCase().indexOf(needle) >= 0);
    })
    readonly property var current: items[selected] ?? null

    function pulsePreview() {
        if (Theme.reducedMotion) return;
        previewScale = Theme.expressiveMotion ? 0.955 : 0.985;
        previewOpacity = 0.35;
        Qt.callLater(() => {
            root.previewScale = 1;
            root.previewOpacity = 1;
        });
    }

    visible: Runtime.storeOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:store"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function label(item) {
        if (tab === "wallpapers") return Wallpapers.nameOf(item);
        return String(item?.name || item?.id || "Unknown");
    }
    function detail(item) {
        if (tab === "themes") {
            const count = wallpaperCount(item?.name);
            return String(item?.mode || "theme").toUpperCase() + " · " + count + " WALLPAPER" + (count === 1 ? "" : "S");
        }
        if (tab === "wallpapers") return String(item?.theme || "collection");
        return String(item?.description || item?.category || "Plugin");
    }
    function wallpaperCount(theme) {
        const name = String(theme || "");
        return Wallpapers.list.filter(item => Wallpapers.themeOf(item) === name).length;
    }
    function neighbor(delta) {
        if (!items.length) return null;
        const index = (selected + delta + items.length) % items.length;
        return items[index] ?? null;
    }
    function moveWrapped(delta) {
        if (!items.length) return;
        selected = (selected + delta + items.length) % items.length;
        list.positionViewAtIndex(selected, ListView.Contain);
    }
    function close() { frame.dismiss(() => Runtime.storeOpen = false); }
    function chooseTab(value) {
        tab = value;
        selected = 0;
        query = "";
        if (value === "wallpapers") Wallpapers.refresh();
        if (value === "plugins") Plugins.refresh();
        Qt.callLater(search.forceActiveFocus);
    }
    function move(delta) {
        if (!items.length) return;
        selected = Math.max(0, Math.min(items.length - 1, selected + delta));
        list.positionViewAtIndex(selected, ListView.Contain);
    }
    function activate(item) {
        if (!item) return;
        if (tab === "themes") ThemeIndex.apply(item.name);
        else if (tab === "wallpapers") Wallpapers.apply(Wallpapers.pathOf(item));
        else {
            Runtime.pluginManagerTab = "installed";
            Runtime.pluginDeveloperOpen = true;
            close();
        }
    }
    function browse() {
        if (tab === "plugins") {
            Runtime.pluginManagerTab = "store";
            Runtime.pluginDeveloperOpen = true;
            close();
        } else if (tab === "wallpapers") {
            Runtime.wallpaperOpen = true;
            close();
        } else {
            Runtime.themePickerOpen = true;
            close();
        }
    }

    onItemsChanged: selected = Math.max(0, Math.min(selected, items.length - 1))
    onSelectedChanged: pulsePreview()
    onTabChanged: pulsePreview()
    onVisibleChanged: if (visible) {
        ThemeIndex.refresh();
        Wallpapers.refresh();
        Plugins.refresh();
        selected = 0;
        Qt.callLater(search.forceActiveFocus);
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    MotionSurface {
        id: frame
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spaceXl * 4, Math.round(Theme.cellW * 112))
        height: Math.min(parent.height - Theme.spaceXl * 4, Math.round(Theme.cellH * 42))
        accentBorder: true
        MouseArea { anchors.fill: parent }

        FocusScope {
            anchors.fill: parent
            focus: root.visible
            Keys.onEscapePressed: root.close()
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onReturnPressed: root.activate(root.current)
            Keys.onEnterPressed: root.activate(root.current)

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceMd

                PanelHead {
                    rowWidth: parent.width
                    icon: "󰏖"
                    title: "Library"
                    subtitle: "Themes, wallpapers, and reviewed extensions"
                    badge: String(root.items.length)
                }

                Row {
                    width: parent.width
                    height: Theme.controlHeight
                    spacing: Theme.spaceSm
                    Repeater {
                        model: [{id: "themes", label: "THEMES"}, {id: "wallpapers", label: "WALLPAPERS"}, {id: "plugins", label: "PLUGINS"}]
                        ControlButton {
                            required property var modelData
                            text: modelData.label
                            selected: root.tab === modelData.id
                            onTriggered: root.chooseTab(modelData.id)
                        }
                    }
                    Rectangle {
                        width: parent.width - Theme.cellW * 42
                        height: Theme.controlHeight
                        color: Theme.panelSurfaceRaised
                        radius: Theme.radius
                        border.width: search.activeFocus ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceMd
                            anchors.rightMargin: Theme.spaceMd
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            selectionColor: Theme.selection
                            selectedTextColor: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            text: root.query
                            onTextEdited: root.query = text
                            Keys.onEscapePressed: root.close()
                            Keys.onUpPressed: root.move(-1)
                            Keys.onDownPressed: root.move(1)
                            Keys.onReturnPressed: root.activate(root.current)
                        }
                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Search this collection"
                            color: Theme.muted
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: parent.height - Theme.controlHeight * 2 - Theme.cellH * 4
                    spacing: Theme.spaceLg

                    ListView {
                        id: list
                        width: parent.width * 0.48
                        height: parent.height
                        model: root.items
                        currentIndex: root.selected
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: Theme.spaceXs
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: list.width
                            height: Theme.menuRowHeight
                            color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"
                            radius: Theme.radius
                            border.width: index === root.selected ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder
                            scale: index === root.selected ? 1 : 0.985
                            Behavior on color { ColorAnimation { duration: Theme.motionFast } }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Theme.motionEffect
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.motionCurveEffect
                                }
                            }
                            Line {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spaceMd
                                anchors.right: state.left
                                anchors.rightMargin: Theme.spaceMd
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.label(row.modelData)
                                color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                                elide: Text.ElideRight
                            }
                            Line {
                                id: state
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spaceMd
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.tab === "themes" ? (row.modelData.name === Config.theme ? "ACTIVE" : root.wallpaperCount(row.modelData.name) + " WP")
                                    : root.tab === "wallpapers" ? (Wallpapers.pathOf(row.modelData) === Wallpapers.current ? "ACTIVE" : "")
                                    : Plugins.enabledIds.indexOf(row.modelData.id) >= 0 ? "ENABLED" : "INSTALLED"
                                color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.muted
                                font.pixelSize: Theme.fontCaption
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.selected = row.index
                                onClicked: root.activate(row.modelData)
                            }
                        }
                    }

                    PanelSurface {
                        width: parent.width - list.width - parent.spacing
                        height: parent.height
                        color: Theme.panelSurfaceRaised

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceXl
                            spacing: Theme.spaceLg

                            Rectangle {
                                id: visualPreview
                                width: parent.width
                                height: Math.min(parent.height * 0.48, Theme.cellH * 15)
                                color: root.tab === "themes" ? (root.current?.background || Theme.bgDarker) : Theme.bgDarker
                                radius: Theme.radius
                                border.width: Theme.borderWidth
                                border.color: root.tab === "themes" ? (root.current?.accent || Theme.accent) : Theme.panelBorder
                                scale: root.previewScale
                                opacity: root.previewOpacity
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Theme.motionMove
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.motionCurveEffect
                                    }
                                }
                                Behavior on opacity { NumberAnimation { duration: Theme.motionEffect } }
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.borderWidth
                                    visible: (root.tab === "wallpapers" || root.tab === "themes") && !!root.current
                                    source: visible ? "file://" + (root.tab === "themes" ? String(root.current?.wallpaper || "") : Wallpapers.pathOf(root.current)) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    // Decode only at preview resolution. A
                                    // 4K wallpaper would otherwise add tens
                                    // of MiB while this small card is open.
                                    sourceSize.width: Math.max(1, Math.ceil(width))
                                    sourceSize.height: Math.max(1, Math.ceil(height))
                                    asynchronous: true
                                    cache: false
                                }
                                Repeater {
                                    model: [-1, 1]
                                    Rectangle {
                                        required property int modelData
                                        readonly property var neighborItem: root.neighbor(modelData)
                                        visible: root.tab === "themes" && root.items.length > 1
                                        z: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: modelData < 0 ? Theme.spaceSm : parent.width - width - Theme.spaceSm
                                        width: Math.max(Theme.cellW * 5, parent.width * 0.13)
                                        height: parent.height * 0.62
                                        color: neighborItem?.background || Theme.bgDarker
                                        radius: Theme.radius
                                        border.width: Theme.borderWidth
                                        border.color: neighborItem?.accent || Theme.panelBorder
                                        opacity: 0.68
                                        scale: 0.94
                                        Behavior on opacity { NumberAnimation { duration: Theme.motionEffect } }
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: parent.border.width
                                            source: parent.visible ? "file://" + String(parent.neighborItem?.wallpaper || "") : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            sourceSize.width: Math.max(1, Math.ceil(width))
                                            sourceSize.height: Math.max(1, Math.ceil(height))
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Theme.alpha(Theme.bgDarker, 0.34)
                                            radius: parent.radius
                                        }
                                        Line {
                                            anchors.centerIn: parent
                                            text: parent.modelData < 0 ? "‹" : "›"
                                            color: Theme.fgBright
                                            font.pixelSize: Theme.fontDisplay
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.moveWrapped(parent.modelData)
                                        }
                                    }
                                }
                                Line {
                                    anchors.centerIn: parent
                                    visible: root.tab === "plugins"
                                    text: "󰏖"
                                    color: Theme.accent
                                    font.pixelSize: Theme.fontDisplay
                                }

                                // A lightweight live mockup communicates the
                                // theme better than a palette swatch. It uses
                                // the selected theme's own colors and default
                                // wallpaper, so imported themes get a preview
                                // without generating or shipping screenshots.
                                Rectangle {
                                    id: terminalPreview
                                    visible: root.tab === "themes" && !!root.current
                                    anchors.centerIn: parent
                                    width: parent.width * 0.72
                                    height: parent.height * 0.62
                                    color: root.current?.background || Theme.bgDarker
                                    opacity: 0.94
                                    radius: Math.max(2, Theme.radius * 0.72)
                                    border.width: Math.max(1, Theme.borderWidth)
                                    border.color: root.current?.accent || Theme.accent

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: Math.max(6, Theme.spaceMd)
                                        spacing: Math.max(2, Theme.spaceXs)

                                        Row {
                                            width: parent.width
                                            height: Theme.cellH
                                            spacing: Math.max(3, Theme.spaceXs)
                                            Repeater {
                                                model: [root.current?.red, root.current?.yellow, root.current?.green]
                                                Rectangle {
                                                    required property var modelData
                                                    width: Math.max(5, Theme.cellH * 0.38)
                                                    height: width
                                                    radius: width / 2
                                                    color: modelData || Theme.muted
                                                }
                                            }
                                            Item { width: Theme.spaceSm; height: 1 }
                                            Line {
                                                text: "nbshell — preview"
                                                color: root.current?.dimForeground || root.current?.foreground || Theme.fgDim
                                                font.pixelSize: Math.max(8, Theme.fontCaption)
                                            }
                                        }

                                        Line {
                                            text: "$ fastfetch"
                                            color: root.current?.accent || Theme.accent
                                            font.pixelSize: Math.max(8, Theme.fontCaption)
                                        }
                                        Line {
                                            width: parent.width
                                            text: "nbshell  ·  Umbriel"
                                            color: root.current?.foreground || Theme.fg
                                            font.pixelSize: Math.max(9, Theme.fontBody)
                                            elide: Text.ElideRight
                                        }
                                        Line {
                                            width: parent.width
                                            text: String(root.current?.name || "theme")
                                            color: root.current?.dimForeground || root.current?.foreground || Theme.fgDim
                                            font.pixelSize: Math.max(8, Theme.fontCaption)
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Line { width: parent.width; text: root.current ? root.label(root.current) : "No selection"; color: Theme.fg; font.pixelSize: Theme.fontTitle; elide: Text.ElideRight }
                            Line { width: parent.width; text: root.current ? root.detail(root.current) : ""; color: Theme.muted; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight }
                            Item { width: 1; height: 1 }
                            ControlButton {
                                width: parent.width
                                text: root.tab === "plugins" ? "MANAGE" : "APPLY"
                                enabled: !!root.current
                                onTriggered: root.activate(root.current)
                            }
                            ControlButton {
                                width: parent.width
                                text: root.tab === "plugins" ? "BROWSE PLUGIN STORE" : root.tab === "wallpapers" ? "OPEN VISUAL PICKER" : "OPEN THEME PICKER"
                                onTriggered: root.browse()
                            }
                        }
                    }
                }

                Line { width: parent.width; text: "↑↓ SELECT  ·  ENTER APPLY  ·  ESC CLOSE  ·  INSTALLING NEVER ACTIVATES PLUGINS"; color: Theme.muted; font.pixelSize: Theme.fontCaption; horizontalAlignment: Text.AlignRight }
            }
        }
    }
}
