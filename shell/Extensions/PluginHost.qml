import QtQuick
import qs.Services

// Laedt die explizit aktivierten Panel-, Overlay- und Service-Einstiegspunkte.
// Bar-Widgets entstehen weiterhin nur dort, wo WidgetHost sie einplant.
Item {
    id: root

    width: 0
    height: 0
    // Geladene PanelWindow/PopupWindow-Wurzeln steuern ihre Sichtbarkeit
    // selbst. Der Host belegt mit 0x0 trotzdem keinen Platz.
    visible: true

    Repeater {
        model: Plugins.runtimeEntries

        Loader {
            id: loader

            required property var modelData

            active: true
            source: modelData.source

            onLoaded: {
                Plugins.registerInstance(modelData.id, modelData.kind, item);
                Plugins.reportLoadState(modelData.id, modelData.kind, "geladen", modelData.source);
            }
            onStatusChanged: {
                if (status === Loader.Loading)
                    Plugins.reportLoadState(modelData.id, modelData.kind, "laedt", modelData.source);
                if (status === Loader.Error) {
                    Plugins.reportLoadState(modelData.id, modelData.kind, "error", modelData.source);
                    console.warn("nbshell/plugins:", modelData.id, modelData.kind, "failed to load —", modelData.source);
                }
            }
            Component.onDestruction: {
                Plugins.unregisterInstance(modelData.id, modelData.kind, item);
                Plugins.reportLoadState(modelData.id, modelData.kind, "inaktiv", "");
            }
        }
    }
}
