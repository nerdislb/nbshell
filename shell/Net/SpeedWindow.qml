import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// Durchsatz messen -- als Fenster mit Balken statt als Zahlenzeile im Popout.
//
// Die Balken sind dieselben Bloecke wie ueberall in nbshell (`LevelBar`), nur
// laenger. Sie zeigen nicht "wie viel Prozent von 100", sondern wie viel vom
// bisher schnellsten Wert -- die Skala waechst mit. Eine feste Obergrenze waere
// an einem Ort falsch: 50 Mbit/s sind im Hotel viel und zu Hause wenig.
//
// `speedtest-cli` liefert seine drei Werte alle auf einmal, erst am Ende. Es
// gibt also nichts, was live steigen koennte -- statt einen Fortschritt zu
// erfinden, laeuft waehrenddessen ein Lauflicht durch den Balken. Man sieht
// dass es arbeitet, und wird nicht ueber den Stand belogen.
PanelWindow {
    id: root

    property var result: null
    property bool running: false

    // Die Skala. Bleibt zwischen zwei Messungen stehen, damit man vergleichen
    // kann, und waechst, wenn eine Messung darueber hinausgeht.
    property real scale: Config.value("speedScale", 100)

    function start() {
        if (root.running)
            return;
        root.running = true;
        root.result = null;
        proc.command = ["bash", Qt.resolvedUrl("../scripts/speedtest.sh").toString().replace("file://", "")];
        proc.running = true;
    }

    function close() {
        Runtime.speedOpen = false;
    }

    // Wie viel Prozent des Balkens. Ueber der Skala wird sie erweitert, damit
    // der Balken nie am Anschlag klebt und man den Unterschied noch sieht.
    function anteil(wert) {
        if (!wert || wert <= 0)
            return 0;
        return Math.max(2, Math.min(100, Math.round(100 * wert / root.scale)));
    }

    visible: Runtime.speedOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:speedtest"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.speedOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    onVisibleChanged: {
        if (visible) {
            focusItem.forceActiveFocus();
            root.start();
        }
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                root.running = false;
                try {
                    root.result = JSON.parse(text);
                } catch (e) {
                    root.result = ({
                            "ok": false,
                            "grund": "Antwort unlesbar"
                        });
                }
                if (root.result && root.result.ok) {
                    const groesster = Math.max(root.result.down, root.result.up);
                    if (groesster > root.scale) {
                        // Auf die naechste runde Zahl aufrunden -- eine Skala,
                        // die genau am Messwert endet, sieht aus wie ein
                        // Anschlag.
                        const neu = Math.ceil(groesster / 50) * 50;
                        root.scale = neu;
                        Config.set("speedScale", neu);
                    }
                }
            }
        }
    }

    // Lauflicht waehrend der Messung.
    property int tick: 0

    Timer {
        interval: 90
        repeat: true
        running: root.running
        onTriggered: root.tick++
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
        Keys.onPressed: event => {
            // Leertaste und Enter messen erneut -- das ist das Einzige, was man
            // in diesem Fenster tun will.
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.start();
                event.accepted = true;
            }
        }
    }

    PanelSurface {
        anchors.centerIn: parent

        width: inhalt.implicitWidth + Theme.cellW * 4
        height: inhalt.implicitHeight + Theme.cellH * 2

        accentBorder: false

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: inhalt

            anchors.centerIn: parent
            spacing: Theme.cellH * 0.5

            readonly property real rowWidth: Theme.cellW * 52

            // Ein Balken mit Beschriftung darueber und Wert dahinter.
            component Messwert: Column {
                id: messwert

                property string label: ""
                property real wert: 0
                property string einheit: "Mbit/s"
                property color fill: Theme.accent
                property bool laeuft: false

                spacing: 0

                Line {
                    text: messwert.label
                    color: Theme.fgDim
                }

                Row {
                    spacing: Theme.cellW

                    LevelBar {
                        cells: 34
                        // Waehrend der Messung wandert ein kurzer Block durch
                        // den Balken. `value` ist dabei keine Aussage ueber
                        // den Durchsatz -- es gibt noch keine.
                        value: messwert.laeuft ? ((root.tick * 3) % 100) : root.anteil(messwert.wert)
                        fillColor: messwert.laeuft ? Theme.muted : messwert.fill
                        interactive: false
                    }

                    Line {
                        width: Theme.cellW * 14
                        text: messwert.laeuft ? "measuring …" : (messwert.wert > 0 ? (messwert.wert.toFixed(1) + " " + messwert.einheit) : "—")
                        color: messwert.laeuft ? Theme.muted : Theme.fg
                    }
                }
            }

            PanelHead {
                rowWidth: inhalt.rowWidth
                icon: Icons.lan
                title: "Throughput"
                subtitle: (root.result && root.result.ok) ? String(root.result.server) : "Speedtest"
                badge: root.running ? "misst" : (root.result && root.result.ok ? (root.scale + " Mbit/s") : "")
            }

            Rule {
                rowWidth: inhalt.rowWidth
            }

            Messwert {
                label: "DOWNLOAD"
                laeuft: root.running
                wert: (root.result && root.result.ok) ? root.result.down : 0
                fill: Theme.green
            }

            Messwert {
                label: "UPLOAD"
                laeuft: root.running
                wert: (root.result && root.result.ok) ? root.result.up : 0
                fill: Theme.accent
            }

            Rule {
                rowWidth: inhalt.rowWidth
            }

            // Der Ping bekommt keinen Balken: bei ihm ist klein gut, und ein
            // Balken, der bei "gut" fast leer ist, liest sich falsch herum.
            //
            // Unplausible Werte werden verschwiegen statt gezeigt:
            // speedtest-cli meldet gegen manche Gegenstellen 1.800.000 ms.
            // Eine offensichtlich falsche Zahl ist schlechter als keine.
            Facts {
                rowWidth: inhalt.rowWidth
                pairs: [
                    {
                        "label": "Ping",
                        "value": (root.result && root.result.ok && root.result.ping > 0 && root.result.ping < 5000) ? (root.result.ping + " ms") : (root.running ? "…" : "—")
                    },
                    {
                        "label": "Skala",
                        "value": root.scale + " Mbit/s"
                    }
                ]
            }

            Line {
                width: inhalt.rowWidth
                visible: root.result !== null && root.result.ok !== true
                text: "  " + (root.result ? root.result.grund : "")
                color: Theme.red
                wrapMode: Text.WordWrap
            }

            Line {
                width: inhalt.rowWidth
                text: "Space runs again · Esc closes"
                color: Theme.muted
            }
        }
    }
}
