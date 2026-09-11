import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common
import qs.Widgets
import "TrayPreferences.js" as Preferences

// Click opens the drawer; right-click or Menu opens per-app preferences.
Cell {
    id: root

    // Welches Symbol gerade sein Menue zeigt. Der Anker des Popouts wandert
    // mit, damit es unter dem richtigen Symbol steht.
    property var menuItem: null
    property Item menuAnchor: null

    readonly property var items: SystemTray.items?.values ?? []

    readonly property var preferences: Config.value("trayItems", ({}))
    readonly property var visibleItems: Preferences.visibleItems(items, preferences, expanded, Status.Passive)

    function setMode(item, mode) {
        Config.set("trayItems", Preferences.updated(preferences, item, mode));
    }

    function toggleDrawer() {
        menuPopout.closeImmediately();
        Config.set("trayExpanded", !expanded);
    }

    onVisibleItemsChanged: {
        // Repeater rebuilds can destroy the anchor even when the app remains.
        if (menuItem) {
            menuPopout.closeImmediately();
            menuItem = null;
            menuAnchor = null;
        }
    }

    readonly property bool expanded: Config.value("trayExpanded", false)
    readonly property real itemExtent: Theme.barIconSlot + Theme.barItemPadding * 2

    function isSymbolic(source) {
        // Preserve Quickshell's resolved URL, including fallback theme paths.
        // Only named symbolic icons opt into recoloring; app artwork stays intact.
        return String(source || "").split("?")[0].endsWith("-symbolic");
    }

    shown: items.length > 0
    onShownChanged: if (!shown) {
        manager.closeImmediately();
        menuPopout.closeImmediately();
    }
    custom: true

    Row {
        spacing: 0

        // Der Pfeil zeigt zugleich Aktion und Zustand, ohne einen Zaehler.
        InteractiveSurface {
            id: toggle
            width: root.itemExtent
            height: root.implicitHeight
            color: visualFocus ? Theme.barHover : "transparent"
            border.width: visualFocus ? Theme.borderWidth : 0
            border.color: Theme.focusBorder
            readonly property bool hovered: toggleHover.hovered
            HoverHandler { id: toggleHover }
            accessibleName: root.expanded ? "Collapse tray" : "Expand tray"
            accessibleDescription: "Right-click or press Menu to manage tray icons"
            onTriggered: root.toggleDrawer()
            Keys.onMenuPressed: manager.toggle()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                    manager.toggle();
                    event.accepted = true;
                }
            }
            Line {
                anchors.centerIn: parent
                text: root.expanded ? "<" : ">"
                color: Theme.textDim
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.RightButton)
                        manager.toggle();
                    else
                        toggle.activate();
                }
            }
        }

        Repeater {
            model: root.visibleItems

            Item {
                id: entry

                required property var modelData

                width: root.itemExtent
                height: root.implicitHeight

                Item {
                    id: icon

                    anchors.centerIn: parent
                    width: Theme.barIconHeight
                    height: width
                    readonly property bool symbolic: root.isSymbolic(entry.modelData.icon)

                    Image {
                        id: artwork
                        anchors.fill: parent
                        source: entry.modelData.icon
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                        visible: !icon.symbolic
                        layer.enabled: icon.symbolic
                    }

                    // Symbolic artwork contributes alpha only. Colorization
                    // preserves luminance and leaves dark source glyphs dim.
                    Rectangle {
                        id: symbolicFill
                        anchors.fill: artwork
                        color: root.shownColor
                        visible: false
                        layer.enabled: icon.symbolic
                    }
                    MultiEffect {
                        anchors.fill: artwork
                        source: symbolicFill
                        visible: icon.symbolic
                        maskEnabled: true
                        maskSource: artwork
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onClicked: mouseEvent => {
                        const item = entry.modelData;
                        if (mouseEvent.button === Qt.RightButton || item.onlyMenu) {
                            if (!item.hasMenu)
                                return;
                            // Dasselbe Symbol noch einmal schliesst das Menue.
                            if (menuPopout.visible && root.menuItem === item) {
                                menuPopout.close();
                                return;
                            }
                            root.menuItem = item;
                            root.menuAnchor = entry;
                            menuPopout.open();
                            return;
                        }
                        if (mouseEvent.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                            return;
                        }
                        item.activate();
                    }

                    onWheel: wheelEvent => entry.modelData.scroll(wheelEvent.angleDelta.y, false)
                }
            }
        }
    }

    Popout {
        id: manager
        anchorItem: toggle
        takesKeyboard: true
        contentComponent: Component {
            TraySettings {
                items: root.items
                preferences: root.preferences
                setMode: root.setMode
                availableWidth: Math.max(1, root.Screen.width - Theme.panelPadding * 4)
                availableHeight: Math.max(1, root.Screen.height - Theme.barHeight - Theme.panelPadding * 4)
            }
        }
    }

    // Ein Popout fuer alle Symbole: es haengt jeweils an dem, das zuletzt
    // angeklickt wurde.
    Popout {
        id: menuPopout
        // Reserve space before DBus replies; keep native geometry stable.
        minimumContentHeight: 6 * Theme.rowHeight
        maximumContentHeight: Math.max(1, root.Screen.height - Theme.barHeight - Theme.panelPadding * 4)

        anchorItem: root.menuAnchor ?? root
        takesKeyboard: true
        contentComponent: menuComponent
    }

    Component {
        id: menuComponent

        Column {
            id: content
            readonly property Item initialFocusItem: menu.initialFocusItem
            spacing: Theme.cellH * 0.3

            Line {
                width: menu.rowWidth
                elide: Text.ElideRight
                text: root.menuItem?.title || root.menuItem?.id || ""
                color: Theme.fgDim
            }

            MenuView {
                id: menu
                rowWidth: Math.min(32 * Theme.cellW, root.Screen.width - Theme.panelPadding * 4)
                handle: root.menuItem?.menu ?? null
                dismiss: () => {
                    menuPopout.close();
                }
            }
        }
    }
}
