import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.Widgets

Cell {
  id: root
  readonly property var player: Plugins.serviceFor("ytmusic")
  shown: true
  quiet: false
  slotChars: 1
  interactive: true
  label: "YouTube Music"
  icon: ""
  text: ""
  color: player && player.playing ? Theme.accent : Theme.textDim
  onClicked: Plugins.toggle("ytmusic", "{}")
  onRightClicked: if (player) player.togglePlayback()
  popoutOnHover: true

  custom: true

  Image {
    id: logoSource
    width: Math.round(Theme.cellH * 0.9)
    height: width
    source: Qt.resolvedUrl("assets/ytmusic.svg")
    fillMode: Image.PreserveAspectFit
    smooth: true
    visible: false
  }

  MultiEffect {
    width: logoSource.width
    height: logoSource.height
    source: logoSource
    colorization: 1.0
    colorizationColor: player && player.playing ? "#ff0033" : Theme.barFg
  }

  popout: Component {
    Column {
      id: panel

      property var closePopout: null
      readonly property real rowWidth: 44 * Theme.cellW

      spacing: Theme.cellH * 0.35

      PanelHead {
        rowWidth: panel.rowWidth
        icon: Icons.play
        title: player && player.hasMedia ? player.title : "YouTube Music"
        subtitle: player && player.hasMedia ? player.artist : "Nothing playing"
        badge: player && player.hasMedia && player.lengthSeconds > 0
          ? Math.floor(player.positionSeconds / 60) + ":" + String(Math.floor(player.positionSeconds % 60)).padStart(2, "0")
          : ""
        badgeColor: player && player.playing ? "#ff0033" : Theme.fgDim
      }

      Image {
        width: panel.rowWidth
        height: player && player.artUrl ? Theme.cellH * 8 : 0
        visible: height > 0
        source: player ? player.artUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }

      LevelBar {
        width: panel.rowWidth
        visible: player && player.hasMedia && player.lengthSeconds > 0
        cells: 38
        value: player ? Math.round(player.positionSeconds) : 0
        maximum: player ? Math.max(1, Math.round(player.lengthSeconds)) : 1
        fillColor: "#ff0033"
        interactive: player && player.playbackControllable
        onMoved: value => player.seekSeconds(value)
      }

      Row {
        width: panel.rowWidth
        spacing: Theme.cellW

        ActionButton {
          text: "Previous"
          compact: true
          enabled: player && player.playbackControllable
          onTriggered: player.previous()
        }

        ActionButton {
          text: player && player.playing ? "Pause" : "Play"
          tone: "primary"
          accentColor: "#ff0033"
          compact: true
          enabled: player && player.playbackControllable
          onTriggered: player.togglePlayback()
        }

        ActionButton {
          text: "Next"
          compact: true
          enabled: player && player.playbackControllable
          onTriggered: player.next()
        }

        ActionButton {
          text: "Open"
          compact: true
          onTriggered: {
            panel.closePopout?.()
            Plugins.toggle("ytmusic", "{}")
          }
        }
      }

      Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4
        visible: player && player.volumeSupported

        Line {
          id: volumeLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Volume"
          color: Theme.fgDim
        }

        LevelBar {
          anchors.left: volumeLabel.right
          anchors.leftMargin: Theme.cellW
          anchors.right: volumeValue.left
          anchors.rightMargin: Theme.cellW
          anchors.verticalCenter: parent.verticalCenter
          cells: 18
          value: player ? Math.round(player.volume * 100) : 0
          maximum: 100
          fillColor: "#ff0033"
          onMoved: value => player.setVolume(value / 100)
        }

        Line {
          id: volumeValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: player ? Math.round(player.volume * 100) + "%" : ""
          color: Theme.fg
        }
      }
    }
  }
}
