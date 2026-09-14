import QtQuick
import qs.Common
import qs.Widgets
import qs.Ui as Ui

// Shared native controls composed for one touchpad numeric parameter.
Column {
    id: root
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.01
    property int decimals: 2
    property string suffix: ""
    property string detail: ""
    signal edited(real value)
    spacing: Theme.spaceXs
    function commit(value) {
        if (isFinite(value)) edited(Math.max(minimum, Math.min(maximum, value)));
    }
    Line { width: parent.width; text: root.label + (root.detail ? " · " + root.detail : ""); wrapMode: Text.WordWrap }
    Row {
        width: parent.width
        spacing: Theme.spaceSm
        ControlButton { id: minus; text: "−"; enabled: root.value > root.minimum; onTriggered: root.commit(root.value - root.step) }
        TextField {
            id: field
            width: Math.min(Theme.cellW * 13, parent.width - minus.width * 2 - parent.spacing * 2)
            accessibleName: root.label
            text: Number(root.value).toFixed(root.decimals)
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator { bottom: root.minimum; top: root.maximum; decimals: root.decimals; locale: "C"; notation: DoubleValidator.StandardNotation }
            onEditingFinished: {
                if (acceptableInput) root.commit(Number(text));
                text = Number(root.value).toFixed(root.decimals);
            }
            Keys.onUpPressed: event => { root.commit(root.value + root.step * (event.modifiers & Qt.ShiftModifier ? 10 : 1)); event.accepted = true; }
            Keys.onDownPressed: event => { root.commit(root.value - root.step * (event.modifiers & Qt.ShiftModifier ? 10 : 1)); event.accepted = true; }
        }
        ControlButton { text: "+"; enabled: root.value < root.maximum; onTriggered: root.commit(root.value + root.step) }
        Line { text: root.suffix; anchors.verticalCenter: parent.verticalCenter }
    }
    Ui.PanelSlider {
        width: parent.width
        value: root.value; minimum: root.minimum; maximum: root.maximum; step: root.step
        activeFocusOnTab: true
        accessibleName: root.label
        trackColor: Theme.panelBorder; fillColor: Theme.accent; knobColor: Theme.fg
        onMoved: value => root.commit(value)
    }
}
