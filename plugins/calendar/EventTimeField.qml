import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "Dates.js" as Dates

// Display local date and time, but preserve an unchanged provider timestamp exactly.
RowLayout {
    id: root
    property string value: ""
    property alias text: root.value
    property bool inclusiveEnd: false
    property bool allDay: false
    property string accessibleName: "Event time"
    property bool edited: false
    readonly property bool valid: {
        try { serializedValue(); return true; } catch (error) { return false; }
    }
    spacing: Theme.spaceSm

    function loadValue() {
        if (!dateInput || !timeInput) return;
        var parts = Dates.editorParts(value, allDay, inclusiveEnd);
        dateInput.text = parts[0];
        timeInput.text = parts[1];
        edited = false;
    }
    function serializedValue() {
        if (!edited) {
            Dates.parse(value, allDay);
            return value;
        }
        return Dates.fromEditor(dateInput.text, timeInput.text, allDay, inclusiveEnd);
    }
    function focusInput() { dateInput.forceActiveFocus(); }
    onValueChanged: loadValue()
    onAllDayChanged: loadValue()
    onInclusiveEndChanged: loadValue()
    Component.onCompleted: loadValue()

    TextField {
        id: dateInput
        objectName: "eventDateInput"
        Layout.fillWidth: true
        Layout.minimumWidth: Theme.cellW * 12
        placeholderText: "YYYY-MM-DD"
        accessibleName: root.accessibleName + " date"
        accessibleDescription: "Year, month and day"
        onTextEdited: root.edited = true
    }
    TextField {
        id: timeInput
        objectName: "eventTimeInput"
        visible: !root.allDay
        Layout.preferredWidth: Theme.cellW * 9
        placeholderText: "HH:mm"
        accessibleName: root.accessibleName + " time"
        accessibleDescription: "24-hour time in your local time zone"
        onTextEdited: root.edited = true
    }
}
