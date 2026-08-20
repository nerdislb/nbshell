import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Hintergrundbild, ein Fenster je Bildschirm -- und daneben eine zweite,
// weichgezeichnete Flaeche fuer niris Uebersicht.
//
// Das Bild haengt am Theme: jedes Omarchy-Theme bringt seine mit, und
// scripts/themes.sh sucht sie an den drei bekannten Stellen (siehe README).
// Wechselt das Theme, wechselt das Bild -- ueberblendet, nicht geschnitten.
//
// Standardmaessig AUS. Wer DMS daneben laufen laesst, haette sonst zwei
// Hintergruende auf derselben Ebene. Einschalten mit `nbshell wallpaper on`.
//
// **Die Unschaerfe in der Uebersicht kann niri nicht selbst.** Es zeigt dort
// nur, was auf einer Hintergrundflaeche liegt, die als
//
//     layer-rule { match namespace="nbshell:wallpaper-blur"
//                  place-within-backdrop true }
//
// markiert ist (steht in nbshell-takeover.kdl). Deshalb dieselbe Loesung wie in
// DMS: eine fertig verwischte Kopie bereithalten. Sie liegt hinter der scharfen
// und ist im Alltag nie zu sehen -- erst die Uebersicht holt sie hervor.
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

            mask: Region {}

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
                visible: opacity > 0
                opacity: win.showA ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                    }
                }
            }

            Image {
                id: imageB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: opacity > 0
                opacity: win.showA ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
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

            Component.onCompleted: {
                if (win.source)
                    imageA.source = "file://" + win.source;
            }
        }
    }

    // ── Die verwischte Kopie fuer die Uebersicht ──────────────────────────

    Variants {
        model: (Config.wallpaperEnabled && Config.wallpaperBlur) ? Quickshell.screens : []

        delegate: PanelWindow {
            id: blurWin

            required property var modelData

            readonly property string source: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")

            screen: modelData
            color: Theme.bg

            WlrLayershell.namespace: "nbshell:wallpaper-blur"
            WlrLayershell.layer: WlrLayershell.Background
            exclusionMode: ExclusionMode.Ignore

            anchors.left: true
            anchors.right: true
            anchors.top: true
            anchors.bottom: true

            mask: Region {}

            Image {
                id: blurSource

                anchors.fill: parent
                source: blurWin.source ? "file://" + blurWin.source : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                // Nur die Vorlage fuer den Effekt -- selbst gezeichnet wird sie
                // nicht.
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: blurSource
                blurEnabled: true
                blur: 1.0
                blurMax: Config.wallpaperBlurAmount
                // Ohne das waechst die Flaeche um den Weichzeichnerrand und
                // sitzt nicht mehr passgenau auf dem Bildschirm.
                autoPaddingEnabled: false
            }
        }
    }
}
