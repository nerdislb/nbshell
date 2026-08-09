import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services

// Anwendungsstarter und Befehlspalette in einem.
//
// Ein Vollbildfenster auf der obersten Ebene, das die Tastatur exklusiv
// bekommt, solange es offen ist -- anders liesse sich nicht tippen, waehrend
// darunter ein Fenster den Fokus haelt. Sichtbar ist davon nur der Kasten in
// der Mitte; die restliche Flaeche ist durchsichtig und schliesst beim Klick.
//
// Es gibt es nur einmal, nicht je Bildschirm: ein zweiter Starter auf dem
// zweiten Monitor waere ein zweites Eingabefeld mit eigenem Zustand.
//
// Gesucht wird in beidem gleichzeitig: Anwendungen UND alles, was die Shell
// selbst kann (siehe Services/Commands.qml). Ein fuehrendes ">" schraenkt auf
// die Befehle ein, ein "!" auf die Anwendungen. Sortiert wird nach Punkten,
// nicht nach Herkunft -- wer "gruv" tippt, will das Theme, wer "fire" tippt,
// den Browser, und keiner von beiden will erst durch die andere Liste.
PanelWindow {
    id: root

    // Anwendungen tragen ihren Namen im Namen; Befehle bekommen einen kleinen
    // Abschlag, damit bei gleichem Treffer die Anwendung vorn steht. Sie ist
    // das, wofuer der Starter urspruenglich da war.
    readonly property real commandBias: 0.9

    readonly property string mode: {
        const t = input.text;
        if (t.startsWith(">"))
            return "cmd";
        if (t.startsWith("!"))
            return "app";
        return "beides";
    }

    readonly property string query: root.mode === "beides" ? input.text : input.text.substring(1).trim()

    readonly property var results: {
        const q = root.query;
        if (root.mode === "cmd")
            return Commands.rank(q).map(x => x.entry);
        if (root.mode === "app")
            return Apps.rank(q).map(x => x.entry);

        const apps = Apps.rank(q);
        const cmds = Commands.rank(q);

        // Ohne Eingabe gibt es nichts zu vergleichen -- dann stehen die
        // Anwendungen nach Haeufigkeit oben und die Befehle darunter.
        if (!q)
            return apps.map(x => x.entry).concat(cmds.map(x => x.entry));

        const merged = apps.concat(cmds.map(x => ({
                    "entry": x.entry,
                    "points": x.points * root.commandBias
                })));
        merged.sort((a, b) => b.points - a.points || a.entry.name.localeCompare(b.entry.name));
        return merged.map(x => x.entry);
    }

    // Wie DMS' Spotlight: die Liste bleibt so lang, wie Platz ist, und der
    // Kasten waechst nicht bei jedem Tastendruck.
    property int selected: 0

    // Was sich nicht zurueckdrehen laesst (Ausschalten, Abmelden), verlangt
    // ein zweites Enter. In einer Suchpalette liegt sonst der Feierabend einen
    // Tippfehler entfernt.
    property var pending: null

    // Das Fenster bleibt bestehen und wird nur ein- und ausgeblendet: so ist
    // die Liste beim naechsten Oeffnen sofort da.
    visible: Runtime.launcherOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:launcher"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.launcherOpen = false;
    }

    function accept() {
        const entry = results[selected];
        if (!entry) {
            // Nichts getroffen: die Eingabe war offenbar ein Befehl fuer die
            // Shell darunter, kein Suchbegriff.
            Apps.run(root.mode === "beides" ? input.text : root.query);
            close();
            return;
        }

        if (entry.kind === "cmd") {
            if (entry.confirm && root.pending !== entry) {
                root.pending = entry;
                return;
            }
            Commands.invoke(entry);
        } else {
            Apps.launch(entry);
        }
        close();
    }

    function move(delta) {
        if (results.length === 0)
            return;
        root.pending = null;
        selected = Math.max(0, Math.min(results.length - 1, selected + delta));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    onVisibleChanged: {
        if (visible) {
            input.text = Runtime.launcherPrefill;
            input.cursorPosition = input.text.length;
            selected = 0;
            pending = null;
            input.forceActiveFocus();
        } else {
            // Der Praefix gilt fuer EIN Oeffnen. Bliebe er stehen, kaeme der
            // Starter beim naechsten Mal wieder als Palette hoch, ohne dass
            // jemand danach gefragt haette.
            Runtime.launcherPrefill = "";
        }
    }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // Etwas oberhalb der Mitte: dort sucht das Auge zuerst, und die Liste
        // waechst nach unten.
        y: Math.round(parent.height * 0.22)

        width: Math.round(Theme.cellW * 64)
        height: header.height + list.height + footer.height + Theme.cellH

        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.accent

        // Klicks im Kasten sollen ihn nicht schliessen.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.8

            Text {
                id: prompt

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "> "
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            TextInput {
                id: input

                anchors.left: prompt.right
                anchors.right: counter.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                focus: true
                selectByMouse: true
                selectionColor: Theme.selection
                selectedTextColor: Theme.fg

                onTextChanged: {
                    root.selected = 0;
                    root.pending = null;
                    list.positionViewAtBeginning();
                }

                // Erst die Rueckfrage abraeumen, dann das Fenster: wer sich bei
                // "Ausschalten" vertippt hat, will nicht blind ein zweites Mal
                // Esc druecken muessen und dabei raten, was gerade passiert.
                Keys.onEscapePressed: {
                    if (root.pending)
                        root.pending = null;
                    else
                        root.close();
                }
                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onPressed: event => {
                    // Ctrl-N/P wie in jedem Terminalprogramm.
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_N) {
                            root.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_P) {
                            root.move(-1);
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Anwendung oder Befehl suchen  (> nur Befehle, ! nur Anwendungen)"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            Text {
                id: counter

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.results.length + ""
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.borderWidth
                color: Theme.muted
            }
        }

        ListView {
            id: list

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            anchors.topMargin: Theme.cellH * 0.4

            // Feste Zeilenzahl statt einer Hoehe in Pixeln: der Kasten aendert
            // seine Groesse beim Tippen dann nicht.
            height: rowHeight * Math.min(12, Math.max(1, root.results.length))
            readonly property real rowHeight: Theme.cellH * 2.4

            clip: true
            model: root.results
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: list.rowHeight
                color: index === root.selected ? Theme.selection : "transparent"

                Text {
                    id: marker

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.index === root.selected ? "▸" : " "
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                // Das Symbol des Programms. Die einzige Stelle im Starter, die
                // nicht aus Zeichen besteht -- ohne sie sucht das Auge laenger.
                Item {
                    id: appIcon

                    anchors.left: marker.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Theme.cellH * 1.5)
                    height: width

                    // Befehle haben kein Symbol und sollen auch keines
                    // vortaeuschen: sie bekommen das Prompt-Zeichen, an dem
                    // man sie auf einen Blick von einer Anwendung trennt.
                    readonly property bool isCommand: row.modelData.kind === "cmd"
                    readonly property string iconSource: isCommand ? "" : Apps.iconFor(row.modelData)

                    IconImage {
                        anchors.fill: parent
                        visible: appIcon.iconSource !== ""
                        source: appIcon.iconSource
                    }

                    // Ersatz fuer Programme ohne Symbol: der erste Buchstabe in
                    // einem Kasten, wie ein Kuerzel.
                    Rectangle {
                        anchors.fill: parent
                        visible: appIcon.iconSource === ""
                        color: "transparent"
                        border.width: Theme.borderWidth
                        border.color: appIcon.isCommand ? Theme.accent : Theme.muted
                        radius: Theme.radius

                        Text {
                            anchors.centerIn: parent
                            text: appIcon.isCommand ? ">" : (row.modelData.name || "?").charAt(0).toUpperCase()
                            color: appIcon.isCommand ? Theme.accent : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }
                    }
                }

                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: Theme.cellW
                    anchors.right: badge.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        width: parent.width
                        text: row.modelData.name
                        color: row.index === root.selected ? Theme.on(Theme.selection) : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.modelData.genericName || row.modelData.comment || ""
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: badge

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.cellW / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.kind === "cmd" ? (row.modelData.category || "BEFEHL").toUpperCase() : (row.modelData.runInTerminal ? "TUI" : "APP")
                    color: row.modelData.kind === "cmd" ? Theme.fgDim : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selected = row.index
                    onClicked: root.accept()
                }
            }
        }

        Text {
            id: footer

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.4
            verticalAlignment: Text.AlignVCenter
            text: {
                if (root.pending)
                    return "\"" + root.pending.name + "\" -- nochmal Enter bestaetigt, Esc bricht ab";
                if (root.results.length > 0)
                    return "↑↓ waehlen · Enter starten · Esc schliessen";
                if (input.text === "")
                    return "nichts gefunden";
                return "Enter fuehrt \"" + root.query + "\" als Befehl aus";
            }
            color: root.pending ? Theme.red : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }
}
