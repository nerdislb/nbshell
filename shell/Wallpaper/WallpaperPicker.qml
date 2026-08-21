import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

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

    // Nur die ERSTE Liste nach dem Oeffnen bestimmt, wo der Rahmen steht.
    // Danach gehoert die Auswahl den Pfeiltasten -- sonst zieht jede neue
    // Liste sie wieder auf den Ausgangswert.
    property bool jumpPending: false

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
        // Kein positionViewAtIndex mehr: das setzt `contentX` hart und
        // ueberfaehrt damit genau die Bewegung, die man sehen soll. Der
        // Streifen folgt jetzt ueber `currentIndex` und den Vorzugsbereich.
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
        jumpPending = true;
        Wallpapers.refresh();
        keys.forceActiveFocus();
    }

    // Nach dem Laden auf das aktuelle Bild springen.
    Connections {
        target: Wallpapers

        function onListChanged() {
            if (!root.jumpPending)
                return;
            root.jumpPending = false;
            const i = root.list.indexOf(root.previous);
            root.selected = i >= 0 ? i : 0;
            // Beim Oeffnen ohne Bewegung dorthin -- eine Animation aus dem
            // Nichts sieht aus, als haette man schon etwas verstellt.
            strip.positionViewAtIndex(root.selected, ListView.Center);
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

        PanelSurface {
            id: box
            accentBorder: true

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.cellH * 3

            width: Math.min(parent.width - Theme.cellW * 8, Theme.cellW * 130)
            height: strip.height + header.height + Theme.cellH * 2

            MouseArea {
                anchors.fill: parent
            }

            Line {
                id: header

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.cellW
                height: Theme.cellH * 1.6
                text: {
                    if (Wallpapers.loading)
                        return "WALLPAPER  ·  searching …";
                    if (root.list.length === 0)
                        return "WALLPAPER  ·  no images for " + Config.theme;
                    return "WALLPAPER  ·  " + Config.theme + "  ·  " + (root.selected + 1) + "/" + root.list.length + "  ·  " + Wallpapers.nameOf(root.list[root.selected] ?? "");
                }
                color: Theme.fgDim
            }

            ListView {
                id: strip

                readonly property real tileWidth: strip.height * 1.6

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

                // Der Streifen gleitet, statt zu springen. `ApplyRange` haelt
                // das aktuelle Bild in der Mitte, laesst am Anfang und Ende
                // aber los -- sonst haengt der Streifen beim ersten Bild in
                // der Mitte fest und die Haelfte davor ist leer.
                currentIndex: root.selected
                highlightMoveDuration: 220
                highlightMoveVelocity: -1
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: (strip.width - strip.tileWidth) / 2
                preferredHighlightEnd: (strip.width + strip.tileWidth) / 2

                delegate: Item {
                    id: tile

                    required property var modelData
                    required property int index

                    readonly property bool current: tile.index === root.selected

                    // Die uebrigen sind kleiner UND blasser. Ein staerkerer
                    // Rahmen allein reicht auf einem Streifen aus Fotos nicht
                    // -- er verschwindet zwischen den Bildinhalten.
                    //
                    // NICHT readonly: ein `Behavior` schreibt die Property,
                    // waehrend er sie animiert, und scheitert an einer
                    // schreibgeschuetzten ("is a read-only property").
                    property real inset: tile.current ? 0 : Theme.cellH * 0.7

                    width: strip.tileWidth
                    height: strip.height

                    Behavior on inset {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: tile.inset

                        color: "transparent"
                        border.width: tile.current ? Math.max(2, Theme.borderWidth * 2) : Theme.borderWidth
                        border.color: tile.current ? Theme.focusBorder : Theme.panelBorder
                        radius: Theme.radius
                        opacity: tile.current ? 1 : 0.45

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 180
                            }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: parent.border.width
                            source: "file://" + tile.modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            // Nur so gross laden, wie es angezeigt wird --
                            // sonst liegen 20 Vollbilder im Speicher.
                            sourceSize.width: Math.round(strip.tileWidth)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.preview(tile.index);
                            root.close();
                        }
                    }
                }
            }

            Line {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.cellW
                text: "←→ browse · Enter apply · r theme image · Esc back"
                color: Theme.muted
            }
        }
    }
}
