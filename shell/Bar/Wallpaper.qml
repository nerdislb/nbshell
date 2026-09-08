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
            readonly property string source: DynamicWallpaper.stillPath

            // Keep both textures only for the duration of the cross-fade.
            // A decoded screen-sized wallpaper can occupy tens of MiB; leaving
            // the hidden previous image loaded doubled that cost forever.
            onShowAChanged: releaseHidden.restart()

            Timer {
                id: releaseHidden
                interval: Theme.motionEffectsSlow + 50
                onTriggered: {
                    if (win.showA)
                        imageB.source = "";
                    else
                        imageA.source = "";
                }
            }

            function stage(path) {
                releaseHidden.stop();
                if (!path) {
                    imageA.source = "";
                    imageB.source = "";
                    return;
                }

                const url = DynamicWallpaper.url(path);
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

            function imageFailed(image) {
                const fallbackUrl = DynamicWallpaper.url(DynamicWallpaper.fallback);
                if (image.source != fallbackUrl && fallbackUrl) {
                    DynamicWallpaper.error = "Image unavailable; using current theme wallpaper.";
                    image.source = fallbackUrl;
                }
            }

            onSourceChanged: win.stage(source)

            Connections {
                target: imageA
                function onStatusChanged() {
                    if (imageA.status === Image.Error) win.imageFailed(imageA);
                    if (imageA.status === Image.Ready && !win.showA && imageA.source != "")
                        win.showA = true;
                }
            }

            Connections {
                target: imageB
                function onStatusChanged() {
                    if (imageB.status === Image.Error) win.imageFailed(imageB);
                    if (imageB.status === Image.Ready && win.showA && imageB.source != "")
                        win.showA = false;
                }
            }

            // Destroying the loader releases the decoder as well as its output.
            // Restart only after a short quiet period when a workspace clears.
            readonly property bool mayPlay: DynamicWallpaper.videoEligible
                && DynamicWallpaper.clearDesktop(win.screen.name)
            property bool playReady: false
            property string failedVideo: ""
            onMayPlayChanged: {
                playReady = false;
                if (mayPlay) resumeVideo.restart();
                else resumeVideo.stop();
            }
            Timer {
                id: resumeVideo
                interval: 750 // Debounce workspace/window changes, not a visual animation.
                running: win.mayPlay
                onTriggered: win.playReady = true
            }
            Connections {
                target: DynamicWallpaper
                function onVideoPathChanged() { win.failedVideo = ""; }
                function onSettingsChanged() { win.failedVideo = ""; }
            }
            Loader {
                id: video
                anchors.fill: parent
                active: win.mayPlay && win.playReady && win.failedVideo !== DynamicWallpaper.videoPath
                source: "../Wallpaper/VideoWallpaper.qml"
                onLoaded: item.source = Qt.binding(() => DynamicWallpaper.url(DynamicWallpaper.videoPath))
                onStatusChanged: if (status === Loader.Error) DynamicWallpaper.error = "Video player unavailable; using still image."
            }
            Connections {
                target: video.item
                function onFailed(message) {
                    win.failedVideo = DynamicWallpaper.videoPath;
                    DynamicWallpaper.error = "Video unavailable; using still image. " + message;
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
                    imageA.source = DynamicWallpaper.url(win.source);
            }
        }
    }

}
