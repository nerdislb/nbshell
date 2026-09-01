import QtQuick
import qs.Commons
import qs.Ui

// One word or phrase inside a line of text that is a link out of the window.
//
// Underlined, always: the affordance has to be there before the pointer is, and
// colour alone must never carry it — some themes put the accent close enough to
// the foreground that a recolour says nothing at all.
//
// The pointing-hand cursor is reserved for real links, which this is. Native
// controls elsewhere in the panel keep the arrow, and `tests/test_source.sh`
// enforces that for the files that hold them.
Text {
  id: root

  property string tooltipText: ""
  property string accessibleName: ""

  signal activated()
  activeFocusOnTab: enabled
  Accessible.role: Accessible.Link
  Accessible.name: accessibleName !== "" ? accessibleName : text
  Accessible.focusable: enabled
  Accessible.onPressAction: if (enabled) root.activated()
  Keys.onPressed: function(event) {
    if (!enabled || event.isAutoRepeat) return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activated()
      event.accepted = true
    }
  }

  font.underline: true

  HoverHandler {
    id: hover
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    onTapped: root.activated()
  }

  PanelToolTip {
    text: root.tooltipText
    visible: hover.hovered && root.tooltipText !== ""
  }
}
