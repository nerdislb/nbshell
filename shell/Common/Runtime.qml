pragma Singleton

import QtQuick
import Quickshell

// Fluechtiger Zustand, den mehrere Fenster teilen -- alles, was NICHT in die
// Config gehoert, weil es einen Neustart nicht ueberleben soll.
//
// Die Leiste gibt es einmal pro Bildschirm; ohne eine gemeinsame Stelle wuerde
// ein Tastenkuerzel nur die Insel auf einem davon aufklappen.
Singleton {
    id: root

    property bool islandOpen: false

    // Der Themewaehler laesst sich auch per Tastenkuerzel oeffnen, nicht nur
    // durch einen Klick auf die Zelle.
    property bool themePickerOpen: false
    property bool audioPanelOpen: false
    property bool audioToolsOpen: false
    property bool controlOpen: false
    property bool launcherOpen: false

    // Womit der Starter aufgeht. Leer heisst: mit nichts, also mit den
    // Anwendungen. ">" oeffnet ihn direkt als Befehlspalette, "!" nur mit
    // Anwendungen -- dafuer gibt es eigene Tastenkuerzel, damit man den
    // Praefix nicht jedes Mal tippt.
    property string launcherPrefill: ""
    property bool notifyOpen: false
    property bool notificationCenterOpen: false
    property bool powerOpen: false
    property bool clipOpen: false
    property bool procsOpen: false
    property bool captureOpen: false
    property bool settingsOpen: false
    property bool modulesOpen: false
    property bool wallpaperOpen: false
    property bool calendarOpen: false
    property bool todoOpen: false
    property bool habitsOpen: false
    property bool qrOpen: false
    property bool speedOpen: false
    property bool musicOpen: false
    property bool keysOpen: false
    property bool menuOpen: false
    property bool emojiOpen: false
    property bool hubOpen: false
    property bool pluginDeveloperOpen: false

    // Wie viele Popouts gerade offen sind. Die Leiste braucht das: ein
    // Popup-Griff wird vom Kompositor nur erlaubt, wenn die Layer-Flaeche
    // darunter ueberhaupt Tastatur annehmen DARF. Steht sie auf "None", wird
    // der Griff abgelehnt -- und dann erscheint das Popout gar nicht erst.
    property int popoutCount: 0

    // Das gerade offene Bar-Popout -- es darf nur EINS gleichzeitig geben.
    // Oeffnet man ein zweites, schliesst es hierueber das erste; sonst
    // ueberlappen sie sich (niri beendet den Popup-Griff beim Klick daneben
    // nicht selbst). Haelt die Popout-Instanz, nicht nur einen Zaehler.
    property var activePopout: null

    // Wie viele Zellen MIT Popout gerade unter der Maus stehen. Das ist der
    // Vorlauf: die Leiste muss schon Tastatur annehmen DUERFEN, wenn der Klick
    // kommt -- wird das erst beim Oeffnen umgestellt, ist der Griff im selben
    // Durchlauf noch abgelehnt und das Popout erscheint gar nicht.
    property int popoutHover: 0

    // Wie viele Leisten unter der Maus stehen. Stille Bausteine (keine
    // Meldungen, keine Aufnahme) zeigen sich nur, solange das der Fall ist.
    property int barHover: 0

    // Ein Popout von aussen aufklappen -- gedacht fuer Plugins, die kein
    // eigenes IPC-Ziel haben. Der Name ist der des Bausteins, der Zaehler
    // loest aus: eine blosse Zeichenkette meldete beim zweiten Mal desselben
    // Namens keine Aenderung mehr.
    property string popoutTarget: ""
    property int popoutToken: 0

    function requestPopout(name) {
        popoutTarget = name;
        popoutToken += 1;
    }

    // Hochgezaehlt, wenn alle Popouts zugehen sollen -- Esc auf der Leiste,
    // Fensterwechsel in niri. Bewusst eine Property und KEIN Signal: ein
    // `signal closeAll` auf einem Singleton kam bei den Zellen nicht an, eine
    // Aenderungsmeldung dagegen zuverlaessig.
    property int closeToken: 0

    function closeAll() {
        closeToken += 1;
    }
}
