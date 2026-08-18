import QtQuick
import qs.Common

// Gemeinsame Aktionsflaeche. Klickbare Befehle tragen keine dekorativen
// Textklammern mehr; Rolle, Flaeche und Zustand machen die Aktion erkennbar.
Rectangle {
    id: root

    property string text: ""
    property string tone: "secondary" // primary, secondary, danger
    property bool busy: false
    property bool compact: false
    property color accentColor: tone === "danger" ? Theme.red : Theme.accent

    signal triggered()
    signal rightTriggered()

    readonly property color idleSurface: tone === "primary"
        ? Theme.alpha(accentColor, 0.20)
        : (tone === "danger" ? Theme.alpha(Theme.red, 0.12) : Theme.bgLight)
    readonly property color activeSurface: tone === "primary"
        ? Theme.alpha(accentColor, 0.34)
        : (tone === "danger" ? Theme.alpha(Theme.red, 0.24) : Theme.hover)
    // Die Flaeche ist teilweise transparent. Kontrast gegen `root.color`
    // allein waere deshalb falsch: QML mischt sie erst spaeter mit bgLight.
    readonly property color labelColor: tone === "danger"
        ? Theme.readable(Theme.red, Theme.bgLight, 4.5)
        : Theme.readable(Theme.fgBright, Theme.bgLight, 4.5)

    implicitWidth: label.implicitWidth + Theme.cellW * (compact ? 1.5 : 2.5)
    implicitHeight: Theme.cellH * (compact ? 1.35 : 1.65)
    radius: Theme.radius
    color: !enabled ? Theme.alpha(Theme.bgLight, 0.45) : (hover.hovered || tap.pressed ? activeSurface : idleSurface)
    border.width: Theme.borderWidth
    border.color: !enabled ? Theme.muted : (tone === "secondary" ? Theme.muted : accentColor)
    opacity: enabled ? 1 : 0.55

    Line {
        id: label
        anchors.centerIn: parent
        text: root.busy ? "…" : root.text
        color: !root.enabled ? Theme.fgDim
            : root.labelColor
        font.bold: root.tone === "primary"
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        enabled: root.enabled && !root.busy
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: function(eventPoint, button) {
            if (button === Qt.RightButton)
                root.rightTriggered();
            else
                root.triggered();
        }
    }
}
