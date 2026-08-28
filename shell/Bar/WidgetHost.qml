import QtQuick
import qs.Common
import qs.Services
import "Widgets"

// Loest einen Namen aus der Config zu einem Baustein auf.
//
// Zwei Quellen: die eingebauten Bausteine stehen unten als Komponenten, alles
// Weitere kommt als QML-Datei aus ~/.config/nbshell/plugins (siehe
// Services/Plugins.qml). Beides sieht von hier aus gleich aus -- ein Plugin ist
// kein Sonderfall, nur eine andere Herkunft.
//
// Der Loader steckt in einer Huelle und bekommt selbst KEINE Groesse: ein
// Loader mit gesetzter Breite skaliert sein Kind auf genau diese Breite, und
// steht die Breite ihrerseits am Kind, fallen beide lautlos auf 0.
Item {
    id: root

    property string widgetName: ""
    property string screenName: ""
    property bool externalPopoutEligible: true

    readonly property var item: loader.item
    readonly property bool hasActivityWidget: Config.collapsedWidgets.indexOf("notifications") >= 0
        || Config.leftWidgets.indexOf("notifications") >= 0
        || Config.centerWidgets.indexOf("notifications") >= 0
        || Config.rightWidgets.indexOf("notifications") >= 0
    readonly property bool redundantClipboard: root.widgetName === "clipboard" && root.hasActivityWidget

    width: item ? item.width : 0
    height: item ? item.height : 0

    // NICHT `item.visible` abfragen: die Sichtbarkeit eines Kindes enthaelt
    // immer die des Elternteils. Die Huelle wuerde also ihre eigene Antwort
    // lesen -- beide blieben fuer immer unsichtbar. Bausteine, die sich
    // ausblenden wollen, setzen deshalb `shown`.
    visible: !!item && item.shown && !root.redundantClipboard && width > 0

    // Leer heisst: eingebaut. Sonst der Pfad zur QML-Datei des Plugins.
    readonly property string pluginSource: Plugins.source(root.widgetName)

    Loader {
        id: loader

        anchors.verticalCenter: parent.verticalCenter
        active: !root.redundantClipboard

        // Nur eines von beiden -- wer `source` setzt, loescht `sourceComponent`
        // und umgekehrt.
        sourceComponent: root.pluginSource === "" ? root.componentFor(root.widgetName) : null
        source: root.pluginSource

        onStatusChanged: if (status === Loader.Error)
            console.warn("nbshell: Baustein", root.widgetName, "failed to load —", sourceComponent ? "eingebaut" : root.pluginSource);
    }

    // Jeder Baustein bekommt seinen Namen angehaengt, damit ein Popout von
    // aussen aufgeklappt werden kann (`nbshell popout wetter`).
    Binding {
        target: root.item
        when: root.item && "widgetId" in root.item
        property: "widgetId"
        value: root.widgetName
        restoreMode: Binding.RestoreNone
    }

    // Bausteine, die wissen wollen, auf welchem Bildschirm sie stehen, kriegen
    // es angehaengt -- so muss der Name hier nicht in jeder Komponente stehen.
    Binding {
        target: root.item
        when: root.item && "output" in root.item
        property: "output"
        value: root.screenName
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "popupOutput" in root.item
        property: "popupOutput"
        value: root.screenName
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.item
        when: root.item && "externalPopoutEligible" in root.item
        property: "externalPopoutEligible"
        value: root.externalPopoutEligible
        restoreMode: Binding.RestoreNone
    }

    function componentFor(name) {
        switch (name) {
        case "clock":
            return clockComponent;
        case "caffeine":
            return caffeineComponent;
        case "nearby":
            return nearbyComponent;
        case "workspaces":
            return workspacesComponent;
        case "window":
            return windowComponent;
        case "battery":
            return batteryComponent;
        case "sys":
            return sysComponent;
        case "layout":
            return layoutComponent;
        case "sep":
            return separatorComponent;
        case "themes":
            return themesComponent;
        case "volume":
            return volumeComponent;
        case "control":
            return controlComponent;
        case "tray":
            return trayComponent;
        case "notifications":
            return notificationsComponent;
        case "media":
            return mediaComponent;
        case "musik":
            return musicControlsComponent;
        case "vis":
            return visualizerComponent;
        case "bongo":
            return bongoComponent;
        case "clipboard":
            // Compatibility alias for configurations created before the
            // notification and clipboard panels were combined.
            return notificationsComponent;
        case "capture":
            return captureComponent;
        case "ai":
            return aiComponent;
        case "updates":
            return updatesComponent;
        case "units":
            return unitsComponent;
        case "todo":
            return todoComponent;
        case "habits":
            return habitsComponent;
        case "kdeconnect":
            return kdeconnectComponent;
        case "tailscale":
            return tailscaleComponent;
        case "whatsapp":
            return whatsappComponent;
        case "pip":
            return zenPipComponent;
        }
        // Kein eingebauter -- dann muss es ein Plugin sein. Ist es das auch
        // nicht, steht ein Name in der Config, den niemand kennt.
        if (Plugins.source(name) === "" && Plugins.scanned)
            console.warn("nbshell: unbekannter Baustein:", name);
        return null;
    }

    Component {
        id: caffeineComponent

        Caffeine {}
    }

    Component {
        id: nearbyComponent

        Nearby {}
    }

    Component {
        id: clockComponent
        Clock {}
    }

    Component {
        id: workspacesComponent
        Workspaces {}
    }

    Component {
        id: windowComponent
        WindowTitle {}
    }

    Component {
        id: batteryComponent
        Battery {}
    }

    Component {
        id: sysComponent
        Sys {}
    }

    Component {
        id: layoutComponent
        Layout {}
    }

    Component {
        id: separatorComponent
        Separator {}
    }

    Component {
        id: themesComponent
        Themes {}
    }

    Component {
        id: volumeComponent
        Volume {}
    }

    Component {
        id: controlComponent
        Control {}
    }

    Component {
        id: trayComponent
        Tray {}
    }

    Component {
        id: notificationsComponent
        Notifications {}
    }

    Component {
        id: visualizerComponent

        Visualizer {}
    }

    Component {
        id: musicControlsComponent

        MusicControls {}
    }

    Component {
        id: bongoComponent

        Bongo {}
    }

    Component {
        id: mediaComponent
        Media {}
    }

    Component {
        id: captureComponent
        Capture {}
    }

    Component {
        id: aiComponent
        AiFill {}
    }

    Component {
        id: updatesComponent
        Updates {}
    }

    // `Failed`, nicht `Units`: der Dienst in qs.Services heisst schon so --
    // dieselbe Falle wie bei `Tasks`/`Todo` weiter unten.
    Component {
        id: unitsComponent
        Failed {}
    }

    // `Tasks`, nicht `Todo`: der Dienst in qs.Services heisst schon so, und
    // beide Namen im selben Gueltigkeitsbereich waeren mehrdeutig. Dieselbe
    // Trennung wie bei Clip (Baustein) und Clipboard (Dienst).
    Component {
        id: todoComponent
        Tasks {}
    }

    Component {
        id: habitsComponent
        HabitsWidget {}
    }

    Component {
        id: kdeconnectComponent
        KdeConnect {}
    }

    Component {
        id: tailscaleComponent
        Tailscale {}
    }

    Component {
        id: whatsappComponent
        WhatsApp {}
    }

    Component {
        id: zenPipComponent
        Pip {}
    }
}
