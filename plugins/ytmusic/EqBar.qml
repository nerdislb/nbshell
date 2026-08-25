import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real areaRadius: Math.max(Style.space(14), Style.cornerRadius)
  property int activeBand: -1
  property bool compact: false
  property bool showPreset: true
  property var previewBands: []

  readonly property var bands: root.service ? root.service.eqBands : []
  readonly property string presetName: root.service ? root.service.eqPreset : "Flat"
  readonly property var labels: root.service ? root.service.eqLabels : []
  readonly property real labelHeight: root.compact ? Style.space(12) : Style.space(14)

  implicitHeight: root.compact ? Style.space(56) : Style.space(72)
  implicitWidth: eqRow.implicitWidth

  function bandGain(index) {
    if (root.previewBands && root.previewBands.length === 10)
      return Number(root.previewBands[index]) || 0
    if (!root.bands || index < 0 || index >= root.bands.length) return 0
    return Number(root.bands[index]) || 0
  }

  function bandLabel(index) {
    if (root.labels && index >= 0 && index < root.labels.length)
      return String(root.labels[index])
    return ""
  }

  function formatGain(value) {
    var gain = Number(value) || 0
    if (Math.abs(gain) < 0.05) return "0"
    return (gain > 0 ? "+" : "") + Math.round(gain)
  }

  function snapshotBands() {
    var next = []
    for (var i = 0; i < 10; i++)
      next.push(root.bandGain(i))
    return next
  }

  function applyBand(index, gain) {
    var next = root.snapshotBands()
    next[index] = gain
    root.previewBands = next
    pendingIndex = index
    pendingGain = gain
    if (!applyTimer.running) applyTimer.start()
  }

  function flushBand() {
    applyTimer.stop()
    if (root.service && pendingIndex >= 0)
      root.service.setEqBand(pendingIndex, pendingGain)
  }

  property int pendingIndex: -1
  property real pendingGain: 0

  Timer {
    id: applyTimer
    interval: 80
    repeat: false
    onTriggered: root.flushBand()
  }

  onActiveBandChanged: if (root.activeBand < 0) {
    root.flushBand()
    root.previewBands = []
  }

  Row {
    id: eqRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Row {
      id: bandRow
      spacing: root.compact ? Style.space(2) : Style.space(4)

    Repeater {
      model: 10
      delegate: Item {
        required property int index
        width: root.compact ? Style.space(18) : Style.space(22)
        height: root.compact ? Style.space(48) : Style.space(60)

        readonly property real gain: root.bandGain(index)
        readonly property bool hot: root.activeBand === index

        Rectangle {
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - Style.space(4)
          height: parent.height - root.labelHeight - Style.space(4)
          radius: Style.space(4)
          color: Style.normalFillFor(root.foreground, root.accent)
          border.width: 1
          border.color: hot
            ? Style.controlBorder(true, true, root.foreground, root.accent)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(2)
            width: parent.width - Style.space(4)
            height: Math.max(Style.space(4), (parent.height - Style.space(4))
              * ((gain + 12) / 24))
            radius: Style.space(3)
            color: hot || Math.abs(gain) >= 0.05
              ? Style.selectedFillFor(root.foreground, root.accent)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          }
        }

        Text {
          id: label
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          height: root.labelHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: root.bandLabel(index)
          color: hot
            ? Style.selectedStateColor(root.foreground, root.accent)
            : Qt.darker(root.foreground, 1.35)
          font.family: Style.font.family
          font.pixelSize: root.compact ? Style.font.caption : Style.font.bodySmall
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor
          onPressed: function(mouse) {
            root.activeBand = index
            adjustGain(mouse.y)
          }
          onPositionChanged: function(mouse) {
            if (pressed) adjustGain(mouse.y)
          }
          onReleased: root.activeBand = -1
          onExited: if (!pressed) root.activeBand = -1

          function adjustGain(y) {
            if (!root.service) return
            var trackBottom = parent.height - root.labelHeight - Style.space(4)
            var span = Math.max(1, trackBottom - Style.space(4))
            var ratio = 1 - Math.max(0, Math.min(1, (y - Style.space(4)) / span))
            var next = Math.round((ratio * 24 - 12) * 2) / 2
            root.applyBand(index, next)
          }
        }

        PanelToolTip {
          visible: hot
          text: root.bandLabel(index) + " Hz · "
            + root.formatGain(gain) + " dB"
        }
      }
    }
    }

    Chicklet {
      id: presetChicklet
      visible: root.showPreset
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰓃"
      foreground: root.foreground
      selected: root.presetName !== "Flat" && root.presetName !== "Custom"
      tooltipText: "EQ preset: " + root.presetName + " · E"
      Accessible.name: "EQ preset " + root.presetName
      onClicked: if (root.service) root.service.cycleEqPreset()
    }
  }
}
