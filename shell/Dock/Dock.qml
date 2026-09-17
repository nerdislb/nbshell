import Quickshell

Variants {
    model: Quickshell.screens
    delegate: DockWindow { required property var modelData; screen: modelData }
}
