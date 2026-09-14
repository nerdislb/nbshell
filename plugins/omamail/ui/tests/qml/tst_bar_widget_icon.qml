import QtQuick
import QtTest
import qs.Services
import "../.." as Omamail
Item {
 QtObject {
   id: mail
   property bool anyAccountReady: true
   property bool windowOpen: false
   property int unreadTotal: 3
   property var settings: ({showBarIcon: true})
 }
 Omamail.BarWidget { id: widget }
 TestCase {
   name: "NativeMailCell"
   when: windowShown
   function init() { Plugins.service = mail; Plugins.toggleCount = 0; mail.settings = ({showBarIcon: true}); mail.windowOpen = false; mail.unreadTotal = 3 }
   function test_unread_and_active_follow_service() { compare(widget.text, "3"); mail.windowOpen = true; compare(widget.active, true); mail.unreadTotal = 0; compare(widget.text, ""); compare(widget.quiet, true) }
   function test_icon_setting_and_click() { mail.settings = ({showBarIcon: false}); compare(widget.shown, false); mail.settings = ({showBarIcon: true}); widget.clicked(); compare(Plugins.toggleCount,1) }
   function test_startup_without_service() { Plugins.service = null; compare(widget.text, ""); compare(widget.shown, true) }
 }
}
