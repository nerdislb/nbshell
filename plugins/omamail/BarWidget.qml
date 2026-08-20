import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
  id: root
  readonly property var mail: Plugins.serviceFor("omamail")
  shown: true
  quiet: mail && mail.ready && mail.unreadCount === 0
  slotChars: 2
  interactive: true
  label: "Mail"
  icon: String.fromCodePoint(0xf0e0)
  text: mail && mail.unreadCount > 0 ? String(mail.unreadCount) : ""
  color: mail && mail.unreadCount > 0 ? Theme.accent : Theme.textDim
  onClicked: Plugins.toggle("omamail", "{}")
}
