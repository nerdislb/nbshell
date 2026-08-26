import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string surfaceKey: ""
  property bool cancelHasCursor: false
  property bool confirmHasCursor: false
  readonly property string availability: service
    ? String(service.lyricsPluginAvailability || "missing") : "missing"
  readonly property bool busy: service && service.lyricsPluginBusy
  readonly property string errorText: service
    ? String(service.lyricsPluginError || "") : ""

  signal canceled()

  implicitWidth: Style.space(340)
  implicitHeight: promptContent.implicitHeight
  height: implicitHeight

  Column {
    id: promptContent
    width: parent.width
    spacing: Style.space(9)

    Text {
      objectName: "lyrics-install-title"
      width: parent.width
      text: root.availability === "disabled" ? "Enable Lyrics?"
        : (root.availability === "ready" && root.errorText
          ? "Lyrics didn't open" : "Lyrics extension unavailable")
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      wrapMode: Text.WordWrap
    }

    Text {
      objectName: "lyrics-install-description"
      width: parent.width
      text: root.availability === "disabled"
        ? "The lyrics extension is already installed but currently disabled."
        : (root.availability === "ready"
          ? "The plugin is installed, but YouTube Music could not open its lyrics window."
          : "Install a compatible lyrics extension separately, then try again.")
      color: Qt.darker(root.foreground, 1.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      visible: root.availability === "missing"
      text: "Lyrics are optional and are not installed or managed by nbshell."
      color: Qt.darker(root.foreground, 1.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      objectName: "lyrics-install-error"
      width: parent.width
      visible: text !== ""
      text: root.errorText
      color: root.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        objectName: "lyrics-install-cancel"
        width: (parent.width - parent.spacing) / 2
        text: "Cancel"
        foreground: root.foreground
        focusable: true
        hasCursor: root.cancelHasCursor
        enabled: !root.busy
        onClicked: root.canceled()
      }

      Button {
        objectName: "lyrics-install-confirm"
        width: (parent.width - parent.spacing) / 2
        text: root.busy
          ? (root.service && root.service.lyricsPluginOperation === "disabled"
            ? "Enabling…" : "Installing…")
          : (root.availability === "disabled" ? "Enable"
            : (root.availability === "ready" ? "Try again" : "Close"))
        iconText: root.availability === "ready" ? "󰑓" : "󰐕"
        foreground: root.foreground
        selected: root.availability !== "missing"
        focusable: true
        hasCursor: root.confirmHasCursor
        enabled: !root.busy
        onClicked: {
          if (root.availability === "missing") root.canceled()
          else if (root.service) root.service.confirmLyricsPlugin(root.surfaceKey)
        }
      }
    }
  }
}
