import QtQuick

import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Wallpaper surface, one window per output. Umbriel owns overview styling.
//
// Das Bild haengt am Theme: jedes Omarchy-Theme bringt seine mit, und
// scripts/themes.sh sucht sie an den drei bekannten Stellen (siehe README).
// Wechselt das Theme, wechselt das Bild -- ueberblendet, nicht geschnitten.
//
// Enabled by default; the user can still disable it with `nbshell wallpaper off`.

Scope {
    id: root

    // ── Der Hintergrund, den man immer sieht ──────────────────────────────

    Variants {
        model: Config.wallpaperEnabled ? Quickshell.screens : []

        delegate: PanelWindow {
            id: win

            required property var modelData

            screen: modelData
            color: "transparent"

            WlrLayershell.namespace: "nbshell:wallpaper"
            WlrLayershell.layer: WlrLayershell.Background
            exclusionMode: ExclusionMode.Ignore

            anchors.left: true
            anchors.right: true
            anchors.top: true
            anchors.bottom: true

            mask: Region { item: wallpaperInput }

            // Deckt die Raender ab, solange ein Bild laedt oder keines da ist.
            Rectangle {
                anchors.fill: parent
                color: Theme.bg
            }

            // Zwei Bildflaechen, die sich abwechseln: die verdeckte laedt das
            // neue Bild und wird erst eingeblendet, wenn es steht -- sonst
            // blitzt beim Wechsel Schwarz durch.
            Image {
                id: imageA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: Math.max(1, Math.ceil(win.width * win.screen.devicePixelRatio))
                sourceSize.height: Math.max(1, Math.ceil(win.height * win.screen.devicePixelRatio))
                visible: opacity > 0
                opacity: win.showA ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motionEffectsSlow
                    }
                }
            }

            Image {
                id: imageB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: Math.max(1, Math.ceil(win.width * win.screen.devicePixelRatio))
                sourceSize.height: Math.max(1, Math.ceil(win.height * win.screen.devicePixelRatio))
                visible: opacity > 0
                opacity: win.showA ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.motionEffectsSlow
                    }
                }
            }

            property bool showA: true
            readonly property string source: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")

            // Keep both textures only for the duration of the cross-fade.
            // A decoded screen-sized wallpaper can occupy tens of MiB; leaving
            // the hidden previous image loaded doubled that cost forever.
            onShowAChanged: releaseHidden.restart()

            Timer {
                id: releaseHidden
                interval: 500
                onTriggered: {
                    if (win.showA)
                        imageB.source = "";
                    else
                        imageA.source = "";
                }
            }

            function stage(path) {
                if (!path) {
                    imageA.source = "";
                    imageB.source = "";
                    return;
                }

                const url = "file://" + path;
                const target = showA ? imageB : imageA;

                // Beim Rueckwechsel liegt das gewuenschte Bild oft noch
                // fertig geladen in der gerade verdeckten Ebene. Dieselbe URL
                // erneut zuzuweisen erzeugt kein StatusChanged/Ready-Signal;
                // dadurch blieb die sichtbare andere Ebene (z. B. Harbor)
                // endlos oben. Ist das Ziel schon bereit, direkt ueberblenden.
                if (String(target.source) === url && target.status === Image.Ready) {
                    showA = target === imageA;
                    return;
                }

                target.source = url;
            }

            onSourceChanged: win.stage(source)

            Connections {
                target: imageA
                function onStatusChanged() {
                    if (imageA.status === Image.Ready && !win.showA && imageA.source != "")
                        win.showA = true;
                }
            }

            Connections {
                target: imageB
                function onStatusChanged() {
                    if (imageB.status === Image.Ready && win.showA && imageB.source != "")
                        win.showA = false;
                }
            }

            // Empty desktop gestures stay available regardless of which
            // optional modules are present in the bar. Windows and shell
            // overlays remain above this background layer and keep priority.
            Item {
                id: wallpaperInput
                anchors.fill: parent

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onDoubleTapped: Runtime.wallpaperOpen = true
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onDoubleTapped: Runtime.themePickerOpen = true
                }
            }

            Component.onCompleted: {
                if (win.source)
                    imageA.source = "file://" + win.source;
            }
        }
    }

}
