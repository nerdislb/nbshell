import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Optional bar entry for the standalone theme gallery. The gallery lives in
// the shell root, so menu, IPC, and desktop gestures work even without this
// widget in the configured bar layout.
Cell {
    id: root

    icon: Icons.palette
    text: Config.widgetIcons ? "" : Config.theme
    color: Theme.barAccent
    interactive: true
    active: Runtime.themePickerOpen

    onClicked: Runtime.themePickerOpen = true
    onWheel: delta => ThemeIndex.step(delta > 0 ? -1 : 1)
}
