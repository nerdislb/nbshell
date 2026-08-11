pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// Was passiert, wenn niemand mehr etwas tut.
//
// Bis hierher passierte: nichts. Der Bildschirm blieb an, gesperrt wurde nie --
// auf einem Geraet, das in eine Tasche wandert, ist das die groesste Luecke,
// die der Blick in Omarchys Plugin-Katalog zutage gefoerdert hat.
//
// Gebraucht wird dafuer KEIN Zusatzprogramm. Quickshell spricht das
// Wayland-Protokoll `ext-idle-notify` selbst (`IdleMonitor`), und niri kann es.
// swayidle oder hypridle waeren ein zweiter Daemon mit einer zweiten
// Konfiguration, die man vergisst, wenn man hier etwas aendert.
//
// Drei Stufen, jede mit eigener Frist:
//
//   dimmen      der Bildschirm wird dunkler, aber man sieht noch alles.
//               Ein Tastendruck holt die alte Helligkeit zurueck.
//   ausschalten DPMS aus. niri schaltet bei der naechsten Eingabe selbst
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

    // Nur wahr, wenn wirklich etwas passieren soll.
    readonly property bool armed: root.enabled && !root.caffeine

    // Zum Anzeigen: wie weit ist es gerade?
    readonly property bool dimmed: root.dimmedBrightness >= 0
    property int dimmedBrightness: -1

    readonly property string state: {
        if (!root.enabled)
            return "aus";
        if (root.caffeine)
            return "wach";
        if (lockMonitor.isIdle)
            return "gesperrt";
        if (offMonitor.isIdle)
            return "Bildschirm aus";
        if (dimMonitor.isIdle)
            return "gedimmt";
        return "wartet";
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

        // Eingeschaltet wird nicht von hier: niri weckt die Bildschirme bei
        // der naechsten Eingabe selbst. Ein `power-on-monitors` von uns kaeme
        // entweder zu frueh (waehrend noch niemand etwas tut) oder zu spaet.
        onIsIdleChanged: {
            if (offMonitor.isIdle)
                Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"]);
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
