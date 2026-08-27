// Adapted from dumidulkdev/omarchy-orbital-lock (MIT), commit 6639304.
pragma ComponentBehavior: Bound

import QtQuick
import "ClockMath.js" as ClockMath

Item {
    id: root

    property var currentTime: new Date()
    property color foreground: "white"
    property bool showSecondsRing: true
    property bool authenticating: false
    property string hourFormat: "24"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property real authBoost: 0

    readonly property real unit: width / 960
    readonly property real minuteRadius: 305 * unit
    readonly property real secondRadius: 445 * unit
    readonly property real minuteRotation: ClockMath.visibleEdgeRotation(ClockMath.minuteAngle(currentTime)) - authBoost * 0.45
    readonly property real secondRotation: ClockMath.visibleEdgeRotation(ClockMath.secondAngle(currentTime)) - authBoost

    NumberAnimation {
        target: root
        property: "authBoost"
        from: 0
        to: 360
        duration: 850
        loops: Animation.Infinite
        running: root.authenticating
        easing.type: Easing.InOutSine
        onStopped: root.authBoost = 0
    }

    Item {
        id: secondRing
        anchors.centerIn: parent
        width: root.secondRadius * 2
        height: width
        rotation: root.secondRotation
        visible: root.showSecondsRing

        Repeater {
            model: 60
            delegate: Item {
                required property int index
                readonly property real baseAngle: index * 6
                readonly property real radians: (baseAngle - 90) * Math.PI / 180
                readonly property bool major: index % 5 === 0
                readonly property real highlight: Math.max(0, 1 - ClockMath.angularDistance(baseAngle + secondRing.rotation, 0) / 24)
                x: secondRing.width / 2 + Math.cos(radians) * root.secondRadius
                y: secondRing.height / 2 + Math.sin(radians) * root.secondRadius

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.major ? 2.2 * root.unit : 1.2 * root.unit
                    height: parent.major ? 15 * root.unit : 8 * root.unit
                    radius: width / 2
                    rotation: parent.baseAngle
                    color: root.foreground
                    opacity: parent.major ? 0.28 + parent.highlight * 0.62 : 0.12 + parent.highlight * 0.42
                }
                Text {
                    visible: parent.major
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 15 * root.unit
                    text: String(parent.index).padStart(2, "0")
                    color: root.foreground
                    opacity: 0.24 + parent.highlight * 0.76
                    font.family: root.fontFamily
                    font.pixelSize: 16 * root.unit
                    font.weight: parent.highlight > 0.55 ? Font.Bold : Font.Normal
                    font.letterSpacing: 1.5 * root.unit
                    rotation: parent.baseAngle
                }
            }
        }
    }

    Item {
        id: minuteRing
        anchors.centerIn: parent
        width: root.minuteRadius * 2
        height: width
        rotation: root.minuteRotation

        Repeater {
            model: 60
            delegate: Item {
                required property int index
                readonly property real baseAngle: index * 6
                readonly property real radians: (baseAngle - 90) * Math.PI / 180
                readonly property bool major: index % 5 === 0
                readonly property real highlight: Math.max(0, 1 - ClockMath.angularDistance(baseAngle + minuteRing.rotation, 0) / 24)
                x: minuteRing.width / 2 + Math.cos(radians) * root.minuteRadius
                y: minuteRing.height / 2 + Math.sin(radians) * root.minuteRadius

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.major ? 3 * root.unit : 1.5 * root.unit
                    height: parent.major ? 20 * root.unit : 11 * root.unit
                    radius: width / 2
                    rotation: parent.baseAngle
                    color: root.foreground
                    opacity: parent.major ? 0.34 + parent.highlight * 0.66 : 0.15 + parent.highlight * 0.48
                }
                Text {
                    visible: parent.major
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: 17 * root.unit
                    text: String(parent.index).padStart(2, "0")
                    color: root.foreground
                    opacity: 0.3 + parent.highlight * 0.7
                    font.family: root.fontFamily
                    font.pixelSize: 23 * root.unit
                    font.weight: parent.highlight > 0.55 ? Font.Bold : Font.Normal
                    font.letterSpacing: 2 * root.unit
                    rotation: parent.baseAngle
                }
            }
        }
    }

    Text {
        x: parent.width / 2 + 72 * root.unit
        anchors.verticalCenter: parent.verticalCenter
        text: ClockMath.hourText(root.currentTime, root.hourFormat)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 118 * root.unit
        font.weight: Font.Black
        font.letterSpacing: -7 * root.unit
    }
}
