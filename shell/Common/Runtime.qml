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
    property bool controlOpen: false
    property bool launcherOpen: false
    property bool notifyOpen: false
    property bool powerOpen: false
    property bool clipOpen: false
    property bool procsOpen: false
    property bool captureOpen: false
    property bool settingsOpen: false

    // Wie viele Popouts gerade offen sind. Die Leiste braucht das: ein
    // Popup-Griff wird vom Kompositor nur erlaubt, wenn die Layer-Flaeche
    // darunter ueberhaupt Tastatur annehmen DARF. Steht sie auf "None", wird
    // der Griff abgelehnt -- und dann erscheint das Popout gar nicht erst.
    property int popoutCount: 0

    // Wie viele Zellen MIT Popout gerade unter der Maus stehen. Das ist der
    // Vorlauf: die Leiste muss schon Tastatur annehmen DUERFEN, wenn der Klick
    // kommt -- wird das erst beim Oeffnen umgestellt, ist der Griff im selben
    // Durchlauf noch abgelehnt und das Popout erscheint gar nicht.
    property int popoutHover: 0
}
