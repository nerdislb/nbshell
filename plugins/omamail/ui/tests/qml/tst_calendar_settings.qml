import QtQuick 2.15
import QtTest 1.3
import qs.Commons
import "../../components" as Omamail

Item {
  width: 600
  height: 800

  QtObject {
    id: mailService

    property bool unifiedCalendarView: false
    property bool alwaysShowImages: false
    property bool alwaysRenderHeavyMessages: false
    property int undoSendSeconds: 10
    property int settingChanges: 0
    property var accountSummaries: []
    property bool backendCanDiscoverCalendars: true
    property var auth: null

    function setUnifiedCalendarView(value) {
      unifiedCalendarView = value === true
      settingChanges = settingChanges + 1
    }
  }

  QtObject {
    id: calendarController

    property var sourceList: ({ version: 1, sources: [] })
    property var availableSources: sourceList
    property bool savingSource: false
    property bool discoveringCalendars: false
    property string discoveringAccountId: ""
    property int discoverCalls: 0
    property int toggleCalls: 0
    property string toggledId: ""
    property int removeCalls: 0
    property string removedId: ""
    property int colorCalls: 0
    property string coloredId: ""
    property string selectedColor: ""
    signal calendarSaved(bool ok, string error)
    signal discoveryFinished(bool ok, string error, int count)

    function addCalDavCalendar(_source, _password) {}
    function removeCalendar(sourceId) { removeCalls++; removedId = sourceId }
    function updateCalendarPassword(_source, _password) {}
    function discoveredCount(_accountId) { return 0 }
    function discoverAccountCalendars(_accountId) { discoverCalls++; return true }
    function setSourceEnabled(sourceId, _enabled) { toggleCalls++; toggledId = sourceId }
    function setSourceColor(sourceId, colorKey) {
      colorCalls++
      coloredId = sourceId
      selectedColor = colorKey
    }
  }

  Omamail.SettingsPage {
    id: settings
    width: parent.width
    service: mailService
    calendarController: calendarController
    textColor: Color.foreground
    dimColor: Color.foreground
    accentColor: Color.accent
    urgentColor: Color.accent
    panelFontFamily: "monospace"
  }

  TestCase {
    name: "CalendarSettings"
    when: windowShown

    function init() {
      mailService.accountSummaries = []
      mailService.backendCanDiscoverCalendars = true
      calendarController.sourceList = ({ version: 1, sources: [] })
      calendarController.discoverCalls = 0
      calendarController.toggleCalls = 0
      calendarController.toggledId = ""
      calendarController.removeCalls = 0
      calendarController.removedId = ""
      calendarController.colorCalls = 0
      calendarController.coloredId = ""
      calendarController.selectedColor = ""
      wait(1)
    }

    function test_unified_view_switch_updates_the_persistent_setting() {
      var toggle = findChild(settings, "unifiedCalendarSwitch")
      verify(toggle !== null)
      compare(toggle.checked, false)

      toggle.toggled()
      compare(mailService.unifiedCalendarView, true)
      compare(mailService.settingChanges, 1)
      compare(toggle.checked, true)

      toggle.toggled()
      compare(mailService.unifiedCalendarView, false)
      compare(mailService.settingChanges, 2)
      compare(toggle.checked, false)
    }

    function test_existing_icloud_account_is_discovered_and_selected_in_calendars() {
      mailService.accountSummaries = [{ id: "imap:person@icloud.com",
        email: "person@icloud.com", provider: "imap", calendarProvider: "icloud",
        signedIn: true }]
      calendarController.sourceList = ({ version: 1, sources: [{
        id: "icloud:one", kind: "icloud", name: "Personal",
        accountId: "imap:person@icloud.com", enabled: true, discovered: true,
        colorKey: "accent"
      }] })
      wait(1)
      var discover = findChild(settings, "calendar-discover-icloud")
      verify(discover !== null)
      compare(discover.text, "Find calendars")
      verify(discover.activeFocusOnTab, "discovery must be reachable with Tab")
      discover.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(calendarController.discoverCalls, 1)
      var toggle = findChild(settings, "calendar-source-toggle")
      verify(toggle !== null)
      compare(toggle.checked, true)
      verify(toggle.activeFocusOnTab, "calendar visibility must be reachable with Tab")
      toggle.forceActiveFocus()
      keyClick(Qt.Key_Space)
      compare(calendarController.toggleCalls, 1)
      compare(calendarController.toggledId, "icloud:one")

      var colorButton = findChild(settings, "calendar-source-color")
      verify(colorButton !== null)
      var picker = findChild(settings, "calendar-color-picker")
      verify(picker !== null)
      compare(picker.visible, false)
      verify(colorButton.activeFocusOnTab, "the color trigger must be reachable with Tab")
      colorButton.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(picker.visible, true)
      var blue = findChild(settings, "calendar-color-blue")
      verify(blue !== null)
      verify(blue.activeFocusOnTab, "palette choices must be reachable with Tab")
      blue.forceActiveFocus()
      keyClick(Qt.Key_Space)
      compare(calendarController.colorCalls, 1)
      compare(calendarController.coloredId, "icloud:one")
      compare(calendarController.selectedColor, "blue")
      compare(picker.visible, false)
    }
    // Removing a mailbox leaves the calendars discovered through it in the
    // settings file with nothing to sign in as. They can be removed here;
    // a calendar whose mailbox is still present is refreshed, not removed.
    function test_a_calendar_whose_mailbox_is_gone_can_be_removed() {
      mailService.accountSummaries = [{ id: "imap:person@icloud.com",
        email: "person@icloud.com", provider: "imap", calendarProvider: "icloud",
        signedIn: true }]
      calendarController.sourceList = ({ version: 1, sources: [{
        id: "icloud:kept", kind: "icloud", name: "Personal",
        accountId: "imap:person@icloud.com", enabled: true, discovered: true,
        colorKey: "accent"
      }, {
        id: "icloud:orphan", kind: "icloud", name: "Old",
        accountId: "imap:gone@icloud.com", enabled: true, discovered: true,
        colorKey: "accent"
      }] })
      wait(1)
      var removes = []
      var details = []
      function collect(item) {
        if (!item) return
        if (item.objectName === "calendar-source-remove") removes.push(item)
        if (item.objectName === "calendar-source-detail") details.push(item)
        for (var i = 0; i < item.children.length; i++) collect(item.children[i])
      }
      collect(settings)
      compare(removes.length, 2)
      compare(removes[0].visible, false, "a calendar with its mailbox is not removable")
      compare(removes[1].visible, true, "a calendar without its mailbox is")
      compare(details.length, 2)
      compare(details[0].text, "iCloud · person@icloud.com")
      compare(details[1].text, "iCloud · Mailbox removed")
      removes[1].clicked()
      compare(calendarController.removeCalls, 1)
      compare(calendarController.removedId, "icloud:orphan")
    }

    function test_old_backend_does_not_offer_discovery() {
      mailService.accountSummaries = [{ id: "imap:person@icloud.com",
        email: "person@icloud.com", calendarProvider: "icloud", signedIn: true }]
      mailService.backendCanDiscoverCalendars = false
      wait(1)
      compare(findChild(settings, "calendar-discover-icloud"), null)
      compare(calendarController.discoverCalls, 0)
    }
  }
}
