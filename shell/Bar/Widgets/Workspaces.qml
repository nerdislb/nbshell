import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Arbeitsflaechen des Bildschirms, auf dem die Zelle steht.
//
// Eine Zelle mit eigenem Inhalt statt Text: die einzelnen Flaechen muessen
// anklickbar sein und eigene Farben haben. Mausrad blaettert durch,
// Rechtsklick wechselt den Stil.
//
// Vier Stile, aus dem Vorgaenger workspace-pills uebernommen:
//
//   numbers   die Nummern, unterstrichen ist die aktive
//   dots      dicker Punkt aktiv, kleiner Punkt inaktiv
//   pacman    dieselben Punkte, auf dem aktiven sitzt Pac-Man
//   invader   dieselben Punkte, auf dem aktiven sitzt ein Space Invader
//
// Die beiden Figuren arbeiten gleich: eine Reihe Punkte, der aktive ist
// verdeckt -- da steht die Figur. Unterschiedlich ist nur die Zeichnung.
Cell {
    id: root

    property string output: ""

    readonly property var list: Niri.workspacesForOutput(output)
    readonly property int activeIndex: list.findIndex(w => w.is_active)

    readonly property string style: Config.workspaceStyle
    readonly property bool pacmanMode: style === "pacman"
    readonly property bool invaderMode: style === "invader"
    readonly property bool figureMode: pacmanMode || invaderMode

    // Masse auf dem Zeichenraster, nicht in festen Pixeln: wer die
    // Schriftgroesse aendert, aendert die Punkte mit.
    readonly property real dotBig: Math.max(4, Math.round(Theme.cellH * 0.42))
    readonly property real dotSmall: Math.max(2, Math.round(Theme.cellH * 0.2))
    readonly property real stride: Math.round(Theme.cellW * 1.6)
    readonly property real figureSize: Math.round(Theme.cellH * 0.8)

    // Pac-Man ist gelb und der Invader gruen, sonst sind es keine. Wer die
    // Leiste lieber einfarbig haette, nimmt `workspaceClassic: false` -- dann
    // kommen beide aus der Palette des Themes.
    readonly property color figureColor: Config.workspaceClassic ? (invaderMode ? "#5AF75A" : "#FFCC00") : (invaderMode ? Theme.green : Theme.yellow)

    // Der klassische Invader, 11x8 Bloecke, in seinen zwei Bildern.
    readonly property var invaderFrames: [["..#.....#..", "...#...#...", "..#######..", ".##.###.##.", "###########", "#.#######.#", "#.#.....#.#", "...##.##..."], ["..#.....#..", "#..#...#..#", "#.#######.#", "###.###.###", "###########", ".#########.", "..#.....#..", ".#.......#."]]

    function colorFor(w) {
        if (w.is_urgent)
            return Theme.red;
        return w.is_active ? Theme.barAccent : Theme.barFgDim;
    }

    custom: true
    interactive: true

    onWheel: delta => {
        const items = root.list;
        const current = root.activeIndex;
        if (current < 0)
            return;
        const next = delta > 0 ? current - 1 : current + 1;
        if (next >= 0 && next < items.length)
            Niri.focusWorkspace(items[next].idx);
    }

    // Reihum durch die Stile -- so, wie es der Vorgaenger auch machte. Es
    // steht sonst nur im Optionsmenue, und zum Ausprobieren will man nicht
    // jedes Mal dorthin.
    onRightClicked: {
        const order = ["numbers", "dots", "pacman", "invader"];
        Config.set("workspaceStyle", order[(order.indexOf(root.style) + 1) % order.length]);
    }

    // Ein Loader, damit immer nur EIN Stil da ist: unsichtbare Kinder zaehlen
    // in `childrenRect` mit, und genau daraus rechnet die Zelle ihre Breite.
    // Zwei Stile nebeneinander machten die Zelle doppelt so breit.
    Loader {
        sourceComponent: root.style === "numbers" ? numbers : strip
    }

    // ── Nummern ───────────────────────────────────────────────────────────

    Component {
        id: numbers

        Row {
            spacing: Theme.cellW

            Repeater {
                model: root.list

                Line {
                    required property var modelData

                    text: modelData.name ? modelData.name : String(modelData.idx)
                    color: root.colorFor(modelData)
                    font.underline: modelData.is_active

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.cellW / 2
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Niri.focusWorkspace(parent.modelData.idx)
                    }
                }
            }
        }
    }

    // ── Punkte, mit oder ohne Figur ───────────────────────────────────────

    Component {
        id: strip

        Item {
            id: lane

            readonly property int count: root.list.length

            // Die Figur ist breiter als ein Punkt und wuerde an den Enden
            // sonst abgeschnitten.
            readonly property real pad: root.figureMode ? Math.max(0, (root.figureSize - root.dotBig) / 2) : 0

            function centerAt(i) {
                return pad + i * root.stride + root.dotBig / 2;
            }

            implicitWidth: count > 0 ? (count - 1) * root.stride + root.dotBig + 2 * pad : 0
            implicitHeight: root.figureMode ? Math.max(root.dotBig, root.figureSize) : root.dotBig
            width: implicitWidth
            height: implicitHeight

            // Blickrichtung aus der Bewegung: nach einem Sprung nach links
            // dreht Pac-Man sich um. Der letzte Index muss dafuer gemerkt
            // werden -- aus dem aktuellen Zustand allein ist sie nicht
            // ablesbar.
            property int lastIndex: root.activeIndex

            Connections {
                target: root

                function onActiveIndexChanged() {
                    const now = root.activeIndex;
                    if (now >= 0 && lane.lastIndex >= 0 && now !== lane.lastIndex)
                        figure.facingBack = now < lane.lastIndex;
                    lane.lastIndex = now;
                }
            }

            Repeater {
                model: root.list

                Rectangle {
                    id: dot

                    required property var modelData
                    required property int index

                    readonly property bool act: modelData.is_active

                    width: act && !root.figureMode ? root.dotBig : root.dotSmall
                    height: width
                    radius: width / 2

                    x: lane.centerAt(index) - width / 2
                    y: (lane.height - height) / 2

                    // Unter der Figur ist der Punkt gefressen.
                    opacity: root.figureMode && act ? 0 : 1
                    color: root.colorFor(modelData)

                    Behavior on width {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    MouseArea {
                        // Der Punkt selbst ist ein kleines Ziel; die Flaeche
                        // greift bis zur Mitte der Luecke daneben.
                        //
                        // BEWUSST ohne `hoverEnabled`: eine MouseArea, die das
                        // Ueberfahren annimmt, nimmt es der Zelle darunter weg
                        // -- und die braucht es fuer ihren eigenen Zustand.
                        anchors.centerIn: parent
                        width: root.stride
                        height: lane.height
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Niri.focusWorkspace(dot.modelData.idx)
                    }
                }
            }

            Canvas {
                id: figure

                width: root.figureSize
                height: root.figureSize
                visible: root.figureMode && root.activeIndex >= 0
                z: 1

                x: lane.centerAt(Math.max(0, root.activeIndex)) - width / 2
                y: (lane.height - height) / 2

                // Oeffnungswinkel des Munds, 0 = zu.
                property real mouth: 0.35
                property bool facingBack: false
                // Welches der beiden Invader-Bilder gerade dran ist.
                property int invaderFrame: 0

                Behavior on x {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                onMouthChanged: requestPaint()
                onFacingBackChanged: requestPaint()
                onWidthChanged: requestPaint()
                onInvaderFrameChanged: requestPaint()

                Connections {
                    target: root

                    function onStyleChanged() {
                        figure.requestPaint();
                    }

                    function onFigureColorChanged() {
                        figure.requestPaint();
                    }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = root.figureColor;

                    if (root.invaderMode) {
                        // Sprite aus Bloecken: jede Zeile ein String, '#' ist
                        // ein gesetzter Block. Die Kantenlaenge ergibt sich aus
                        // der kleineren Achse, damit nichts ueber den Rand
                        // laeuft.
                        const rows = root.invaderFrames[invaderFrame];
                        const cols = rows[0].length;
                        const cell = Math.max(1, Math.floor(Math.min(width / cols, height / rows.length)));
                        const ox = (width - cell * cols) / 2;
                        const oy = (height - cell * rows.length) / 2;
                        for (let r = 0; r < rows.length; r++) {
                            for (let c = 0; c < cols; c++) {
                                if (rows[r][c] === "#")
                                    ctx.fillRect(ox + c * cell, oy + r * cell, cell, cell);
                            }
                        }
                        return;
                    }

                    const r = width / 2;
                    const a = mouth * Math.PI / 2;
                    ctx.beginPath();
                    ctx.moveTo(r, r);
                    // Der Vollkreis abzueglich des Keils, der den Mund bildet.
                    if (facingBack)
                        ctx.arc(r, r, r, Math.PI + a, Math.PI - a, false);
                    else
                        ctx.arc(r, r, r, a, -a, false);
                    ctx.closePath();
                    ctx.fill();
                }

                // Der Invader wackelt nicht, er schaltet zwischen zwei Bildern
                // um -- so lief es im Original auch.
                Timer {
                    running: figure.visible && root.invaderMode
                    interval: 420
                    repeat: true
                    onTriggered: figure.invaderFrame = 1 - figure.invaderFrame
                }

                SequentialAnimation on mouth {
                    running: figure.visible && root.pacmanMode
                    loops: Animation.Infinite

                    NumberAnimation {
                        from: 0.05
                        to: 0.5
                        duration: 220
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        from: 0.5
                        to: 0.05
                        duration: 220
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }
}
