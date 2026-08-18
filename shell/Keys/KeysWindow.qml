import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Alle Tastenkuerzel auf einen Blick (Mod+K).
//
// niri bringt selbst eine Uebersicht mit (Mod+Shift+/), die aber nur zeigt,
// was jemand mit `hotkey-overlay-title` beschriftet hat -- und das ist hier
// weniger als die Haelfte. Der Rest steht ohne Titel in acht Dateien verteilt.
// Dieses Fenster liest alle, uebersetzt die Aktionen und sortiert sie.
//
// Gebaut wie die Mediathek: ein Vollbildfenster, das die Tastatur exklusiv
// nimmt, sichtbar nur der Kasten in der Mitte. Nur ist hier nichts zu
// bedienen, also darf das Tippen direkt filtern -- kein "/" davor.
PanelWindow {
    id: root

    property string query: ""

    // Erste sichtbare Zeile. Geblaettert wird, nicht ausgewaehlt: es gibt hier
    // nichts anzuklicken, und eine Markierung, die nichts tut, waere ein
    // Versprechen, das das Fenster nicht halten kann.
    property int off: 0

    readonly property real boxW: Theme.cellW * 130
    readonly property real boxH: Theme.cellH * 36
    readonly property real zeilenH: Theme.cellH * 1.2

    // Wie viele Zeilen JE SPALTE hineinpassen -- gerechnet, nicht gesetzt:
    // Kopfzeile, Trennlinie und Fusszeile brauchen zusammen gut sechs Zellen.
    readonly property int sicht: Math.max(4, Math.floor((root.boxH - Theme.cellH * 7) / root.zeilenH))
    readonly property int proSeite: root.sicht * 2

    // Die flache Liste, die im Kasten steht: Gruppenkoepfe und Bindungen
    // gemischt, in der Reihenfolge, in der sie erscheinen sollen.
    //
    // Flach und nicht verschachtelt, weil sie auf ZWEI Spalten verteilt wird:
    // eine Gruppe kann mitten in der linken Spalte enden und rechts
    // weitergehen. Mit einem Baum muesste man rechnen, wo welcher Ast
    // umbricht; mit einer Liste ist es ein `slice`.
    readonly property var zeilen: {
        const suche = root.query.toLowerCase().trim();
        const treffer = Binds.list.filter(b => {
            if (suche === "")
                return true;
            return (b.taste + " " + b.text + " " + b.aktion + " " + b.gruppe).toLowerCase().indexOf(suche) >= 0;
        });

        const out = [];
        for (var g = 0; g < Binds.gruppen.length; g++) {
            const name = Binds.gruppen[g];
            const drin = treffer.filter(b => b.gruppe === name);
            if (drin.length === 0)
                continue;
            out.push({
                "kopf": true,
                "text": name + "  (" + drin.length + ")"
            });
            for (var i = 0; i < drin.length; i++)
                out.push({
                    "kopf": false,
                    "taste": drin[i].taste,
                    "text": drin[i].text
                });
        }
        return out;
    }

    readonly property int maxOff: Math.max(0, root.zeilen.length - root.proSeite)

    visible: Runtime.keysOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:keys"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.keysOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.keysOpen = false;
    }

    // Beim Oeffnen einmal lesen -- und oben anfangen, mit leerer Suche. Wer
    // das Fenster zumacht und wieder aufmacht, sucht selten dasselbe noch
    // einmal.
    onVisibleChanged: {
        if (!root.visible)
            return;
        root.query = "";
        root.off = 0;
        Binds.ensure();
    }

    // Beim Tippen zurueck nach oben: sonst filtert man auf drei Treffer und
    // sieht eine leere Seite, weil der Blick noch bei Zeile 90 steht.
    onQueryChanged: root.off = 0

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                // Erst die Suche zuruecknehmen, dann schliessen -- wie in der
                // Mediathek. Ein Esc, das sofort zumacht, kostet den Weg zur
                // vollen Liste zurueck.
                if (root.query !== "")
                    root.query = "";
                else
                    root.close();
                break;
            case Qt.Key_Backspace:
                root.query = root.query.slice(0, -1);
                break;
            case Qt.Key_Down:
                root.off = Math.min(root.off + 1, root.maxOff);
                break;
            case Qt.Key_Up:
                root.off = Math.max(0, root.off - 1);
                break;
            case Qt.Key_PageDown:
            case Qt.Key_Right:
                root.off = Math.min(root.off + root.proSeite, root.maxOff);
                break;
            case Qt.Key_PageUp:
            case Qt.Key_Left:
                root.off = Math.max(0, root.off - root.proSeite);
                break;
            case Qt.Key_Home:
                root.off = 0;
                break;
            case Qt.Key_End:
                root.off = root.maxOff;
                break;
            case Qt.Key_F5:
                Binds.load();
                break;
            default:
                // Alles Druckbare ist Suche. Kein "/" davor: hier gibt es
                // keinen zweiten Modus, in dem ein Buchstabe etwas anderes
                // bedeuten koennte.
                if (event.text && event.text.length === 1 && event.text >= " ")
                    root.query += event.text;
                break;
            }
            event.accepted = true;
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: kasten

            x: (parent.width - width) / 2
            y: (parent.height - height) / 2

            width: root.boxW
            height: root.boxH

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            // Klicks im Kasten fallen nicht zum Schliessen durch.
            MouseArea {
                anchors.fill: parent
            }

            // Blaettern mit dem Mausrad -- die Liste ist laenger als eine
            // Seite, und die Hand liegt oft ohnehin an der Maus.
            WheelHandler {
                onWheel: wheelEvent => {
                    const schritt = wheelEvent.angleDelta.y > 0 ? -3 : 3;
                    root.off = Math.max(0, Math.min(root.off + schritt, root.maxOff));
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW

                spacing: 0

                PanelHead {
                    rowWidth: kasten.width - Theme.cellW * 2
                    icon: Icons.keyboard
                    title: root.query !== "" ? "Suche: " + root.query : "Tastenkuerzel"
                    subtitle: "niri"
                    badge: Binds.loading ? "…" : String(Binds.list.length)

                    // Ziehen an der Kopfzeile, wie bei der Mediathek.
                    DragHandler {
                        target: kasten

                        xAxis.minimum: 0
                        xAxis.maximum: root.width - kasten.width
                        yAxis.minimum: 0
                        yAxis.maximum: root.height - kasten.height

                        cursorShape: Qt.ClosedHandCursor
                    }
                }

                Rule {
                    rowWidth: kasten.width - Theme.cellW * 2
                }

                Line {
                    visible: Binds.problem !== ""
                    text: "  " + Binds.problem
                    color: Theme.yellow
                }

                Line {
                    visible: Binds.problem === "" && root.zeilen.length === 0
                    text: Binds.loading ? "  reading configuration …" : "  nothing found"
                    color: Theme.muted
                }

                // ── Zwei Spalten ──────────────────────────────────────────
                //
                // Die linke nimmt die erste Haelfte des Sichtfensters, die
                // rechte die zweite. Gelesen wird also spaltenweise von oben
                // nach unten -- wie in einem Handbuch, nicht wie in einer
                // Zeitung.
                Row {
                    spacing: Theme.cellW * 2

                    component Spalte: Column {
                        id: spalte

                        property int von: 0

                        readonly property real breite: (kasten.width - Theme.cellW * 6) / 2

                        clip: true
                        width: spalte.breite
                        height: root.sicht * root.zeilenH
                        spacing: 0

                        Repeater {
                            model: root.zeilen.slice(spalte.von, spalte.von + root.sicht)

                            delegate: Item {
                                id: zeile

                                required property var modelData

                                width: spalte.breite
                                height: root.zeilenH

                                // Gruppenkopf: eine Zeile, die keine Bindung
                                // ist, sondern sagt, worum es in den naechsten
                                // geht.
                                Line {
                                    visible: zeile.modelData.kopf
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: zeile.modelData.text.toUpperCase()
                                    color: Theme.readable(Theme.accent, Theme.bg)
                                }

                                Line {
                                    id: taste

                                    visible: !zeile.modelData.kopf
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.cellW * 20
                                    text: zeile.modelData.taste ?? ""
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Line {
                                    visible: !zeile.modelData.kopf
                                    anchors.left: taste.right
                                    anchors.leftMargin: Theme.cellW
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: zeile.modelData.text
                                    color: Theme.fgDim
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Spalte {
                        von: root.off
                    }

                    Spalte {
                        von: root.off + root.sicht
                    }
                }

                Rule {
                    rowWidth: kasten.width - Theme.cellW * 2
                }

                Item {
                    width: kasten.width - Theme.cellW * 2
                    height: Theme.cellH * 1.4

                    Line {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Breite BEGRENZEN: ein Text ohne Breite waechst, bis
                        // er aus dem Kasten laeuft -- genau das ist der
                        // Fusszeile der Mediathek einmal passiert.
                        width: parent.width - Theme.cellW * 14
                        text: "type to search · ↑↓ browse · ←→ page · F5 reload · Esc close"
                        color: Theme.muted
                        elide: Text.ElideRight
                    }

                    Line {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.zeilen.length > root.proSeite ? (root.off + 1) + "–" + Math.min(root.off + root.proSeite, root.zeilen.length) + " / " + root.zeilen.length : ""
                        color: Theme.muted
                    }
                }
            }
        }
    }
}
