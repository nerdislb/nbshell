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
}
