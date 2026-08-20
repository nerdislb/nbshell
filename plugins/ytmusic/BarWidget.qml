import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
  id: root
  readonly property var player: Plugins.serviceFor("ytmusic")
  shown: true
  quiet: !player || !player.hasMedia
  slotChars: 2
  interactive: true
  label: "YouTube Music"
  icon: player && player.playing ? String.fromCodePoint(0xf04b) : String.fromCodePoint(0xf001)
  text: player && player.hasMedia ? player.title : ""
  color: player && player.playing ? Theme.accent : Theme.textDim
  onClicked: Plugins.toggle("ytmusic", "{}")
  onRightClicked: if (player) player.togglePlayback()
}
