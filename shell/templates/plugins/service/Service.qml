import QtQuick

QtObject {
    id: root

    property var manifest: null
    property var settings: ({})
    readonly property string status: "ready"

    function applySettings(values) {
        settings = values || ({});
    }
}
