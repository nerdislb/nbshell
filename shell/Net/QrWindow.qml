import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// Das WLAN als QR-Code -- zum Abscannen mit dem Telefon.
//
// Ein eigenes Fenster und kein Popout, aus einem sehr praktischen Grund: ein
// Popout klappt zu, sobald die Maus es verlaesst. Genau das tut man aber, wenn
// man zum Telefon greift.
//
// Gezeichnet wird die Modulmatrix als schwarze Quadrate auf WEISS. Der erste
// Versuch malte den Code aus Halbblockzeichen in den Farben des Themes -- das
// sah zur Shell passend aus und war unlesbar:
//
//   * hell auf dunkel ist die Umkehrung dessen, was ein QR-Code sein soll,
//     und viele Kameras lesen sie nicht;
//   * die Ruhezone war ein Modul breit statt vier;
//   * der gestauchte Zeilenabstand verzerrte die Module.
//
// Deshalb hier: eine weisse Karte, schwarze Quadrate, Ruhezone aus dem
// Generator. Das ist die eine Stelle in nbshell, an der das Theme nichts zu
// sagen hat -- ein Code, den niemand scannen kann, ist kein Code.
PanelWindow {
    id: root

    // NICHT `data` nennen: das ist in QML die Standard-Kindliste jedes
    // QtObject. Eine eigene Property dieses Namens verdeckt sie -- die
    // Kinder des Fensters landen dann in einer Variablen statt in der Szene,
    // und das Fenster liegt an, zeigt aber nichts. Genau so passiert.
    property var qr: null
    property bool loading: false

    readonly property var rows: (root.qr && root.qr.ok) ? root.qr.rows : []
    readonly property int size: (root.qr && root.qr.ok) ? root.qr.size : 0

    // So gross, dass eine Handykamera aus einer Armlaenge sicher trifft: bei
    // 37 Modulen sind das gut 400 px Kantenlaenge. Kleiner geht auch, aber
    // dann muss man naeher heran, und der Sinn der Sache ist, das Telefon
    // einmal kurz hochzuhalten.
    readonly property int modul: Math.max(6, Math.round(Theme.cellH * 0.8))

    function load() {
        root.loading = true;
        proc.command = ["bash", Qt.resolvedUrl("../scripts/wifi-qr.sh").toString().replace("file://", "")];
        proc.running = true;
    }

    function close() {
        Runtime.qrOpen = false;
    }

    visible: Runtime.qrOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:wifi-qr"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.qrOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    // Beim Oeffnen frisch holen: das Netz kann ein anderes sein als beim
    // letzten Mal, und ein alter Code fuehrt wortlos ins falsche Netz.
    onVisibleChanged: {
        if (visible) {
            root.qr = null;
            root.load();
            focusItem.forceActiveFocus();
        }
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    root.qr = JSON.parse(text);
                } catch (e) {
                    root.qr = ({
                            "ok": false,
                            "grund": "Antwort unlesbar"
                        });
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Item {
        id: focusItem

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.close()
    }

    Rectangle {
        anchors.centerIn: parent

        width: card.implicitWidth + Theme.cellW * 4
        height: card.implicitHeight + Theme.cellH * 2

        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.accent

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: card

            anchors.centerIn: parent
            spacing: Theme.cellH * 0.6

            PanelHead {
                rowWidth: Math.max(qrCard.width, Theme.cellW * 30)
                icon: Icons.wifi
                title: (root.qr && root.qr.ok) ? String(root.qr.ssid) : "WI-FI"
                subtitle: "scan to connect"
                badge: root.loading ? "…" : ""
            }

            // Die weisse Karte. Der Rand gehoert dazu: die Ruhezone steckt
            // zwar schon in der Matrix, aber sie muss auch WEISS sein.
            Rectangle {
                id: qrCard

                width: Math.max(root.size * root.modul, Theme.cellW * 30)
                height: root.size * root.modul
                visible: root.size > 0
                color: "white"

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Repeater {
                        model: root.rows

                        Row {
                            id: zeile

                            required property var modelData

                            spacing: 0

                            Repeater {
                                model: zeile.modelData.length

                                Rectangle {
                                    required property int index

                                    width: root.modul
                                    height: root.modul
                                    // Kein `radius`, kein Rand, keine Kante:
                                    // ein Modul ist ein Quadrat, sonst
                                    // verschluckt der Weichzeichner der Kamera
                                    // die feinen Uebergaenge.
                                    color: zeile.modelData.charAt(index) === "#" ? "black" : "white"
                                }
                            }
                        }
                    }
                }
            }

            Line {
                width: qrCard.width
                visible: root.qr !== null && root.qr.ok !== true
                text: root.loading ? "…" : ("  " + (root.qr ? root.qr.grund : ""))
                color: Theme.muted
                wrapMode: Text.WordWrap
            }

            Line {
                width: qrCard.width
                visible: root.qr !== null && root.qr.ok === true && String(root.qr.note) !== ""
                text: root.qr ? String(root.qr.note) : ""
                color: Theme.yellow
                wrapMode: Text.WordWrap
            }

            Line {
                width: qrCard.width
                text: "Esc closes"
                color: Theme.muted
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
