import QtQuick
import qs.Commons
import qs.Ui

TextField {
  id: root

  property real areaRadius: Math.max(Style.space(14), Style.cornerRadius)

  background: BorderSurface {
    implicitHeight: Style.space(38)
    color: Style.normalFillFor(root.foreground, root.accent)
    radius: root.areaRadius
    borderSpec: Border.none()
  }
}
