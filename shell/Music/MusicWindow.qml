import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Die Mediathek als eigenes Fenster (Mod+M).
//
// Aufgebaut wie die Aufgabenliste und der Starter: ein Vollbildfenster, das
// die Tastatur exklusiv nimmt, sichtbar nur der Kasten in der Mitte. Zwei
// Spalten -- links die Playlists, rechts die Titel darin.
//
// Kein echtes Terminalprogramm, obwohl es so aussieht. Ein zweites
// Bedienkonzept neben dem, was hier schon steht, waere der teuerste Weg zu
// derselben Optik: Farben, Zeichenraster, Tastenfuehrung und die Popouts
// gibt es alle schon, und ein `ncurses`-Fenster koennte weder die Themefarben
// noch die Zellenbreite dieser Shell mitbenutzen.
//
// Bedient wird ausschliesslich mit der Tastatur, weil man beim Musikhoeren
// selten die Maus in der Hand hat: Pfeile bewegen, Tab wechselt die Spalte,
// Enter spielt, "/" sucht, Esc geht zurueck und dann zu.
PanelWindow {
    id: root

    // Welche Spalte die Pfeiltasten bedienen.
    property bool inTracks: false

    property int listSel: 0
    property int trackSel: 0

    // Der Suchtext. Solange er nicht leer ist, steht rechts das Ergebnis der
    // Suche statt der Playlist.
    property string query: ""
    property bool typing: false

    // ── Angeheftet ───────────────────────────────────────────────────────
    //
    // Das Fenster bleibt stehen, statt bei Esc oder einem Klick daneben zu
    // verschwinden. Wichtig dabei: es gibt dann die TASTATUR AB. Ein Fenster,
    // das dauerhaft sichtbar ist UND die Tastatur exklusiv haelt, waere ein
    // Rechner, an dem man nichts mehr tippen kann.
    //
    // Also zwei getrennte Dinge:
    //   Runtime.musicOpen  -- hat den Fokus, wird mit Tasten bedient
    //   pinned             -- ist zu sehen, nimmt nur noch die Maus
    //
    // Mod+P holt sich die Tastatur zurueck, auch waehrend es angeheftet ist;
    // Esc gibt sie wieder her und laesst das Fenster stehen.
    readonly property bool pinned: Config.value("musicPinned", false)

    function anheften() {
        const jetzt = !root.pinned;
        Config.set("musicPinned", jetzt);
        // Loesen darf das Fenster nicht wegnehmen: sichtbar war es bis eben
        // ueber `pinned`, und ohne das hier fiele `visible` sofort auf falsch.
        // Wer die Nadel zieht, will es weiter sehen -- jetzt eben mit Tastatur.
        if (!jetzt)
            Runtime.musicOpen = true;
    }

    // Auf welcher Zeile eine Loeschfrage offen steht (-1 = keine).
    property int loeschFrage: -1

    readonly property var shown: Music.shown

    // Der Kasten und was hineinpasst. Die Zeilenzahl wird GERECHNET, nicht
    // gesetzt: 22 standen hier zuerst als Zahl, und weil Kopf, Trennlinie und
    // Fusszeile zusammen sechs Zellen brauchen, lief die Liste unten aus dem
    // Kasten heraus und legte sich ueber die Fusszeile.
    readonly property real boxW: Theme.cellW * 108
    readonly property real boxH: Theme.cellH * 32
    readonly property real zeilenH: Theme.cellH * 1.25
    readonly property int sicht: Math.max(4, Math.floor((root.boxH - Theme.cellH * 8.5) / root.zeilenH))

    visible: Runtime.musicOpen || root.pinned

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:music"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.musicOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    // Angeheftet nimmt NUR der Kasten Klicks an. Ohne diese Maske laege eine
    // unsichtbare, bildschirmgrosse Flaeche ueber allem -- man kaeme an kein
    // Fenster darunter mehr heran. Dasselbe Mittel wie bei der Leiste.
    mask: root.pinned && !Runtime.musicOpen ? kastenRegion : null

    Region {
        id: kastenRegion

        item: kasten
    }

    function close() {
        Runtime.musicOpen = false;
    }

    // Beim Oeffnen einmal laden -- aber nur, wenn noch nichts da ist. Wer das
    // Fenster zum dritten Mal aufmacht, will keine Wartezeit fuer eine Liste,
    // die sich seit dem Fruehstueck nicht geaendert hat. F5 holt sie neu.
    onVisibleChanged: {
        if (!root.visible)
            return;
        root.typing = false;
        if (Music.playlists.length === 0)
            Music.ladePlaylists();
        else if (Music.shown.length === 0)
            root.vorschauLaden();
        else
            root.folgen();
    }

    // Beim Blaettern durch die Playlists laedt die rechte Spalte mit -- man
    // sieht sofort, was drin ist, ohne jede Liste erst zu oeffnen.
    //
    // Aber NICHT bei jedem Tastendruck: wer mit gedrueckter Pfeiltaste durch
    // sechzehn Playlists faehrt, loeste sechzehn Netzabfragen aus. Der Takt
    // wartet, bis die Auswahl einen Moment stillsteht; schon Geholtes kommt
    // ohnehin aus dem Zwischenspeicher und ist sofort da.
    function vorschauLaden() {
        const p = Music.playlists[root.listSel];
        if (!p)
            return;
        root.query = "";
        Music.ladePlaylist(p.id, p.titel);
        root.trackSel = 0;
    }

    onListSelChanged: if (root.visible)
        blaettern.restart()

    onTrackSelChanged: root.loeschFrage = -1

    // Der Liste hinterherspringen, wenn der Titel wechselt.
    //
    // Im Zufallsmodus ist das der eigentliche Punkt: der naechste Titel steht
    // nicht in der naechsten Zeile, sondern irgendwo in der Playlist -- ohne
    // Sprung sucht man ihn jedesmal selbst. Die Markierung ▸ allein hilft
    // nicht, wenn sie zwanzig Zeilen ausserhalb des Fensters sitzt.
    //
    // Nur, wenn der laufende Titel ueberhaupt in dem steht, was gerade zu
    // sehen ist: wer waehrenddessen in einer anderen Playlist blaettert oder
    // sucht, soll nicht bei jedem Titelwechsel herausgerissen werden.
    function folgen() {
        if (!root.visible || !Music.current || root.query !== "")
            return;
        const i = root.shown.findIndex(t => t.id === Music.current.id);
        if (i >= 0 && i !== root.trackSel)
            root.trackSel = i;
    }

    Connections {
        target: Music

        function onCurrentChanged() {
            root.folgen();
        }

        // Auch nach dem Laden einer Playlist: wer die Liste oeffnet, in der
        // gerade etwas laeuft, landet gleich an der richtigen Stelle.
        function onTracksChanged() {
            root.folgen();
        }
    }

    // Beim allerersten Oeffnen sind die Playlists noch unterwegs. Sobald sie
    // da sind, wird die erste gleich mitgeladen -- sonst bliebe die rechte
    // Spalte leer, bis jemand eine Taste drueckt.
    Connections {
        target: Music

        function onPlaylistsChanged() {
            if (root.visible && Music.shown.length === 0)
                root.vorschauLaden();
        }
    }

    Timer {
        id: blaettern

        interval: 260
        onTriggered: root.vorschauLaden()
    }

    function playlistOeffnen() {
        blaettern.stop();
        root.vorschauLaden();
        root.inTracks = true;
    }

    // Enter auf einem Titel spielt AB DIESER STELLE weiter, nicht nur den einen
    // -- alles andere waere bei einer Playlist die falsche Erwartung.
    function spielen() {
        if (root.shown.length === 0)
            return;
        Music.spieleListe(root.shown, Math.max(0, Math.min(root.trackSel, root.shown.length - 1)));
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            // Im Suchfeld frisst das Tippen alles ausser Esc und Enter.
            if (root.typing) {
                if (event.key === Qt.Key_Escape) {
                    root.typing = false;
                    root.query = "";
                    Music.suche("");
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.typing = false;
                    Music.suche(root.query);
                    root.trackSel = 0;
                    root.inTracks = true;
                } else if (event.key === Qt.Key_Backspace) {
                    root.query = root.query.slice(0, -1);
                } else if (event.text && event.text.length === 1 && event.text >= " ") {
                    root.query += event.text;
                }
                event.accepted = true;
                return;
            }

            switch (event.key) {
            case Qt.Key_Escape:
                // Erst aus den Titeln zurueck in die Playlists, dann zu. Ein
                // Esc, das sofort schliesst, kostet den Weg zurueck.
                if (root.inTracks)
                    root.inTracks = false;
                else
                    root.close();
                break;
            case Qt.Key_Slash:
                root.typing = true;
                root.query = "";
                break;
            case Qt.Key_Tab:
            case Qt.Key_Right:
                root.inTracks = true;
                break;
            case Qt.Key_Backtab:
            case Qt.Key_Left:
                root.inTracks = false;
                break;
            case Qt.Key_Down:
                if (root.inTracks)
                    root.trackSel = Math.min(root.trackSel + 1, root.shown.length - 1);
                else
                    root.listSel = Math.min(root.listSel + 1, Music.playlists.length - 1);
                break;
            case Qt.Key_Up:
                if (root.inTracks)
                    root.trackSel = Math.max(root.trackSel - 1, 0);
                else
                    root.listSel = Math.max(root.listSel - 1, 0);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (root.inTracks)
                    root.spielen();
                else
                    root.playlistOeffnen();
                break;
            case Qt.Key_Space:
                Music.playPause();
                break;
            case Qt.Key_Plus:
            case Qt.Key_Equal:
                Music.setzeLautstaerke(Music.lautstaerke + 0.05);
                break;
            case Qt.Key_Minus:
                Music.setzeLautstaerke(Music.lautstaerke - 0.05);
                break;
            case Qt.Key_D:
            case Qt.Key_Delete:
                // Zweimal druecken. Ein Titel ist schnell weg und muss dann
                // von Hand wiedergefunden werden -- das ist die Sorte
                // Aktion, die eine Rueckfrage verdient, aber keinen Dialog.
                if (root.inTracks && root.query === "" && Music.listId !== "") {
                    if (root.loeschFrage === root.trackSel) {
                        Music.entfernen(Music.listId, root.shown[root.trackSel]);
                        root.loeschFrage = -1;
                    } else {
                        root.loeschFrage = root.trackSel;
                    }
                }
                break;
            case Qt.Key_A:
                // Aus der Suche in die links gewaehlte Playlist. Genau
                // andersherum gedacht als das Loeschen: links steht das Ziel,
                // rechts das, was hinein soll.
                if (root.inTracks && root.shown[root.trackSel]) {
                    const ziel = Music.playlists[root.listSel];
                    if (ziel)
                        Music.hinzufuegen(ziel.id, root.shown[root.trackSel]);
                }
                break;
            case Qt.Key_P:
                root.anheften();
                break;
            case Qt.Key_S:
                Music.toggleShuffle();
                break;
            case Qt.Key_F5:
                Music.ladePlaylists();
                break;
            }
            event.accepted = true;
        }

        // Daneben klicken schliesst -- wie bei allen anderen Fenstern hier.
        MouseArea {
            anchors.fill: parent
            enabled: Runtime.musicOpen
            onClicked: root.close()
        }

        Rectangle {
            id: kasten

            // Mittig -- aber nur, bis jemand ihn wegzieht. Das ist Absicht und
            // kein Ersatz-Fenstermanager: ein Layer-Shell-Fenster kann niri
            // NICHT verschieben (Mod+Ziehen gilt nur fuer normale Fenster), es
            // liegt ausserhalb seiner Zustaendigkeit. Also macht es der Kasten
            // selbst -- der DragHandler schreibt x und y und loest die
            // Zentrierung dabei auf.
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2

            width: root.boxW
            height: root.boxH

            DragHandler {
                id: schieber

                // Mit gedrueckter Mod-Taste, wie man es von niri kennt. Ohne
                // Modifikator waere jeder Klick auf eine Zeile ein Zugversuch.
                acceptedModifiers: Qt.MetaModifier
                cursorShape: Qt.ClosedHandCursor

                // Nicht ueber den Bildschirmrand hinaus -- ein Kasten, den man
                // nicht mehr fassen kann, ist verloren bis zum Neustart.
                xAxis.minimum: 0
                xAxis.maximum: root.width - kasten.width
                yAxis.minimum: 0
                yAxis.maximum: root.height - kasten.height
            }

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            // Klicks im Kasten sollen nicht zum Schliessen durchfallen.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW

                spacing: 0

                PanelHead {
                    rowWidth: kasten.width - Theme.cellW * 2
                    icon: Icons.play

                    // Ziehen an der Kopfzeile, ohne Modifikator.
                    //
                    // Angeheftet nimmt das Fenster die Tastatur nicht mehr an
                    // -- und ohne Tastaturfokus schickt der Kompositor ihm auch
                    // KEINEN Modifikatorzustand mehr. Ein DragHandler, der auf
                    // Mod wartet, kann dort also gar nicht ausloesen. Die
                    // Kopfzeile ist ohnehin der Griff, den man an einem Fenster
                    // zuerst sucht.
                    DragHandler {
                        target: kasten

                        xAxis.minimum: 0
                        xAxis.maximum: root.width - kasten.width
                        yAxis.minimum: 0
                        yAxis.maximum: root.height - kasten.height

                        cursorShape: Qt.ClosedHandCursor
                    }
                    title: root.query !== "" ? "Suche: " + root.query : (Music.listName || "Mediathek")
                    subtitle: "YouTube Music"
                    badge: Music.busy ? "…" : String(root.shown.length)
                }

                Rule {
                    rowWidth: kasten.width - Theme.cellW * 2
                }

                // ── Die zwei Spalten ──────────────────────────────────────
                Row {
                    spacing: Theme.cellW * 2

                    Column {
                        id: linke

                        clip: true

                        readonly property real spalte: Theme.cellW * 32

                        width: linke.spalte
                        height: root.sicht * root.zeilenH

                        Repeater {
                            model: Music.playlists

                            Item {
                                id: zeile

                                required property var modelData
                                required property int index

                                width: linke.spalte
                                height: root.zeilenH

                                Rectangle {
                                    anchors.fill: parent
                                    color: zeile.index === root.listSel ? (root.inTracks ? Theme.selection : Theme.accent) : "transparent"
                                    radius: Theme.radius
                                }

                                Line {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW / 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    width: linke.spalte - Theme.cellW * 6
                                    elide: Text.ElideRight

                                    text: zeile.modelData.titel
                                    color: zeile.index === root.listSel && !root.inTracks ? Theme.on(Theme.accent) : Theme.fg
                                }

                                Line {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.cellW / 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    text: zeile.modelData.anzahl > 0 ? String(zeile.modelData.anzahl) : ""
                                    color: zeile.index === root.listSel && !root.inTracks ? Theme.on(Theme.accent) : Theme.muted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.listSel = zeile.index;
                                        root.playlistOeffnen();
                                    }
                                }
                            }
                        }
                    }

                    // Trennlinie zwischen den Spalten -- senkrecht, ein Pixel.
                    Rectangle {
                        width: Theme.borderWidth
                        height: root.sicht * root.zeilenH
                        color: Theme.muted
                    }

                    Column {
                        id: rechte

                        clip: true

                        readonly property real spalte: kasten.width - linke.spalte - Theme.cellW * 7

                        width: rechte.spalte
                        height: root.sicht * root.zeilenH

                        Line {
                            visible: root.shown.length === 0
                            text: Music.busy ? "  lädt …" : (Music.error !== "" ? "  " + Music.error : "  Enter auf einer Playlist — oder / zum Suchen")
                            color: Music.error !== "" ? Theme.red : Theme.muted
                        }

                        Repeater {
                            // Mehr als das passt nicht ins Fenster; gescrollt
                            // wird, indem das Fenster mitwandert (siehe unten).
                            model: root.shown.slice(root.fenster, root.fenster + root.sicht)

                            Item {
                                id: tzeile

                                required property var modelData
                                required property int index

                                readonly property int echt: root.fenster + tzeile.index

                                width: rechte.spalte
                                height: root.zeilenH

                                Rectangle {
                                    anchors.fill: parent
                                    color: tzeile.echt === root.trackSel ? (root.inTracks ? Theme.accent : Theme.selection) : "transparent"
                                    radius: Theme.radius
                                }

                                Line {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW / 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    width: rechte.spalte * 0.52
                                    elide: Text.ElideRight

                                    // Was gerade laeuft, bekommt ein Zeichen davor.
                                    text: (Music.current && Music.current.id === tzeile.modelData.id ? "▸ " : "  ") + tzeile.modelData.titel
                                    color: tzeile.echt === root.trackSel && root.inTracks ? Theme.on(Theme.accent) : Theme.fg
                                }

                                Line {
                                    anchors.left: parent.left
                                    anchors.leftMargin: rechte.spalte * 0.54
                                    anchors.verticalCenter: parent.verticalCenter

                                    width: rechte.spalte * 0.32
                                    elide: Text.ElideRight

                                    text: tzeile.modelData.interpret
                                    color: tzeile.echt === root.trackSel && root.inTracks ? Theme.on(Theme.accent) : Theme.muted
                                }

                                Line {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.cellW / 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    text: tzeile.modelData.dauer
                                    color: tzeile.echt === root.trackSel && root.inTracks ? Theme.on(Theme.accent) : Theme.muted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.trackSel = tzeile.echt;
                                        root.inTracks = true;
                                        root.spielen();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Fusszeile ────────────────────────────────────────────────
            // ── Was gerade laeuft ────────────────────────────────────────
            //
            // Titel, Stelle, Laenge, Lautstaerke -- und beide Balken sind
            // bedienbar: `LevelBar` meldet beim Ziehen den Wert, das genuegt
            // fuer Spulen und Lautstaerke, ohne einen eigenen Regler zu bauen.
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.cellW
                anchors.right: parent.right
                anchors.rightMargin: Theme.cellW
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.cellH * 1.7

                visible: Music.da
                spacing: Theme.cellW

                Line {
                    width: Theme.cellW * 2
                    text: Music.spielt ? Icons.play : Icons.pause
                    color: Theme.readable(Theme.accent, Theme.bg)
                }

                Line {
                    width: root.boxW * 0.28
                    elide: Text.ElideRight
                    text: Music.beschriftung
                    color: Theme.fg
                }

                Line {
                    width: Theme.cellW * 6
                    horizontalAlignment: Text.AlignRight
                    text: MediaService.zeit(Music.stelle)
                    color: Theme.muted
                }

                LevelBar {
                    anchors.verticalCenter: parent.verticalCenter

                    cells: 34
                    value: Math.round(Music.stelle)
                    maximum: Math.max(1, Math.round(Music.laenge))
                    interactive: Music.spulbar
                    onMoved: v => Music.spulen(v)
                }

                Line {
                    width: Theme.cellW * 6
                    text: MediaService.zeit(Music.laenge)
                    color: Theme.muted
                }

                Line {
                    width: Theme.cellW * 4
                    text: "  VOL"
                    color: Theme.muted
                }

                LevelBar {
                    anchors.verticalCenter: parent.verticalCenter

                    cells: 10
                    value: Math.round(Music.lautstaerke * 100)
                    maximum: 100
                    fillColor: Theme.green
                    interactive: Music.lautstaerkeGeht
                    onMoved: v => Music.setzeLautstaerke(v / 100)
                }
            }

            Line {
                anchors.left: parent.left
                anchors.leftMargin: Theme.cellW
                anchors.right: parent.right
                // Platz fuer die Anheft-Marke rechts daneben.
                anchors.rightMargin: Theme.cellW * 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.cellH / 2

                // Mit Breite und `elide`: der Hinweis lief vorher rechts aus
                // dem Kasten heraus, weil ein Text ohne Breite so lang wird,
                // wie er will.
                elide: Text.ElideRight

                text: {
                    if (root.typing)
                        return "Suche: " + root.query + "█   Enter sucht · Esc verwirft";
                    if (root.loeschFrage >= 0)
                        return "„" + (root.shown[root.loeschFrage]?.titel ?? "") + "“ aus der Playlist entfernen? Noch einmal D drückt zu.";
                    if (Music.aktion !== "")
                        return Music.aktion;
                    return "↑↓ wählen · Enter spielt · / suchen · A hinzufügen · D entfernen · S Zufall" + (Music.shuffle ? " [an]" : "") + " · +/− Ton · Esc zurück";
                }
                color: root.loeschFrage >= 0 ? Theme.yellow : (Music.aktion.indexOf("ging nicht") === 0 ? Theme.red : Theme.muted)
            }

            // Angeheftet gibt das Fenster die Tastatur ab -- das Loesen muss
            // also mit der Maus gehen.
            ActionButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.cellW
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.cellH / 2

                text: root.pinned ? "Angeheftet" : "Anheften"
                tone: root.pinned ? "primary" : "secondary"
                compact: true
                onTriggered: root.anheften()
            }
        }
    }

    // Wieviele Titel oben abgeschnitten werden, damit die Auswahl im Bild
    // bleibt. Kein Flickable: bei 400 Titeln waeren das 400 gebaute Zeilen,
    // von denen 22 zu sehen sind.
    readonly property int fenster: {
        if (root.trackSel < root.sicht - 2)
            return 0;
        return Math.min(root.trackSel - root.sicht + 3, Math.max(0, root.shown.length - root.sicht));
    }
}
