import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
  id: root
  readonly property var mail: Plugins.serviceFor("omamail")
  shown: true
  quiet: mail && mail.anyAccountReady && mail.unreadTotal === 0
  active: !!mail && mail.windowOpen
  slotChars: 2
  interactive: true
  label: "Mail"
  icon: String.fromCodePoint(0xf0e0)
  text: mail && mail.unreadTotal > 0 ? String(mail.unreadTotal) : ""
  color: mail && mail.unreadTotal > 0 ? Theme.accent : Theme.textDim
  onClicked: Plugins.toggle("omamail", "{}")
}
