import QtQuick
Item {
 property bool shown: true
 property bool quiet: false
 property bool active: false
 property int slotChars: 2
 property bool interactive: true
 property string label: ""
 property string icon: ""
 property string text: ""
 property color color: Qt.rgba(1, 1, 1, 1)
 visible: shown
 signal clicked()
}
