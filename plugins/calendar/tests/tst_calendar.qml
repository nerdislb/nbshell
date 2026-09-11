import QtQuick
import QtTest
import ".."
import "../Dates.js" as Dates

TestCase {
    id: test
    name: "StandaloneCalendar"
    width: 800; height: 640
    visible: true
    when: windowShown
    QtObject {
        id: backend
        property var accounts: [{id: "a", name: "Synthetic iCloud", provider: "icloud"}]
        property var calendars: [{account: "a", id: "c", key: "a:c", name: "Personal", visible: true, writable: true}]
        property var events: [{account: "a", calendar: "c", calendarKey: "a:c", title: "Synthetic event", start: "2026-09-11T10:00:00Z", end: "2026-09-11T11:00:00Z", allDay: false, writable: true, blocked: false}]
        property bool busy: false
        property bool stale: false
        property string error: ""
        property string loadedAt: "2026-09-11T09:00:00Z"
        property string authorizationUrl: ""
        property var last: ({})
        signal changed()
        function run(value) { last = value; }
        function refresh(start,end) { last = {op: "refresh", start: start,end:end}; }
        function cancel() { }
    }
    CalendarView { id: view; anchors.fill: parent; backend: backend }
    property var initialAccounts
    property var initialCalendars
    property var initialEvents
    function initTestCase() {
        initialAccounts = backend.accounts; initialCalendars = backend.calendars; initialEvents = backend.events;
    }
    function init() {
        backend.accounts = initialAccounts; backend.calendars = initialCalendars; backend.events = initialEvents;
        view.confirmation = ""; view.pending = ({}); view.editorError = ""; view.page = "calendar";
        backend.stale = false; backend.busy = false; backend.error = ""; backend.last = ({});
        test.width = 800;
    }
    function field(name) { return findChild(view, name); }
    function test_create_requires_explicit_destination() {
        view.edit(null);
        verify(view.destination === null);
        view.prepare("create");
        compare(view.confirmation, "");
        view.destination = backend.calendars[0];
        field("titleField").text = "New event";
        view.prepare("create");
        verify(view.confirmation.length > 0);
        compare(view.pending.calendar, "c");
        compare(view.pending.confirmed, true);
    }
    function test_offline_and_series_guard() {
        view.edit(backend.events[0]);
        backend.stale = true;
        view.prepare("delete");
        compare(view.confirmation, "");
        backend.stale = false;
        view.selectedEvent = {blocked: true};
        view.prepare("delete");
        compare(view.confirmation, "");
    }
    function test_escape_cancels_confirmation_before_editor() {
        view.edit(backend.events[0]);
        view.prepare("delete");
        view.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(view.confirmation, "");
        compare(view.page, "editor");
        keyClick(Qt.Key_Escape);
        compare(view.page, "calendar");
    }
    function test_dates_exclusive_end_and_keyboard_focus() {
        const event = {start: "2026-09-11", end: "2026-09-13"};
        verify(Dates.touches(event, new Date(2026,8,12)));
        verify(!Dates.touches(event, new Date(2026,8,13)));
        view.edit(null);
        wait(20);
        verify(view.focusedItem !== null);
        keyClick(Qt.Key_Tab);
        verify(view.focusedItem.activeFocus);
    }
    function test_views_and_narrow_layout() {
        view.anchor = new Date(2026,8,11);
        view.mode = "Week"; compare(view.days.length,7);
        view.mode = "Month"; compare(view.days.length,42);
        test.width = 320; wait(50);
        compare(view.width,320);
        view.mode = "Agenda"; compare(view.days.length,14);
    }
    function test_missing_account_and_live_destination() {
        view.edit(backend.events[0]);
        backend.accounts = [];
        view.prepare("edit");
        compare(view.confirmation, ""); compare(Object.keys(view.pending).length, 0);
        verify(view.editorError.length > 0);
        backend.accounts = initialAccounts;
        backend.calendars = [Object.assign({}, initialCalendars[0], {writable:false})];
        view.prepare("delete"); compare(view.confirmation, "");
        backend.calendars = []; view.prepare("delete"); compare(view.confirmation, "");
        backend.calendars = initialCalendars; backend.busy = true;
        view.prepare("delete"); compare(view.confirmation, "");
        backend.busy = false;
        backend.events = [Object.assign({}, initialEvents[0], {blocked:true})];
        view.prepare("delete"); compare(view.confirmation, "");
    }
    function test_confirmation_rechecks_state() {
        view.edit(backend.events[0]); view.prepare("delete");
        verify(view.confirmation.length > 0);
        backend.accounts = []; view.confirmPending();
        compare(backend.last.op, undefined); compare(view.confirmation, "");
    }
    function test_disconnect_confirmation_and_error_banner() {
        view.page = "accounts";
        view.prepareDisconnect("a"); verify(view.confirmation.indexOf("saved secret") >= 0);
        compare(backend.last.op, undefined);
        view.back(); compare(view.confirmation, ""); compare(Object.keys(view.pending).length, 0);
        view.prepareDisconnect("a"); view.confirmPending();
        compare(backend.last.op, "disconnect"); compare(backend.last.confirmed, true);
        backend.last = ({}); view.prepareDisconnect("a"); backend.accounts = []; view.confirmPending();
        compare(backend.last.op, undefined); compare(view.confirmation, "");
        backend.error = "Synthetic failure";
        wait(10);
        const banner = findChild(view, "errorBanner");
        verify(banner.visible); verify(banner.text.indexOf("Synthetic failure") >= 0);
    }
    function test_toggle_both_ways_data() {
        return [
            {tag:"single", start:"2026-09-11T09:00:00+02:00", end:"2026-09-11T10:00:00+02:00", first:"2026-09-11", last:"2026-09-12", offset:"+02:00", endOffset:"+02:00"},
            {tag:"multi", start:"2026-09-11T23:00:00+02:00", end:"2026-09-14T10:00:00+02:00", first:"2026-09-11", last:"2026-09-15", offset:"+02:00", endOffset:"+02:00"},
            {tag:"spring DST", start:"2026-03-28T23:00:00+01:00", end:"2026-03-30T00:00:00+02:00", first:"2026-03-28", last:"2026-03-30", offset:"+01:00", endOffset:"+02:00"},
            {tag:"fall DST", start:"2026-10-24T23:00:00+02:00", end:"2026-10-26T00:00:00+01:00", first:"2026-10-24", last:"2026-10-26", offset:"+02:00", endOffset:"+01:00"}
        ];
    }
    function test_toggle_both_ways(data) {
        view.edit(backend.events[0]);
        field("startField").text = data.start; field("endField").text = data.end;
        view.toggleAllDay(); verify(view.allDay);
        compare(field("startField").text, data.first); compare(field("endField").text, data.last);
        view.toggleAllDay(); verify(!view.allDay);
        compare(field("startField").text, data.first + "T00:00:00" + data.offset);
        compare(field("endField").text, data.last + "T00:00:00" + data.endOffset);
        view.toggleAllDay(); compare(field("endField").text, data.last);
    }
    function test_local_defaults_and_invalid_input() {
        view.anchor = new Date(2026, 8, 11); view.edit(null);
        compare(field("startField").text, "2026-09-11T09:00:00+02:00");
        for (const bad of ["", "garbage", "2026-02-30T10:00:00+01:00", "2026-09-11T25:00:00+02:00", "2026-09-11T10:00:00"]) {
            field("startField").text = bad;
            view.toggleAllDay(); verify(!view.allDay); compare(field("startField").text, bad);
            verify(view.editorError.length > 0);
            view.destination = backend.calendars[0]; field("titleField").text = "Test";
            view.prepare("create"); compare(view.confirmation, "");
        }
        view.allDay = true; field("startField").text = "2026-02-30";
        view.toggleAllDay(); verify(view.allDay); compare(field("startField").text, "2026-02-30");
    }

    function test_separate_inputs_serialize_real_keyboard_edits() {
        view.edit(backend.events[0]);
        wait(20);
        const start = field("startField");
        const time = findChild(start, "eventTimeInput");
        time.forceActiveFocus();
        keyClick(Qt.Key_A, Qt.ControlModifier);
        keyClick(Qt.Key_1); keyClick(Qt.Key_2); keyClick(Qt.Key_Colon);
        keyClick(Qt.Key_3); keyClick(Qt.Key_0);
        view.prepare("edit");
        verify(view.confirmation.length > 0);
        compare(view.pending.draft.start, "2026-09-11T12:30:00+02:00");
        compare(view.pending.draft.end, backend.events[0].end);
        view.back(); view.back(); view.edit(backend.events[0]);
        compare(time.text, "12:00");
        compare(start.serializedValue(), backend.events[0].start);
    }

    function test_inclusive_last_day_display() {
        view.anchor = new Date(2026, 8, 11);
        view.edit(null); view.toggleAllDay();
        const end = field("endField");
        compare(findChild(end, "eventDateInput").text, "2026-09-11");
        compare(end.serializedValue(), "2026-09-12");
    }

}
