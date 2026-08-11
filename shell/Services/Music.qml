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

    readonly property var current: root.position >= 0 && root.position < root.queue.length ? root.queue[root.position] : null

    property bool running: false
    property string status: ""

    // Startlautstaerke von mpv. Nicht die Systemlautstaerke -- die bleibt, wo
    // sie steht. 100 waere das mpv-Standardmass und beim ersten Titel ein
    // Schreck.
    readonly property int volume: Config.value("musicVolume", 60)

    // ── mpv ──────────────────────────────────────────────────────────────

    function ensure() {
        if (daemon.running)
            return;
        daemon.command = ["mpv", "--idle=yes", "--no-video", "--no-terminal", "--force-window=no",
            // Nur Ton holen, nicht das Video dazu -- spart bei jedem Titel ein
            // Vielfaches an Daten.
            "--ytdl-format=bestaudio", "--volume=" + root.volume, "--input-ipc-server=" + root.socketPath];
        daemon.running = true;
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

    function spiele(titel) {
        root.queue = [titel];
        root.position = 0;
        root.send(["loadfile", root.url(titel), "replace"]);
        root.status = titel.titel;
    }

    function spieleListe(titel, ab) {
        if (!titel || titel.length === 0)
            return;
        const start = ab ?? 0;
        root.queue = titel;
        root.position = start;
        root.send(["loadfile", root.url(titel[start]), "replace"]);
        for (let i = start + 1; i < titel.length; i++)
            root.send(["loadfile", root.url(titel[i]), "append"]);
        root.status = titel.length + " Titel";
    }

    function haengeAn(titel) {
        root.queue = root.queue.concat([titel]);
        root.send(["loadfile", root.url(titel), "append"]);
        root.status = "angehaengt: " + titel.titel;
    }

    function leeren() {
        root.send(["playlist-clear"]);
        root.send(["stop"]);
        root.queue = [];
        root.position = -1;
    }

    Process {
        id: daemon

        // Stirbt mpv (Absturz, `pkill`), faellt `running` zurueck -- der
        // naechste Titel startet es dann einfach neu.
        onExited: root.running = false
        onStarted: root.running = true
    }

    // Verbunden wird nicht per Bindung, sondern auf Zuruf: schlaegt ein
    // Versuch fehl, setzt Quickshell `connected` selbst zurueck -- eine Bindung
    // waere danach kaputt und der zweite Versuch fiele aus.
    Socket {
        id: sock

        path: root.socketPath

        onConnectedChanged: if (sock.connected)
            root.nachreichen()
    }

    Timer {
        interval: 300
        repeat: true
        running: root.running && !sock.connected
        onTriggered: sock.connected = true
    }
}
