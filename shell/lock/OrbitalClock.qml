// Adapted from dumidulkdev/omarchy-orbital-lock (MIT), commit 6639304.
pragma ComponentBehavior: Bound
import QtQuick
import "ClockMath.js" as ClockMath

Item {
    id: root
    property var currentTime: new Date()
    property color foreground: "white"
    property bool showSecondsRing: true
    property string hourFormat: "24"
    property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property real unit: width / 960
    readonly property real minuteRadius: 305 * unit
    readonly property real secondRadius: 445 * unit

    component Dial: Item {
        id: dial
        required property real dialRadius
        required property real dialRotation
        required property bool outer
        anchors.centerIn: parent
        width: dialRadius * 2; height: width; rotation: dialRotation
        Repeater {
            model: 60
            delegate: Item {
                required property int index
                readonly property real baseAngle: index * 6
                readonly property real radians: (baseAngle - 90) * Math.PI / 180
                readonly property bool major: index % 5 === 0
                readonly property real highlight: Math.max(0, 1 - ClockMath.angularDistance(baseAngle + dial.rotation, 0) / 24)
                x: dial.width / 2 + Math.cos(radians) * dial.dialRadius
                y: dial.height / 2 + Math.sin(radians) * dial.dialRadius
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.major ? (dial.outer ? 2.2 : 3) * root.unit : (dial.outer ? 1.2 : 1.5) * root.unit
                    height: parent.major ? (dial.outer ? 15 : 20) * root.unit : (dial.outer ? 8 : 11) * root.unit
                    radius: width / 2; rotation: parent.baseAngle; color: root.foreground
                    opacity: parent.major ? 0.3 + parent.highlight * 0.65 : 0.13 + parent.highlight * 0.46
                }
                Text {
                    visible: parent.major
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: dial.outer ? parent.verticalCenter : undefined
                    anchors.bottom: dial.outer ? undefined : parent.verticalCenter
                    anchors.topMargin: 15 * root.unit; anchors.bottomMargin: 17 * root.unit
                    text: String(parent.index).padStart(2, "0"); color: root.foreground
                    opacity: 0.25 + parent.highlight * 0.75
                    font.family: root.fontFamily; font.pixelSize: (dial.outer ? 16 : 23) * root.unit
                    font.weight: parent.highlight > 0.55 ? Font.Bold : Font.Normal
                    font.letterSpacing: (dial.outer ? 1.5 : 2) * root.unit; rotation: parent.baseAngle
                }
            }
        }
    }

    Dial { id: secondRing; outer: true; visible: root.showSecondsRing; dialRadius: root.secondRadius; dialRotation: ClockMath.visibleEdgeRotation(ClockMath.secondAngle(root.currentTime)) }
    Dial { id: minuteRing; outer: false; dialRadius: root.minuteRadius; dialRotation: ClockMath.visibleEdgeRotation(ClockMath.minuteAngle(root.currentTime)) }
    Text {
        x: parent.width / 2 + 72 * root.unit; anchors.verticalCenter: parent.verticalCenter
        text: ClockMath.hourText(root.currentTime, root.hourFormat); color: root.foreground
        font.family: root.fontFamily; font.pixelSize: 118 * root.unit; font.weight: Font.Black
        font.letterSpacing: -7 * root.unit
    }
}
