import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Die Aufgabenliste als eigenes Fenster (Mod+T).
//
// Aufgebaut wie der Anwendungsstarter: ein Vollbildfenster, das die Tastatur
// exklusiv nimmt, sichtbar nur der Kasten in der Mitte. Anders liesse sich
// nicht tippen, waehrend darunter ein Fenster den Fokus haelt.
//
// Das Eingabefeld hat immer den Fokus -- man soll losschreiben koennen, ohne
// vorher irgendwo hinzuklicken. Deshalb liegt jede Aktion auf einer Taste, die
// beim Tippen nicht im Weg ist: Tab hakt ab, Strg+D wirft weg, Strg+E holt den
// Text zum Aendern ins Feld. Ein blankes `Leertaste = abhaken` gaebe es keine
// Aufgabe mit einem Leerzeichen darin.
PanelWindow {
    id: root

    property int selected: 0

    // Die id des Eintrags, der gerade im Eingabefeld liegt. Leer heisst: was
    // dort steht, wird ein neuer Eintrag.
    property string editing: ""

    readonly property var list: Todo.list

    // Der Ablageort in der Ueberschrift -- aber nur, wenn er absichtlich
    // gesetzt wurde. Wer nicht abgleicht, hat von "~/.local/state/…" nichts;
    // wer abgleicht, sieht hier sofort, ob er auf der Datei im Sync-Ordner
    // arbeitet. Das ist der haeufigste Grund, warum nichts ankommt.
    readonly property string shortPath: {
        if (String(Config.value("todoFile", "")) === "")
            return "";
        const home = Quickshell.env("HOME");
        return Todo.file.indexOf(home) === 0 ? "~" + Todo.file.substring(home.length) : Todo.file;
    }

    visible: Runtime.todoOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:todo"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.todoOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.todoOpen = false;
    }

    function current() {
        return root.list[root.selected] ?? null;
    }

    function move(delta) {
        if (list.length === 0)
            return;
        selected = Math.max(0, Math.min(list.length - 1, selected + delta));
        rows.positionViewAtIndex(selected, ListView.Contain);
    }

    // Enter: entweder den Text im Feld als neue Aufgabe eintragen oder die
    // begonnene Aenderung abschliessen.
    function accept() {
        const text = input.text.trim();
        if (text === "")
            return;
        if (editing !== "") {
            Todo.edit(editing, text);
            editing = "";
        } else {
            Todo.add(text);
            // Neues steht unten bei den openen -- die Auswahl geht mit, sonst
            // zeigt der Pfeil nach dem Eintragen auf etwas anderes.
            selected = Todo.list.length - 1;
        }
        input.text = "";
    }

    function startEdit() {
        const e = current();
        if (!e)
            return;
        editing = String(e.id);
        input.text = e.text;
        input.selectAll();
    }

    function cancelEdit() {
        editing = "";
        input.text = "";
    }

    function toggleCurrent() {
        const e = current();
        if (e)
            Todo.toggle(e.id);
    }

    function removeCurrent() {
        const e = current();
        if (!e)
            return;
        if (editing === String(e.id))
            cancelEdit();
        Todo.remove(e.id);
        // Die Liste wird kuerzer: sonst zeigte die Auswahl hinter das Ende.
        selected = Math.max(0, Math.min(selected, Todo.list.length - 1));
    }

    onVisibleChanged: {
        if (!visible)
            return;
        input.text = "";
        editing = "";
        selected = 0;
        // Eine Konfliktkopie kann liegen, seit die Shell zuletzt hingesehen
        // hat -- beim Oeffnen ist der richtige Moment, sie einzusammeln.
        Todo.foldConflicts();
        input.forceActiveFocus();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: box

        // Mittig oben -- bis jemand ihn wegzieht. niri kann dieses Fenster
        // nicht verschieben: es ist eine Layer-Shell-Flaeche und liegt
        // ausserhalb seiner Zustaendigkeit, Mod+Ziehen gilt nur fuer normale
        // Fenster. Also zieht der Kasten sich selbst.
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.18)

        DragHandler {
            acceptedModifiers: Qt.MetaModifier
            cursorShape: Qt.ClosedHandCursor

            xAxis.minimum: 0
            xAxis.maximum: root.width - box.width
            yAxis.minimum: 0
            yAxis.maximum: root.height - box.height
        }

        // Breiter als der Starter (64 Zeichen): hier steht in der Fusszeile
        // neben den Tasten auch der Ablageort, und beides zusammen passt sonst
        // nicht nebeneinander.
        width: Math.round(Theme.cellW * 80)
        // Die Fusszeile braucht Luft nach oben, sonst klebt sie an der letzten
        // Aufgabe und liest sich wie eine weitere Zeile der Liste.
        height: header.height + rows.height + footer.height + Theme.cellH * 1.6

        color: Theme.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.accent

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 3.4

            Line {
                id: title

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: counts.left
                anchors.rightMargin: Theme.cellW
                elide: Text.ElideMiddle
                text: "TASKS" + (root.shortPath !== "" ? "  ·  " + root.shortPath : "")
                color: Theme.fgDim
            }

            Line {
                id: counts

                anchors.top: parent.top
                anchors.right: parent.right
                text: Todo.count + " open" + (Todo.doneCount > 0 ? "  ·  " + Todo.doneCount + " done" : "")
                color: Theme.fgDim
            }

            Line {
                id: prompt

                anchors.bottom: line.top
                anchors.bottomMargin: Theme.cellH * 0.3
                anchors.left: parent.left
                // Beim Aendern ein anderes Zeichen: sonst sieht ein volles
                // Eingabefeld genauso aus wie ein halb getippter neuer Eintrag.
                text: root.editing !== "" ? "✎ " : "> "
                color: root.editing !== "" ? Theme.yellow : Theme.accent
            }

            TextInput {
                id: input

                anchors.bottom: line.top
                anchors.bottomMargin: Theme.cellH * 0.3
                anchors.left: prompt.right
                anchors.right: parent.right
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                focus: true
                selectByMouse: true
                selectionColor: Theme.selection
                selectedTextColor: Theme.on(Theme.selection)

                Keys.onReturnPressed: root.accept()
                Keys.onEnterPressed: root.accept()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)

                // Esc raeumt erst das Feld, dann schliesst es. So verliert ein
                // versehentliches Esc nicht gleich das ganze Fenster -- und ein
                // zweites Esc kommt schnell.
                Keys.onEscapePressed: {
                    if (root.editing !== "" || input.text !== "")
                        root.cancelEdit();
                    else
                        root.close();
                }

                Keys.onTabPressed: root.toggleCurrent()

                Keys.onPressed: event => {
                    if (!(event.modifiers & Qt.ControlModifier))
                        return;
                    if (event.key === Qt.Key_D) {
                        root.removeCurrent();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_E) {
                        root.startEdit();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_L) {
                        Todo.clearDone();
                        root.selected = 0;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_N) {
                        root.move(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_P) {
                        root.move(-1);
                        event.accepted = true;
                    }
                }

                Line {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: "type a new task and press Enter"
                    color: Theme.muted
                }
            }

            Rectangle {
                id: line

                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.borderWidth
                color: Theme.muted
            }
        }

        ListView {
            id: rows

            readonly property real rowHeight: Theme.cellH * 1.6

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            anchors.topMargin: Theme.cellH * 0.4

            // Feste Zeilenzahl: der Kasten soll beim Eintragen nicht springen.
            height: rowHeight * Math.min(14, Math.max(1, root.list.length))

            clip: true
            model: root.list
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds

            Line {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: Theme.cellH * 0.3
                visible: root.list.length === 0
                text: Todo.doneCount > 0 ? "alles done." : "no tasks."
                color: Theme.muted
            }

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                readonly property bool chosen: row.index === root.selected

                width: rows.width
                height: rows.rowHeight
                color: row.chosen ? Theme.selection : "transparent"

                Line {
                    id: marker

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.chosen ? "▸" : " "
                    color: Theme.accent
                }

                Line {
                    id: mark

                    anchors.left: marker.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.done ? "[x]" : "[ ]"
                    color: row.modelData.done ? Theme.green : Theme.fgDim
                }

                Line {
                    anchors.left: mark.right
                    anchors.leftMargin: Theme.cellW
                    anchors.right: age.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.text
                    color: row.modelData.done ? Theme.muted : (row.chosen ? Theme.on(Theme.selection) : Theme.fg)
                    font.strikeout: row.modelData.done
                    elide: Text.ElideRight
                }

                Line {
                    id: age

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.cellW / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(new Date(row.modelData.created), "dd.MM.")
                    color: Theme.muted
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: root.selected = row.index
                    onClicked: mouseEvent => {
                        root.selected = row.index;
                        if (mouseEvent.button === Qt.RightButton)
                            root.removeCurrent();
                        else
                            Todo.toggle(row.modelData.id);
                    }
                }
            }
        }

        Item {
            id: footer

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.cellW
            height: Theme.cellH * 1.4

            Line {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.editing !== "" ? "Enter saves · Esc cancels" : "Tab toggles · ↑↓ select · Ctrl+E edit · Ctrl+D delete · Ctrl+L clean up"
                color: Theme.muted
                elide: Text.ElideRight
            }
        }
    }
}
