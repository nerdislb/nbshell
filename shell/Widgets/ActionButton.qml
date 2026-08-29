import QtQuick
import qs.Common

// Gemeinsame Aktionsflaeche. Klickbare Befehle tragen keine dekorativen
// Textklammern mehr; Rolle, Flaeche und Zustand machen die Aktion erkennbar.
InteractiveSurface {
    id: root

    property string text: ""
    property string tone: "secondary" // primary, secondary, danger
    property bool busy: false
    property bool compact: false
    property color accentColor: tone === "danger" ? Theme.red : Theme.accent

    signal rightTriggered()

    activationBlocked: busy
    accessibleName: text
    accessibleDescription: busy ? "Action in progress" : ""
    accessiblePressed: tap.pressed

    readonly property color idleSurface: tone === "primary"
        ? Theme.selectedSurface(accentColor)
        : (tone === "danger" ? Theme.mix(Theme.bg, Theme.red, 0.12) : Theme.panelSurfaceRaised)
    readonly property color activeSurface: tone === "primary"
        ? Theme.mix(Theme.bg, accentColor, 0.28)
        : (tone === "danger" ? Theme.mix(Theme.bg, Theme.red, 0.22) : Theme.hover)
    readonly property color labelColor: tone === "danger"
        ? Theme.readable(Theme.red, idleSurface, 4.5)
        : (tone === "primary" ? Theme.selectedForeground(accentColor) : Theme.fg)

    // Compact actions live in dense popout rows. Keep their hit target clear,
    // but do not let the surrounding surface dominate the terminal-like text.
    implicitWidth: label.implicitWidth + Theme.cellW * (compact ? 1.0 : 2.2)
    implicitHeight: Theme.cellH * (compact ? 1.1 : 1.55)
    radius: Theme.radius
    color: !enabled ? Theme.alpha(Theme.panelSurfaceRaised, 0.45) : (hover.hovered || activeFocus || tap.pressed ? activeSurface : idleSurface)
    border.width: activeFocus ? Theme.borderWidth : (root.tone === "primary" ? 0 : Theme.borderWidth)
    border.color: activeFocus ? Theme.focusBorder : (!enabled ? Theme.alpha(Theme.fg, 0.2)
        : (tone === "secondary" ? Theme.alpha(Theme.fg, 0.4) : Theme.alpha(accentColor, 0.8))
    )
    opacity: enabled ? 1 : 0.55
    Behavior on color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.motionFast } }
    Behavior on opacity { NumberAnimation { duration: Theme.motionFast } }

    Line {
        id: label
        anchors.centerIn: parent
        text: root.busy ? "…" : root.text
        color: !root.enabled ? Theme.fgDim
            : root.labelColor
        font.pixelSize: Theme.fontBody
        font.bold: root.tone === "primary"
    }

    HoverHandler {
        id: hover
        enabled: root.interactive && root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap
        enabled: root.interactive && root.enabled && !root.busy
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: function(eventPoint, button) {
            if (button === Qt.RightButton && root.interactive && root.enabled && !root.busy)
                root.rightTriggered();
            else {
                root.forceActiveFocus();
                root.activate();
            }
        }
    }
}
