import QtQuick
import qs.Common
import "Widgets"

// Loest einen Namen aus der Config zu einem Baustein auf.
//
// Der Loader steckt in einer Huelle und bekommt selbst KEINE Groesse: ein
// Loader mit gesetzter Breite skaliert sein Kind auf genau diese Breite, und
// steht die Breite ihrerseits am Kind, fallen beide lautlos auf 0.
Item {
    id: root

    property string widgetName: ""
    property string screenName: ""

    readonly property var item: loader.item

    width: item ? item.width : 0
    height: item ? item.height : 0

    // NICHT `item.visible` abfragen: die Sichtbarkeit eines Kindes enthaelt
    // immer die des Elternteils. Die Huelle wuerde also ihre eigene Antwort
    // lesen -- beide blieben fuer immer unsichtbar. Bausteine, die sich
    // ausblenden wollen, setzen deshalb `shown`.
    visible: !!item && item.shown && width > 0

    Loader {
        id: loader

        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: root.componentFor(root.widgetName)

        onStatusChanged: if (status === Loader.Error)
            console.warn("nbshell: Baustein", root.widgetName, "laedt nicht");
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

    function componentFor(name) {
        switch (name) {
        case "clock":
            return clockComponent;
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
        }
        console.warn("nbshell: unbekannter Baustein:", name);
        return null;
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
}
