import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

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
        if (t.startsWith("#"))
            return "window";
        if (t.startsWith("^"))
            return "clipboard";
        if (t.startsWith("="))
            return "calculator";
        if (t.startsWith("@"))
            return "file";
        return "all";
    }

    readonly property string query: root.mode === "all" ? input.text : input.text.substring(1).trim()

    // The explicit property reads keep this binding reactive when an
    // asynchronous provider completes after the text itself stopped changing.
    readonly property var results: {
        const fileRevision = SearchProviders.files;
        const q = root.query;
        if (root.mode === "cmd")
            return Commands.rank(q).map(x => x.entry);
        if (root.mode === "app")
            return Apps.rank(q).map(x => x.entry);
        if (root.mode === "window")
            return SearchProviders.rankWindows(q).map(x => x.entry);
        if (root.mode === "clipboard")
            return SearchProviders.rankClipboard(q).map(x => x.entry);
        if (root.mode === "calculator")
            return SearchProviders.calculator(q).map(x => x.entry);
        if (root.mode === "file")
            return SearchProviders.fileRows(q).map(x => x.entry);

        const apps = Apps.rank(q);
        const cmds = Commands.rank(q);
        const windows = SearchProviders.rankWindows(q);
        const calculator = SearchProviders.calculator(q);

        // Ohne Eingabe gibt es nichts zu vergleichen -- dann stehen die
        // Anwendungen nach Haeufigkeit oben und die Befehle darunter.
        if (!q)
            return apps.map(x => x.entry).concat(cmds.map(x => x.entry));

        const merged = apps.concat(cmds.map(x => ({
                    "entry": x.entry,
                    "points": x.points * root.commandBias
                }))).concat(windows).concat(calculator);
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
        } else if (entry.kind === "app" || entry.command) {
            Apps.launch(entry);
        } else {
            SearchProviders.activate(entry);
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

    Connections {
        target: Runtime
        function onLauncherPrefillChanged() {
            if (!root.visible || Runtime.launcherPrefill === input.text)
                return;
            input.text = Runtime.launcherPrefill;
            input.cursorPosition = input.text.length;
            root.selected = 0;
            input.forceActiveFocus();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    PanelSurface {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // Etwas oberhalb der Mitte: dort sucht das Auge zuerst, und die Liste
        // waechst nach unten.
        y: Math.round(parent.height * 0.12)

        width: Math.min(parent.width - Theme.spaceXl * 4, Math.round(Theme.cellW * 92))
        height: header.height + list.height + footer.height + Theme.cellH

        accentBorder: true

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
            height: Theme.cellH * 2.35

            Rectangle {
                anchors.fill: parent
                color: Theme.panelSurfaceRaised
                radius: Theme.radius
                border.width: Theme.borderWidth
                border.color: input.activeFocus ? Theme.focusBorder : Theme.panelBorder
            }

            Line {
                id: prompt

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "> "
                color: Theme.readable(Theme.accent, Theme.panelSurfaceRaised, 4.5)
            }

            TextInput {
                id: input

                anchors.left: prompt.right
                anchors.right: counter.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSubtitle
                focus: true
                selectByMouse: true
                selectionColor: Theme.selection
                selectedTextColor: Theme.fg

                onTextChanged: {
                    root.selected = 0;
                    root.pending = null;
                    list.positionViewAtBeginning();
                    const typed = input.text;
                    Qt.callLater(() => {
                        if (input.text === typed && typed.startsWith("@"))
                            SearchProviders.requestFiles(typed.substring(1));
                    });
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

                Line {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "Search apps, commands, windows, or calculate"
                    color: Theme.muted
                }
            }

            Line {
                id: counter

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.results.length + ""
                color: Theme.fgDim
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
            height: rowHeight * Math.min(14, Math.max(1, root.results.length))
            readonly property real rowHeight: Theme.menuRowHeight

            clip: true
            // Hidden layer-shell windows keep their QML tree alive. Avoid
            // resolving and rasterizing a screenful of desktop SVG icons at
            // startup; populate delegates only while the launcher is open.
            model: root.visible ? root.results : []
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: list.rowHeight
                radius: Theme.radius
                color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"
                border.width: index === root.selected ? Theme.borderWidth : 0
                border.color: Theme.focusBorder

                Line {
                    id: marker

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.index === root.selected ? "▸" : " "
                    color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.accent
                }

                // Das Symbol des Programms. Die einzige Stelle im Starter, die
                // nicht aus Zeichen besteht -- ohne sie sucht das Auge laenger.
                Item {
                    id: appIcon

                    anchors.left: marker.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Theme.cellH * 1.75)
                    height: width

                    // Befehle haben kein Symbol und sollen auch keines
                    // vortaeuschen: sie bekommen das Prompt-Zeichen, an dem
                    // man sie auf einen Blick von einer Anwendung trennt.
                    readonly property bool isCommand: row.modelData.kind === "cmd"
                    readonly property bool isApp: row.modelData.kind === "app" || !!row.modelData.command
                    readonly property string iconSource: isApp ? Apps.iconFor(row.modelData) : ""

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

                        Line {
                            anchors.centerIn: parent
                            text: appIcon.isCommand ? ">" : row.modelData.kind === "window" ? "#"
                                : row.modelData.kind === "clipboard" ? "^" : row.modelData.kind === "calculator" ? "="
                                : row.modelData.kind === "file" ? "@" : (row.modelData.name || "?").charAt(0).toUpperCase()
                            color: appIcon.isCommand ? Theme.accent : Theme.fgDim
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

                    Line {
                        width: parent.width
                        text: row.modelData.name
                        color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                        font.pixelSize: Theme.fontBody
                        elide: Text.ElideRight
                    }

                    Line {
                        width: parent.width
                        visible: text !== ""
                        text: row.modelData.genericName || row.modelData.comment || ""
                        color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }
                }

                Line {
                    id: badge

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.cellW / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.kind === "cmd" ? (row.modelData.category || "COMMAND").toUpperCase()
                        : row.modelData.kind === "app" || row.modelData.command ? (row.modelData.runInTerminal ? "TUI" : "APP")
                        : (row.modelData.category || row.modelData.kind || "RESULT").toUpperCase()
                    color: row.index === root.selected ? Theme.selectedForeground(Theme.accent)
                        : (row.modelData.kind === "cmd" ? Theme.fgDim : Theme.muted)
                    font.pixelSize: Theme.fontCaption
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

        Line {
            id: footer

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.4
            verticalAlignment: Text.AlignVCenter
            text: {
                if (root.pending)
                    return "\"" + root.pending.name + "\" -- press Enter again to confirm, Esc cancels";
                if (root.results.length > 0)
                    return "↑↓ SELECT · ENTER OPEN/COPY · # WINDOWS · ^ CLIPBOARD · @ FILES · = CALCULATOR";
                if (input.text === "")
                    return "nothing found";
                return "Enter runs \"" + root.query + "\" as a command";
            }
            color: root.pending ? Theme.red : Theme.muted
        }
    }
}
