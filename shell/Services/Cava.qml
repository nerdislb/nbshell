pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Was aus den Lautsprechern kommt, als Balken.
//
// Gemessen wird NICHT von uns. `cava` (Console-based Audio Visualizer) macht
// genau das seit Jahren: es haengt sich an den Monitor der Ausgabe, rechnet die
// Fouriertransformation und glaettet das Ergebnis so, dass es fuers Auge
// stimmt. Ein Nachbau in QML waere ein Wochenendprojekt mit schlechterem
// Ergebnis -- und die Shell hat keinen Zugriff auf den Audiostrom.
//
// Der Trick ist cavas Rohausgabe: `output_method = raw` schreibt je Bild eine
// Zeile Zahlen auf die Standardausgabe, statt selbst zu zeichnen.
//
//   3;2;4;1;3;4;4;3;1;4;2;3;
//
// Zwoelf Werte von 0 bis 7, durch Semikola getrennt -- genau das Format, das
// ein `SplitParser` Zeile fuer Zeile hereinreicht. Nachgemessen, bevor hier
// etwas gebaut wurde: mit laufender Musik bewegen sich die Zahlen, ueber
// Bluetooth genauso wie ueber die eingebauten Lautsprecher.
//
// GEMESSEN WIRD NUR, WENN ETWAS SPIELT. Ein Prozess, der dreissigmal je
// Sekunde eine Zeile schreibt, waere den ganzen Tag ueber genau die Sorte
// Hintergrundarbeit, die anderswo in dieser Shell gerade herausgeflogen ist.
// Und ohne Ton haette er ohnehin nur Nullen zu melden.
Singleton {
    id: root

    readonly property bool enabled: Config.value("visualizer", true)

    // Wie viele Balken. Mehr sieht feiner aus und braucht mehr Platz in der
    // Leiste; zwoelf sind etwa so breit wie eine Uhrzeit.
    readonly property int bars: Config.value("visualizerBars", 12)

    // Der Ausschlag je Balken, 0 bis 7 -- so viele Stufen hat die Blockschrift
    // (▁▂▃▄▅▆▇█), also wird gar nicht erst feiner gerechnet.
    property var levels: []

    // Laeuft gerade Ton? Das beantwortet MPRIS, nicht der Ton selbst: ein Blick
    // auf den Pegel wuerde bedeuten, dauernd zu messen, was wir ja vermeiden.
    readonly property bool wanted: root.enabled && MediaService.playing

    readonly property string configPath: Config.configDir + "/cava.conf"

    // Die Konfiguration wird geschrieben, nicht mitgeliefert: `bars` kommt aus
    // unserer Config, und cava liest sie nur aus einer Datei.
    readonly property string configText: "# Von nbshell geschrieben (Services/Cava.qml) -- Aenderungen hier\n" + "# ueberlebt den naechsten Start nicht. bars: nbshell set visualizerBars <n>\n" + "[general]\n" + "framerate = 30\n" + "bars = " + root.bars + "\n" + "autosens = 1\n" + "[input]\n" + "method = pulse\n" + "source = auto\n" + "[output]\n" + "method = raw\n" + "raw_target = /dev/stdout\n" + "data_format = ascii\n" + "ascii_max_range = 7\n"

    onConfigTextChanged: conf.setText(root.configText)

    Component.onCompleted: conf.setText(root.configText)

    FileView {
        id: conf

        path: root.configPath
        printErrors: false
        atomicWrites: true
    }

    Process {
        id: cava

        // Erst starten, wenn die Konfiguration steht -- cava liest sie einmal
        // beim Start und nie wieder.
        running: root.wanted && conf.loaded
        command: ["cava", "-p", root.configPath]

        stdout: SplitParser {
            onRead: zeile => {
                const teile = String(zeile).split(";");
                const werte = [];
                for (const s of teile) {
                    if (s === "")
                        continue;          // die Zeile endet auf ein Semikolon
                    werte.push(parseInt(s, 10) || 0);
                }
                if (werte.length > 0)
                    root.levels = werte;
            }
        }

        // Beim Aufhoeren alles auf null, sonst bliebe der letzte Ausschlag als
        // Standbild in der Leiste stehen.
        onRunningChanged: if (!cava.running)
            root.levels = []
    }
}
