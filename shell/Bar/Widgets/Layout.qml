import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Tastaturbelegung, auf zwei Buchstaben eingedampft ("German" -> "GE").
Cell {
    id: root

    shown: Compositor.keyboardLayout !== ""
    icon: Icons.keyboard
    text: Compositor.keyboardLayout.substring(0, 2).toUpperCase()
    color: Theme.textDim
}
