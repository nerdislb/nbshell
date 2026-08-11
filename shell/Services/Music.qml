pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// YouTube Music: was gespielt wird.
//
// Dieser Dienst ist kleiner, als man erwarten wuerde -- und zwar aus einem
// guten Grund. Er tut GENAU eines: Titel in mpv laden. Alles andere ist schon
// da:
//
//   Zustand    (spielt? Titel? Interpret? Position?)  -> MediaService, ueber
//              MPRIS. mpv-mpris liegt in /etc/mpv/scripts/, also meldet sich
//              jede mpv-Instanz von selbst an -- ohne Zutun, ohne Flagge.
//   Steuerung  (Pause, weiter, zurueck)               -> MediaService, ueber
//              dieselbe Schnittstelle wie jeder andere Spieler. Auch die
//              Medientasten und die OSD-Einblendung greifen damit schon.
//   Mediathek  (Playlists, Suche, Bearbeiten)         -> scripts/ytm.py
//
// Uebrig bleibt das eine, was MPRIS nicht kann: eine Adresse abspielen. Dafuer
// laeuft mpv im Leerlauf mit einem Befehlssocket, und hier werden Zeilen
// hineingeschrieben.
//
// mpv wird ERST BEIM ERSTEN TITEL gestartet, nicht beim Anmelden der Sitzung.
// Ein stiller Abspieler, der den ganzen Tag mitlaeuft, waere genau die Art
// Hintergrundarbeit, die anderswo in dieser Shell gerade herausgeflogen ist.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/ytm.py").toString().replace("file://", "")
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nbshell-mpv.sock"

    // Was gerade in der Warteschlange steht. mpv fuehrt seine eigene Liste --
    // die hier ist die, die das Fenster anzeigt, samt Interpret und Album, die
    // mpv gar nicht kennt.
    property var queue: []
    property int position: -1

    // Welcher Titel gerade laeuft. Die Stelle in der Warteschlange allein
    // reicht nicht: mpv rueckt selbst weiter, wenn ein Stueck zu Ende ist, und
    // davon erfaehrt `position` nichts -- die Markierung im Fenster bliebe auf
    // dem ersten Titel stehen. Deshalb zuerst ueber den Namen, den MPRIS
    // meldet, und nur ersatzweise ueber die Stelle.
    readonly property var current: {
        const gespielt = MediaService.title;
        if (gespielt !== "")
            // Meldet MPRIS einen Titel, gilt der -- und nur der. Der Rueckgriff
            // auf die gemerkte Stelle waere hier schaedlich: sie steht immer
            // noch auf dem ersten Stueck, und das Fenster spraenge bei jedem
            // Wechsel dorthin statt zum laufenden.
            return root.queue.find(t => t.titel === gespielt) ?? null;
        return root.position >= 0 && root.position < root.queue.length ? root.queue[root.position] : null;
    }

    // Laeuft ein Abspieler? Das beantwortet der Socket, nicht ein Prozessobjekt:
    // nach einem Neustart der Shell ist mpv noch da, der Process waere neu.
    readonly property bool running: sock.connected
    property bool starting: false

    property string status: ""

    // Startlautstaerke von mpv. Nicht die Systemlautstaerke -- die bleibt, wo
    // sie steht. 100 waere das mpv-Standardmass und beim ersten Titel ein
    // Schreck.
    readonly property int volume: Config.value("musicVolume", 60)

    // ── Mediathek ────────────────────────────────────────────────────────
    //
    // Geladen wird auf Zuruf, nicht im Hintergrund: die Playlists holt das
    // Fenster beim Oeffnen, die Titel beim Anklicken einer Playlist. Ein
    // Abgleich, der staendig mitlaeuft, waere fuer eine Liste, die sich
    // hoechstens taeglich aendert, die falsche Rechnung.

    property var playlists: []
    property var tracks: []
    property string listName: ""
    property string listId: ""

    property var results: []
    property string query: ""

    property bool busy: false
    property string error: ""

    // Was im rechten Feld steht: Titel einer Playlist oder Suchtreffer.
    readonly property var shown: root.query !== "" ? root.results : root.tracks

    function auswerten(text, dann) {
        root.busy = false;
        try {
            const d = JSON.parse(text);
            if (!d.ok) {
                root.error = String(d.grund);
                return;
            }
            root.error = "";
            dann(d);
        } catch (e) {
            root.error = "Antwort unlesbar";
        }
    }

    function ladePlaylists() {
        root.cache = ({});
        root.busy = true;
        listen.command = ["python3", root.script, "playlists"];
        listen.running = true;
    }

    // Schon Geholtes wird gemerkt. Beim Blaettern durch die Playlists wird
    // sonst dieselbe Liste dreimal am Nachmittag geholt -- eine Playlist
    // aendert sich nicht, waehrend man an ihr vorbeiscrollt. F5 wirft den
    // Speicher weg.
    property var cache: ({})

    // Welche Playlist zuletzt GEWUENSCHT wurde, und welche gerade GEHOLT wird.
    // Beim schnellen Blaettern laeuft die Antwort der Auswahl hinterher: ohne
    // diesen Vergleich landen die Titel der vorletzten Playlist in einer
    // Ansicht, die laengst eine andere zeigt.
    property string wunschId: ""
    property string holeId: ""

    function ladePlaylist(id, name) {
        root.query = "";
        root.listId = id;
        root.listName = name ?? "";
        root.wunschId = id;

        if (root.cache[id]) {
            root.tracks = root.cache[id];
            root.busy = false;
            return;
        }
        if (titel.running)
            return;          // laeuft noch -- danach wird der Wunsch nachgeholt
        root.hole(id);
    }

    function hole(id) {
        root.busy = true;
        root.holeId = id;
        titel.command = ["python3", root.script, "playlist", id];
        titel.running = true;
    }

    function suche(text) {
        if (text === "") {
            root.query = "";
            return;
        }
        root.busy = true;
        root.query = text;
        sucher.command = ["python3", root.script, "search", text];
        sucher.running = true;
    }

    Process {
        id: listen

        stdout: StdioCollector {
            onStreamFinished: root.auswerten(text, d => root.playlists = d.playlists ?? [])
        }
    }

    Process {
        id: titel

        stdout: StdioCollector {
            onStreamFinished: root.auswerten(text, d => {
                const liste = d.titel ?? [];
                const c = root.cache;
                c[root.holeId] = liste;
                root.cache = c;
                // Nur anzeigen, wenn die Antwort noch zu dem gehoert, was
                // gerade ausgewaehlt ist.
                if (root.holeId === root.wunschId) {
                    root.tracks = liste;
                    if (d.name)
                        root.listName = d.name;
                }
            })
        }

        // Beim Blaettern staut sich hoechstens ein Wunsch -- der wird jetzt
        // geholt. Die uebersprungenen dazwischen interessieren niemanden mehr.
        onRunningChanged: {
            if (titel.running || root.wunschId === "" || root.wunschId === root.holeId)
                return;
            if (root.cache[root.wunschId])
                root.tracks = root.cache[root.wunschId];
            else
                root.hole(root.wunschId);
        }
    }

    Process {
        id: sucher

        stdout: StdioCollector {
            onStreamFinished: root.auswerten(text, d => root.results = d.treffer ?? [])
        }
    }

    // ── Playlists bearbeiten ─────────────────────────────────────────────
    //
    // Nach jeder Aenderung wird der Zwischenspeicher DIESER Playlist verworfen
    // und sie neu geholt: die Antwort von YouTube enthaelt neue `setVideoId`s,
    // und mit den alten schluege das naechste Entfernen fehl.

    property string aktion: ""

    function entfernen(playlistId, titel) {
        if (!playlistId || !titel || !titel.slot) {
            root.aktion = "geht hier nicht — kein Platz in einer Playlist";
            return;
        }
        root.aktion = "entferne " + titel.titel + " …";
        bearbeiter.command = ["python3", root.script, "remove", playlistId, titel.id, titel.slot];
        root.aendert = playlistId;
        bearbeiter.running = true;
    }

    function hinzufuegen(playlistId, titel) {
        if (!playlistId || !titel) {
            root.aktion = "wohin?";
            return;
        }
        root.aktion = "lege " + titel.titel + " ab …";
        bearbeiter.command = ["python3", root.script, "add", playlistId, titel.id];
        root.aendert = playlistId;
        bearbeiter.running = true;
    }

    property string aendert: ""

    Process {
        id: bearbeiter

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.aktion = d.ok ? "erledigt" : ("ging nicht: " + d.grund);
                } catch (e) {
                    root.aktion = "Antwort unlesbar";
                }
                if (root.aendert !== "") {
                    const c = root.cache;
                    delete c[root.aendert];
                    root.cache = c;
                    if (root.listId === root.aendert)
                        root.hole(root.aendert);
                    root.aendert = "";
                }
                quittung.restart();
            }
        }
    }

    Timer {
        id: quittung

        interval: 4000
        onTriggered: root.aktion = ""
    }

    // ── mpv ──────────────────────────────────────────────────────────────

    // mpv laeuft LOSGELOEST, nicht als Kind der Shell.
    //
    // Als `Process` war es eines -- und starb mit jedem Neuladen der Shell
    // mitten im Titel. Bei einer Shell, die man beim Basteln zwanzigmal am Tag
    // neu startet, ist das der Unterschied zwischen brauchbar und aergerlich.
    // Losgeloest spielt es weiter, und die Shell findet es nach dem Neustart
    // ueber den Socket wieder: Musik laeuft durch, die Leiste hat sie wieder.
    function ensure() {
        if (sock.connected || root.starting)
            return;
        root.starting = true;
        // `systemd-run --scope` statt `setsid`: die Shell laeuft als
        // systemd-Dienst, und beim Neustart raeumt systemd die GANZE
        // Prozessgruppe des Dienstes ab -- eine eigene Sitzung allein rettet
        // mpv davor nicht, es haengt weiter in derselben cgroup. Ein eigener
        // Scope loest es heraus; --collect raeumt ihn auf, wenn mpv endet.
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "mpv", "--idle=yes", "--no-video", "--no-terminal", "--force-window=no",
            // Nur Ton holen, nicht das Video dazu -- spart bei jedem Titel ein
            // Vielfaches an Daten.
            "--ytdl-format=bestaudio", "--volume=" + root.volume, "--input-ipc-server=" + root.socketPath]);
    }

    // Zwischen „mpv gestartet" und „Socket nimmt Verbindungen an" liegen ein
    // paar hundert Millisekunden -- der allererste Titel faellt sonst in ein
    // Loch, und zwar genau einmal pro Sitzung, was die schlimmste Sorte Fehler
    // ist. Deshalb werden Befehle gesammelt, solange niemand zuhoert.
    property var wartend: []

    function send(cmd) {
        root.ensure();
        const zeile = JSON.stringify({
            command: cmd
        }) + "\n";
        if (sock.connected) {
            sock.write(zeile);
            return;
        }
        root.wartend = root.wartend.concat([zeile]);
    }

    function nachreichen() {
        for (const zeile of root.wartend)
            sock.write(zeile);
        root.wartend = [];
    }

    // ── Abspielen ────────────────────────────────────────────────────────
    //
    // `spiele` ersetzt die Warteschlange, `haengeAn` erweitert sie. Beides
    // schickt dieselbe Adresse: music.youtube.com/watch?v=… Was daraus wird,
    // erledigt yt-dlp in mpv.

    function url(titel) {
        return "https://music.youtube.com/watch?v=" + titel.id;
    }

    // `pause` ist in mpv eine EIGENSCHAFT DES SPIELERS, nicht der Datei: wer
    // einmal pausiert hat, bei dem laedt auch jeder naechste Titel pausiert
    // nach -- man klickt auf ein Stueck und es passiert scheinbar nichts.
    function losspielen() {
        root.send(["set_property", "pause", false]);
    }

    function spiele(titel) {
        root.queue = [titel];
        root.position = 0;
        root.send(["loadfile", root.url(titel), "replace"]);
        root.losspielen();
        root.merken();
        root.status = titel.titel;
    }

    // ── Zufall ───────────────────────────────────────────────────────────
    //
    // Der angeklickte Titel bleibt der erste. Wer auf einem Stueck Enter
    // drueckt, will DIESES hoeren -- gewuerfelt wird, was danach kommt.
    // Gemischt wird hier und nicht in mpv (`--shuffle`), weil die Reihenfolge
    // sonst nur mpv kennt und die Warteschlange im Fenster etwas anderes
    // zeigte als das, was spielt.
    readonly property bool shuffle: Config.value("musicShuffle", false)

    function toggleShuffle() {
        Config.set("musicShuffle", !root.shuffle);
        return !root.shuffle;
    }

    function mischen(liste) {
        // Fisher-Yates: jede Reihenfolge gleich wahrscheinlich. Ein
        // `sort(() => Math.random() - 0.5)` waere kuerzer und verzerrt.
        const a = liste.slice();
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
    }

    function spieleListe(titel, ab) {
        if (!titel || titel.length === 0)
            return;
        const start = ab ?? 0;
        let reihe = titel;
        if (root.shuffle) {
            const erster = titel[start];
            reihe = [erster].concat(root.mischen(titel.filter((t, i) => i !== start)));
        } else if (start > 0) {
            reihe = titel.slice(start);
        }
        root.queue = reihe;
        root.position = 0;
        root.send(["loadfile", root.url(reihe[0]), "replace"]);
        for (let i = 1; i < reihe.length; i++)
            root.send(["loadfile", root.url(reihe[i]), "append"]);
        root.losspielen();
        root.merken();
        root.status = reihe.length + " Titel" + (root.shuffle ? ", gemischt" : "");
    }

    function haengeAn(titel) {
        root.queue = root.queue.concat([titel]);
        root.send(["loadfile", root.url(titel), "append"]);
        root.merken();
        root.status = "angehaengt: " + titel.titel;
    }

    function leeren() {
        root.send(["playlist-clear"]);
        root.send(["stop"]);
        root.queue = [];
        root.position = -1;
        root.merken();
    }

    // ── Die Warteschlange ueberlebt den Neustart ─────────────────────────
    //
    // Die Musik lief nach einem Neustart der Shell zwar weiter (mpv haengt in
    // einem eigenen Scope), aber die Liste dazu war weg -- keine Markierung im
    // Fenster, kein Zufallsknopf. Deshalb liegt sie in einer Datei. Klein
    // genug, dass das Schreiben bei jeder Aenderung nicht auffaellt; gelesen
    // wird sie genau einmal, beim Start.
    function merken() {
        queueFile.setText(JSON.stringify({
            "queue": root.queue,
            "position": root.position
        }));
    }

    FileView {
        id: queueFile

        path: Config.configDir + "/queue.json"
        printErrors: false
        atomicWrites: true

        onLoaded: {
            try {
                const d = JSON.parse(queueFile.text());
                root.queue = d.queue ?? [];
                root.position = d.position ?? -1;
            } catch (e) {
                root.queue = [];
            }
        }
    }

    // Verbunden wird nicht per Bindung, sondern auf Zuruf: schlaegt ein
    // Versuch fehl, setzt Quickshell `connected` selbst zurueck -- eine Bindung
    // waere danach kaputt und der zweite Versuch fiele aus.
    Socket {
        id: sock

        path: root.socketPath

        onConnectedChanged: {
            if (!sock.connected)
                return;
            root.starting = false;
            root.nachreichen();
        }


    }

    // Uebernahme nach einem Neustart der Shell: laeuft von vorhin noch ein mpv,
    // wird es wieder angebunden. Gefragt wird zuerst MPRIS -- ein blindes
    // Verbinden auf einen Socket, den es nicht gibt, waere bei jedem Start eine
    // Fehlzeile im Journal.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            if (sock.connected)
                return;
            const meins = MediaService.players.some(p => String(p?.identity ?? "").toLowerCase().indexOf("mpv") >= 0);
            if (meins)
                sock.connected = true;
        }
    }

    Timer {
        interval: 300
        repeat: true
        running: root.starting && !sock.connected
        // Erst aus, dann an: ein fehlgeschlagener Versuch laesst `connected`
        // gesetzt zuruecke, und ein zweites `= true` waere dann eine Zuweisung
        // desselben Wertes -- also gar kein neuer Versuch. Genau daran ging der
        // erste Ladebefehl verloren.
        onTriggered: {
            sock.connected = false;
            sock.connected = true;
        }
    }
}
