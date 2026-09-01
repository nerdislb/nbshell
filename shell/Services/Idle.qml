pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Common

// Was passiert, wenn niemand mehr etwas tut.
//
// Bis hierher passierte: nichts. Der Bildschirm blieb an, locked wurde nie --
// auf einem Geraet, das in eine Tasche wandert, ist das die groesste Luecke,
// die der Blick in Omarchys Plugin-Katalog zutage gefoerdert hat.
//
// Gebraucht wird dafuer KEIN Zusatzprogramm. Quickshell spricht das
// standard Wayland `ext-idle-notify` protocol directly (`IdleMonitor`).
// swayidle oder hypridle waeren ein zweiter Daemon mit einer zweiten
// Konfiguration, die man vergisst, wenn man hier etwas aendert.
//
// Drei Stufen, jede mit eigener Frist:
//
//   dimmen      der Bildschirm wird dunkler, aber man sieht noch alles.
//               Ein Tastendruck holt die alte Helligkeit zurueck.
//   ausschalten DPMS aus. Umbriel wakes outputs on the next input event.
//               wieder ein.
//   sperren     `lockCommand` -- derselbe, den auch das Sitzungsmenue nimmt.
//
// `respectInhibitors` ist an: ein Programm, das eine Sperre anfordert (jeder
// Videoplayer tut das), haelt alle drei Stufen an. Ohne das ginge der
// Bildschirm mitten im Film aus, und man lernt, die ganze Sache abzuschalten.
Singleton {
    id: root

    readonly property bool enabled: Config.value("idle", true)

    // Fristen in Sekunden. Die Reihenfolge wird nicht erzwungen -- wer lieber
    // sofort sperrt und nie dimmt, setzt die Fristen entsprechend.
    // Der Bildschirmschoner kommt ZUERST -- er ist der freundlichste Schritt:
    // man sieht sofort, dass der Rechner sich langweilt, und ein Tastendruck
    // holt alles zurueck. Erst danach wird gedimmt und abgeschaltet.
    readonly property int saverAfter: Config.value("idleSaver", 180)
    readonly property int dimAfter: Config.value("idleDim", 240)
    readonly property int offAfter: Config.value("idleScreenOff", 600)
    readonly property int lockAfter: Config.value("idleLock", 900)

    // Wie dunkel gedimmt wird, in Prozent der aktuellen Helligkeit.
    readonly property int dimTo: Config.value("idleDimPercent", 20)

    // ── Wachhalten ───────────────────────────────────────────────────────
    //
    // Der Knopf in der Leiste. Steht er an, passiert gar nichts mehr -- kein
    // Dimmen, kein Ausschalten, kein Sperren.
    //
    // Bewusst in der Config und nicht nur im Speicher: wer den Rechner
    // wachhaelt, weil ein langer Lauf durchgeht, will nicht, dass ein
    // `install.sh` das stillschweigend zuruecknimmt. Vergessen kann man ihn
    // trotzdem nicht -- die Zelle steht sichtbar in der Leiste, solange er an
    // ist, und zwar auch in der zugeklappten Insel.
    readonly property bool caffeine: Config.value("caffeine", false)

    function setCaffeine(value) {
        Config.set("caffeine", value === true);
    }

    function toggleCaffeine() {
        root.setCaffeine(!root.caffeine);
        return root.caffeine;
    }

    // Wer wachhaelt oder die Automatik abschaltet, will den Schoner sofort weg.
    onArmedChanged: {
        if (!root.armed)
            root.stopSaver();
    }

    // Nur wahr, wenn wirklich etwas passieren soll.
    readonly property bool armed: root.enabled && !root.caffeine

    // Zum Anzeigen: wie weit ist es gerade?
    readonly property bool dimmed: root.dimmedBrightness >= 0
    property int dimmedBrightness: -1

    readonly property string state: {
        if (!root.enabled)
            return "off";
        if (root.caffeine)
            return "wach";
        if (saver.running)
            return "screen saver";
        if (lockMonitor.isIdle)
            return "locked";
        if (offMonitor.isIdle)
            return "Screen off";
        if (dimMonitor.isIdle)
            return "dimmed";
        return "waiting";
    }

    // ── Dimmen ───────────────────────────────────────────────────────────
    //
    // Die alte Helligkeit wird gemerkt, nicht ausgerechnet: nach dem Aufwachen
    // soll genau der Wert zurueckkommen, der vorher stand. -1 heisst "nichts
    // gemerkt", damit ein zweites Dimmen nicht den bereits gedimmten Wert als
    // Ausgangswert nimmt und der Bildschirm bei jedem Zyklus dunkler wird.
    function dim() {
        if (!Brightness.available || root.dimmedBrightness >= 0)
            return;
        root.dimmedBrightness = Brightness.percent;
        Brightness.set(Math.max(1, Math.round(Brightness.percent * root.dimTo / 100)));
    }

    function undim() {
        if (root.dimmedBrightness < 0)
            return;
        Brightness.set(root.dimmedBrightness);
        root.dimmedBrightness = -1;
    }

    // ── Bildschirmschoner ────────────────────────────────────────────────
    //
    // Ein Vollbildterminal mit dem nbshell-Schriftzug, nach Omarchys Vorbild.
    // Beendet wird er auf zwei Wegen: das Skript steigt bei Tastendruck und
    // Mausbewegung selbst aus, und WIR schicken ihm ein SIGTERM, sobald der
    // Leerlauf endet. Das zweite ist noetig, weil eine Mausbewegung ausserhalb
    // des Terminalfensters dort nie ankommt.
    // Das Startskript, nicht das Python direkt: es entscheidet, ob TTE da ist
    // (39 Effekte, dasselbe Programm wie bei Omarchy) oder ob unsere zehn
    // eigenen laufen.
    readonly property string saverScript: Qt.resolvedUrl("../scripts/screensaver.sh").toString().replace("file://", "")
    readonly property string terminal: Config.value("terminal", "") || Quickshell.env("TERMINAL") || "ghostty"

    // The title must exist when the window opens because Umbriel evaluates its
    // Fensterregel aus, sobald das Fenster auftaucht -- zu dem Zeitpunkt hiess
    // es noch "ghostty", und `open-fullscreen` griff nie. Dass das Skript den
    // Titel spaeter selbst setzt, kam fuer die Regel zu spaet; deshalb sagt es
    // ihn dem Terminal jetzt schon auf der Befehlszeile.
    //
    // `--fullscreen` obendrauf, weil es der kuerzeste Weg ist und nicht von
    // einer Regel in einer fremden Datei abhaengt. Terminals, die die Flaggen
    // do not understand them simply receive no extra flags.
    readonly property bool ghostty: root.terminal.indexOf("ghostty") >= 0

    function startSaver() {
        if (saver.running)
            return;
        const vorn = root.ghostty ? [root.terminal, "--title=nbshell-screensaver", "--fullscreen=true"] : [root.terminal];
        saver.command = vorn.concat(["-e", "bash", root.saverScript]);
        saver.running = true;
    }

    function stopSaver() {
        if (saver.running)
            saver.running = false;
    }

    Process {
        id: saver
    }

    IdleMonitor {
        id: saverMonitor

        enabled: root.armed && root.saverAfter > 0
        timeout: root.saverAfter
        respectInhibitors: true

        onIsIdleChanged: {
            if (saverMonitor.isIdle)
                root.startSaver();
            else
                root.stopSaver();
        }
    }

    IdleMonitor {
        id: dimMonitor

        enabled: root.armed && root.dimAfter > 0
        timeout: root.dimAfter
        respectInhibitors: true

        onIsIdleChanged: {
            if (dimMonitor.isIdle)
                root.dim();
            else
                root.undim();
        }
    }

    IdleMonitor {
        id: offMonitor

        enabled: root.armed && root.offAfter > 0
        timeout: root.offAfter
        respectInhibitors: true

        // Umbriel wakes outputs on the next input event.
        onIsIdleChanged: {
            if (!offMonitor.isIdle)
                return;
            Quickshell.execDetached(["umbriel", "msg", "dpms-off"]);
        }
    }

    IdleMonitor {
        id: lockMonitor

        enabled: root.armed && root.lockAfter > 0
        timeout: root.lockAfter
        respectInhibitors: true

        onIsIdleChanged: {
            if (lockMonitor.isIdle)
                Session.run("lock");
        }
    }
}
