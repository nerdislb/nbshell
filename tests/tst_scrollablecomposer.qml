import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    name: "ScrollableComposer"
    width: 420
    height: 180
    when: windowShown

    ScrollView {
        id: viewport
        width: 320
        height: 64
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        TextArea {
            id: composer
            width: viewport.availableWidth
            padding: 0
            background: null
            wrapMode: TextEdit.Wrap
        }
    }

    function test_cursor_keeps_long_text_reachable() {
        composer.text = "TOP " + "wrapped message ".repeat(80) + "BOTTOM"
        composer.forceActiveFocus()
        composer.cursorPosition = composer.length
        tryVerify(function() { return viewport.contentItem.contentY > 0 })
        const bottomY = viewport.contentItem.contentY
        composer.cursorPosition = 0
        tryCompare(viewport.contentItem, "contentY", 0)
        composer.cursorPosition = composer.length
        tryVerify(function() { return viewport.contentItem.contentY >= bottomY })
    }
}
