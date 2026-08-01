import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Hintergrundbild, ein Fenster je Bildschirm.
//
// Es haengt am Theme: jedes Omarchy-Theme bringt seine Bilder mit, und
// scripts/themes.sh sucht sie an den drei bekannten Stellen (siehe README).
// Wechselt das Theme, wechselt das Bild -- ueberblendet, nicht geschnitten.
//
// Standardmaessig AUS. DMS malt seinen eigenen Hintergrund auf dieselbe Ebene;
// solange beide laufen, wuerden sie sich abwechselnd ueberdecken. Einschalten
// mit `nbshell set wallpaper true`.
Variants {
    model: Config.wallpaperEnabled ? Quickshell.screens : []

    delegate: PanelWindow {
        id: win

        required property var modelData

        screen: modelData
        color: "transparent"

        WlrLayershell.namespace: "nbshell:wallpaper"
        WlrLayershell.layer: WlrLayershell.Background
        // Der Hintergrund nimmt keinen Platz weg und faengt keine Klicks.
        exclusionMode: ExclusionMode.Ignore

        anchors.left: true
        anchors.right: true
        anchors.top: true
        anchors.bottom: true

        mask: Region {}

        // Eine leere Flaeche in der Hintergrundfarbe liegt darunter: sie deckt
        // die Raender ab, solange ein Bild laedt oder gar keines da ist.
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
        }

        // Zwei Bildflaechen, die sich abwechseln. Beim Wechsel laedt die
        // verdeckte das neue Bild und wird eingeblendet -- so gibt es kein
        // Schwarzbild zwischendurch.
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

        onSourceChanged: {
            if (!source) {
                imageA.source = "";
                imageB.source = "";
                return;
            }
            const url = "file://" + source;
            // Erst laden, dann umblenden: das verdeckte Bild bekommt die neue
            // Quelle, und `showA` kippt erst, wenn sie steht.
            if (showA) {
                imageB.source = url;
            } else {
                imageA.source = url;
            }
        }

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
