import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Wallpaper-Karussell -- die Bilder des aktuellen Themes als Streifen.
//
// Vorbild ist das eigene `themeWallpaper` aus omarchy2dms: gross genug, um zu
// erkennen, was man waehlt, Pfeiltasten zum Blaettern, Enter uebernimmt, Esc
// stellt den vorherigen Stand wieder her.
//
// Beim Blaettern wird das Bild SOFORT gesetzt -- man sieht es also in voller
// Groesse hinter dem Streifen, statt aus einem Vorschaubild raten zu muessen.
// Esc nimmt es zurueck.
PanelWindow {
    id: root

    property int selected: 0
    property string previous: ""

    readonly property var list: Wallpapers.list

    visible: Runtime.wallpaperOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:wallpaperpicker"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.wallpaperOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.wallpaperOpen = false;
    }

    function preview(i) {
        if (i < 0 || i >= list.length)
            return;
        selected = i;
        Wallpapers.apply(list[i]);
        strip.positionViewAtIndex(i, ListView.Contain);
    }

    function cancel() {
        // Zurueck auf den Stand von vorher, auch wenn er leer war.
        Config.set("wallpaperOverride", previous);
        close();
    }

    onVisibleChanged: {
        if (!visible)
            return;
        previous = Config.value("wallpaperOverride", "");
        Wallpapers.refresh();
        keys.forceActiveFocus();
    }

    // Nach dem Laden auf das aktuelle Bild springen.
    Connections {
        target: Wallpapers

        function onListChanged() {
            const i = root.list.indexOf(root.previous);
            root.selected = i >= 0 ? i : 0;
            strip.positionViewAtIndex(root.selected, ListView.Contain);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.cancel()
        Keys.onLeftPressed: root.preview(root.selected - 1)
        Keys.onRightPressed: root.preview(root.selected + 1)
        Keys.onReturnPressed: root.close()
        Keys.onEnterPressed: root.close()
        Keys.onPressed: event => {
            // `r` zurueck auf das Bild, das das Theme selbst mitbringt.
            if (event.key === Qt.Key_R) {
                Wallpapers.reset();
                root.close();
                event.accepted = true;
            }
        }

        Rectangle {
            id: box

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.cellH * 3

            width: Math.min(parent.width - Theme.cellW * 8, Theme.cellW * 130)
            height: strip.height + header.height + Theme.cellH * 2

            color: Theme.alpha(Theme.bg, 0.92)
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            MouseArea {
                anchors.fill: parent
            }

            Text {
                id: header

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.cellW
                height: Theme.cellH * 1.6
                text: {
                    if (Wallpapers.loading)
                        return "HINTERGRUND  ·  suche …";
                    if (root.list.length === 0)
                        return "HINTERGRUND  ·  keine Bilder fuer " + Config.theme;
                    return "HINTERGRUND  ·  " + Config.theme + "  ·  " + (root.selected + 1) + "/" + root.list.length + "  ·  " + Wallpapers.nameOf(root.list[root.selected] ?? "");
                }
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            ListView {
                id: strip

                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.cellW

                height: Theme.cellH * 9
                orientation: ListView.Horizontal
                spacing: Theme.cellW
                clip: true
                model: root.list
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool current: index === root.selected

                    width: strip.height * 1.6
                    height: strip.height
                    color: "transparent"
                    border.width: current ? Math.max(2, Theme.borderWidth * 2) : Theme.borderWidth
                    border.color: current ? Theme.accent : Theme.muted

                    Image {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        source: "file://" + parent.modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        // Nur so gross laden, wie es angezeigt wird -- sonst
                        // liegen 20 Vollbilder im Speicher.
                        sourceSize.width: Math.round(strip.height * 1.6)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.preview(parent.index);
                            root.close();
                        }
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.cellW
                text: "←→ blaettern · Enter uebernehmen · r Themebild · Esc zurueck"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
