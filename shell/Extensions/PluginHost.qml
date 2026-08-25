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

    Component {
        id: runtimeLoader
        Loader {
            id: loader

            required property var modelData

            active: true
            source: modelData.source

            onLoaded: {
                Plugins.registerInstance(modelData.id, modelData.kind, item);
                Plugins.reportLoadState(modelData.id, modelData.kind, "loaded", modelData.source);
                if (item && "manifest" in item)
                    item.manifest = Plugins.entry(modelData.id);
                if (item && "shell" in item)
                    item.shell = Plugins;
                if (item && "pluginRegistry" in item)
                    item.pluginRegistry = Plugins;
                if (item && "host" in item)
                    item.host = modelData.kind === "bar-widget" ? "bar" : modelData.kind;
                if (item && "service" in item)
                    item.service = Plugins.serviceFor(modelData.id);
                if (modelData.kind === "service" && item && typeof item.applySettings === "function")
                    item.applySettings(Plugins.settingsFor(modelData.id));
                if (modelData.kind === "panel" || modelData.kind === "overlay")
                    Plugins.openLoadedPanel(modelData.id, item);
            }

            Binding {
                target: loader.item
                when: loader.item && "service" in loader.item
                property: "service"
                value: Plugins.serviceFor(loader.modelData.id)
                restoreMode: Binding.RestoreNone
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
                Plugins.reportLoadState(modelData.id, modelData.kind, "inactive", "");
            }
        }
    }

    // Services and on-demand surfaces use separate models. Changing the set
    // of open windows must never rebuild long-lived services with sockets,
    // timers, or queued callbacks.
    Repeater {
        model: Plugins.serviceEntries
        delegate: runtimeLoader
    }

    Repeater {
        model: Plugins.surfaceEntries
        delegate: runtimeLoader
    }
}
