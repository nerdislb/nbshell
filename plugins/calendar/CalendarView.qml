import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Common
import qs.Widgets
import "Dates.js" as Dates

FocusScope {
    id: root
    required property var backend
    property date anchor: new Date()
    property string mode: "Month"
    property bool showCalendars: false
    readonly property bool monthGrid: mode === "Month" && width >= Theme.cellW * 65
    property string page: "calendar"
    property var selectedEvent: null
    property var destination: null
    property bool allDay: false
    property string editorError: ""
    onEditorErrorChanged: { if (editorError) scroll.contentItem.contentY = 0; }
    property string provider: "icloud"
    property string confirmation: ""
    property var pending: ({})
    readonly property var days: Dates.days(anchor, mode)
    readonly property var visibleEvents: backend.events.filter(e => backend.calendars.some(c => c.key === e.calendarKey && c.visible))
    readonly property var focusedItem: root.Window.window ? root.Window.window.activeFocusItem : null
    onFocusedItemChanged: Qt.callLater(revealFocus)
    onPageChanged: { scroll.contentItem.contentY = 0; Qt.callLater(revealFocus); }
    function revealFocus() {
        const item = focusedItem;
        if (!item || !item.visible) return;
        let ancestor = item;
        while (ancestor && ancestor !== root) ancestor = ancestor.parent;
        if (!ancestor) return;
        const viewport = scroll.contentItem;
        const top = item.mapToItem(content, 0, 0).y;
        const margin = Theme.spaceSm;
        let y = viewport.contentY;
        if (top < y + margin) y = top - margin;
        else if (top + item.height > y + viewport.height - margin) y = top + item.height - viewport.height + margin;
        viewport.contentY = Math.max(0, Math.min(Math.max(0, viewport.contentHeight - viewport.height), y));
    }
    signal closeRequested()

    function calendarLabel(calendar) {
        const duplicate = backend.calendars.filter(c => c.name === calendar.name).length > 1;
        const account = backend.accounts.find(a => a.id === calendar.account);
        return duplicate ? (account ? account.name : calendar.account) + " / " + calendar.name : calendar.name;
    }
    function calendarTone(key) {
        const tones = [Theme.accent, Theme.green, Theme.yellow, Theme.blue, Theme.magenta];
        return tones[Math.max(0, backend.calendars.findIndex(c => c.key === key)) % tones.length];
    }
    function refresh() {
        backend.refresh(Dates.add(days[0], -1).toISOString(), Dates.add(days[days.length - 1], 2).toISOString());
    }
    function clearSecrets() { password.clear(); clientSecret.clear(); }
    function back() {
        if (confirmation) { confirmation = ""; pending = ({}); }
        else if (page !== "calendar") { page = "calendar"; password.clear(); clientSecret.clear(); }
        else closeRequested();
        Qt.callLater(() => refreshButton.forceActiveFocus());
    }
    function browse(delta) {
        anchor = mode === "Month" ? new Date(anchor.getFullYear(), anchor.getMonth() + delta, 1) : Dates.add(anchor, delta * (mode === "Week" ? 7 : 14));
        refresh();
    }
    function edit(event) {
        editorError = "";
        selectedEvent = event;
        destination = event ? backend.calendars.find(c => c.account === event.account && c.id === event.calendar) : null;
        titleField.text = event ? event.title : "";
        allDay = event ? event.allDay : false;
        startField.text = event ? event.start : Dates.timed(anchor, 9);
        endField.text = event ? event.end : Dates.timed(anchor, 10);
        startField.loadValue(); endField.loadValue();
        page = "editor";
        Qt.callLater(() => titleField.forceActiveFocus());
    }
    function toggleAllDay() {
        try {
            const fields = Dates.toggle(startField.serializedValue(), endField.serializedValue(), allDay);
            startField.text = fields[0]; endField.text = fields[1];
            allDay = !allDay; editorError = "";
        } catch (error) { editorError = error.message; }
    }
    function writableDestination(operation, target, event) {
        const account = target && backend.accounts.find(a => a.id === target.account);
        const calendar = target && backend.calendars.find(c => c.account === target.account && c.id === target.id);
        if (!account || !calendar || !calendar.writable || backend.stale || backend.busy)
            throw new Error("Destination unavailable. Refresh and choose a writable calendar.");
        if (["create", "edit", "delete"].indexOf(operation) < 0 ||
            (operation === "create" ? !!event : !event) ||
            (event && (event.blocked || !event.writable || event.account !== calendar.account || event.calendar !== calendar.id)))
            throw new Error("This event is view only or no longer available. Reopen it after refresh.");
        const live = event && backend.events.find(e => e.account === event.account && e.calendar === event.calendar && e.id === event.id && e.start === event.start);
        if (event && (!live || live.blocked || !live.writable || live.etag !== event.etag))
            throw new Error("This event changed. Refresh and reopen it.");
        return {account: account, calendar: calendar};
    }
    function prepare(operation) {
        if (confirmation) return;
        pending = ({});
        try {
            const live = writableDestination(operation, destination, selectedEvent);
            if (operation !== "delete") {
                if (!titleField.text.trim() || titleField.text.trim().length > 1024) throw new Error("Enter a title of at most 1024 characters.");
                Dates.range(startField.serializedValue(), endField.serializedValue(), allDay);
            }
            pending = {op: operation, account: live.account.id, calendar: live.calendar.id,
                event: selectedEvent || {}, draft: {title: titleField.text, start: startField.serializedValue(), end: endField.serializedValue(), allDay: allDay}, confirmed: true};
            confirmation = (operation === "delete" ? "Delete “" : "Save “") + titleField.text + "” in " + live.account.name + " / " + live.calendar.name + "?";
            editorError = "";
            Qt.callLater(() => cancelConfirmation.forceActiveFocus());
        } catch (error) { editorError = error.message; }
    }
    function prepareDisconnect(accountId) {
        if (confirmation || backend.busy) return;
        const account = backend.accounts.find(a => a.id === accountId);
        if (!account) { editorError = "Account no longer available."; return; }
        pending = {op: "disconnect", account: account.id, confirmed: true};
        confirmation = "Remove “" + account.name + "” and its saved secret? Remote calendars are retained.";
        Qt.callLater(() => cancelConfirmation.forceActiveFocus());
    }
    function confirmPending() {
        try {
            if (!confirmation || backend.busy) return;
            if (pending.op === "disconnect") {
                if (!backend.accounts.some(a => a.id === pending.account)) throw new Error("Account no longer available.");
            } else writableDestination(pending.op, {account: pending.account, id: pending.calendar}, pending.op === "create" ? null : pending.event);
            backend.run(pending);
        } catch (error) { editorError = error.message; }
        pending = ({}); confirmation = "";
    }
    function connectAccount() {
        backend.run({op: "connect", provider: provider, name: accountName.text, username: username.text,
            password: password.text, clientId: clientId.text, clientSecret: clientSecret.text});
        password.clear(); clientSecret.clear();
    }
    Keys.onEscapePressed: back()
    Connections {
        target: root.backend
        function onChanged(operation) {
            if (["create", "edit", "delete"].indexOf(operation) >= 0) root.page = "calendar";
            root.confirmation = "";
            refreshAfterChange.restart();
        }
    }
    Timer { id: refreshAfterChange; interval: 0; onTriggered: { if (!root.backend.busy) root.refresh(); else restart(); } }

    Controls.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            id: content
            width: scroll.availableWidth
            spacing: Theme.spaceSm
            GridLayout {
                Layout.fillWidth: true
                columns: root.width >= Theme.cellW * 70 ? 2 : 1
                columnSpacing: Theme.spaceLg
                rowSpacing: Theme.spaceSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceXs
                    Line { Layout.fillWidth: true; elide: Text.ElideRight; text: root.page === "calendar" ? root.anchor.toLocaleDateString(Qt.locale(), "MMMM yyyy") : root.page === "editor" ? (root.selectedEvent ? "Event details" : "New event") : "Accounts"; font.pixelSize: Theme.fontHeading }
                    Line {
                        Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontCaption
                        color: root.backend.stale ? Theme.red : Theme.fgDim
                        text: root.backend.busy ? "Syncing calendars…" : root.backend.stale ? "Offline · refresh to make changes" : root.backend.loadedAt ? "Synced " + new Date(root.backend.loadedAt).toLocaleTimeString(Qt.locale(), "HH:mm") : "Ready to sync"
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: Theme.cellW * 54
                    Layout.maximumWidth: root.width >= Theme.cellW * 70 ? Theme.cellW * 54 : Number.POSITIVE_INFINITY
                    Layout.alignment: Qt.AlignRight
                    spacing: Theme.spaceSm
                    ControlButton { text: root.page === "calendar" ? "Close" : "Back"; onTriggered: root.back() }
                    ControlButton { visible: root.backend.busy; text: "Cancel"; onTriggered: root.backend.cancel() }
                    ControlButton { id: refreshButton; text: "Refresh"; enabled: !root.backend.busy; onTriggered: root.refresh() }
                    ControlButton { text: "Accounts"; onTriggered: { root.page = "accounts"; Qt.callLater(() => accountName.forceActiveFocus()); } }
                    ControlButton { text: "+ Event"; selected: true; enabled: !root.backend.busy && !root.backend.stale && root.backend.calendars.some(c => c.writable); onTriggered: root.edit(null) }
                }
            }
            Line { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: text.length > 0; objectName: "errorBanner"; text: [root.backend.error, root.editorError].filter(e => e.length > 0).join("\n"); color: Theme.red }
            Line { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: root.backend.authorizationUrl.length > 0 && root.backend.busy; text: "Finish Google consent in your browser. Waiting up to three minutes." }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.confirmation.length > 0
                Line { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.confirmation }
                Flow {
                    Layout.fillWidth: true; spacing: Theme.spaceSm
                    ControlButton { id: cancelConfirmation; text: "Cancel"; onTriggered: { root.confirmation = ""; root.pending = ({}); } }
                    ControlButton { text: "Confirm"; danger: true; enabled: !root.backend.busy; onTriggered: { root.confirmPending(); } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.page === "calendar"
                spacing: Theme.spaceSm
                GridLayout {
                    Layout.fillWidth: true
                    columns: root.width >= Theme.cellW * 70 ? 2 : 1
                    rowSpacing: Theme.spaceSm
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spaceXs
                        ControlButton { text: "‹"; accessibleName: "Previous period"; enabled: !root.backend.busy; onTriggered: root.browse(-1) }
                        ControlButton { text: "Today"; enabled: !root.backend.busy; onTriggered: { root.anchor = new Date(); root.refresh(); } }
                        ControlButton { text: "›"; accessibleName: "Next period"; enabled: !root.backend.busy; onTriggered: root.browse(1) }
                        ControlButton { text: "Calendars"; selected: root.showCalendars; onTriggered: root.showCalendars = !root.showCalendars }
                    }
                    Segments { Layout.fillWidth: true; rowWidth: width; enabled: !root.backend.busy; options: ["Month", "Week", "Agenda"]; current: root.mode; onChosen: value => { root.mode = value; root.refresh(); } }
                }
                Flow {
                    Layout.fillWidth: true; spacing: Theme.spaceXs; visible: root.showCalendars
                    Repeater {
                        model: root.backend.calendars
                        ControlButton {
                            required property var modelData
                            width: Math.min(implicitWidth, parent.width)
                            clip: true
                            text: root.calendarLabel(modelData)
                            textColor: Theme.readable(root.calendarTone(modelData.key), Theme.panelSurface, 4.5)
                            selected: modelData.visible
                            enabled: !root.backend.busy
                            onTriggered: root.backend.run({op: "visibility", calendar: modelData.key, visible: !modelData.visible})
                        }
                    }
                }
                Line { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: root.backend.accounts.length === 0; text: "Your days, in one place. Open Accounts to connect a calendar."; color: Theme.fgDim }
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.monthGrid
                    columns: 7; columnSpacing: Theme.spaceXs
                    Repeater {
                        model: root.days.slice(0, 7)
                        Line {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredWidth: 0
                            text: modelData.toLocaleDateString(Qt.locale(), "ddd").toUpperCase()
                            color: Theme.fgDim; font.pixelSize: Theme.fontCaption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
                GridLayout {
                    id: calendarGrid
                    Layout.fillWidth: true
                    columns: root.monthGrid ? 7 : 1
                    columnSpacing: Theme.spaceXs; rowSpacing: Theme.spaceXs
                    Repeater {
                        model: root.days
                        PanelSurface {
                            id: dayCell
                            required property var modelData
                            readonly property var entries: root.visibleEvents.filter(e => Dates.touches(e, modelData)).sort((a,b) => Number(b.allDay) - Number(a.allDay) || Dates.date(a.start) - Dates.date(b.start))
                            readonly property bool today: Dates.iso(modelData) === Dates.iso(new Date())
                            readonly property bool outside: modelData.getMonth() !== root.anchor.getMonth()
                            readonly property int capacity: Math.max(1, Math.floor((implicitHeight - Theme.cellH - Theme.controlHeight - Theme.spaceXs * 4) / (Theme.cellH * 2 + Theme.spaceXs)))
                            readonly property int fullCapacity: Math.max(1, Math.floor((implicitHeight - Theme.cellH - Theme.spaceXs * 3) / (Theme.cellH * 2 + Theme.spaceXs)))
                            readonly property int shownCount: root.monthGrid ? (entries.length <= fullCapacity ? entries.length : Math.min(entries.length, capacity)) : entries.length
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            Layout.alignment: Qt.AlignTop
                            implicitHeight: root.monthGrid ? Math.max(Theme.cellH * 3 + Theme.controlHeight + Theme.spaceXs * 4, Math.min(Theme.cellH * 6, (root.height - Theme.cellH * 8 - (root.showCalendars ? Theme.controlHeight * 2 : 0)) / (root.days.length / 7))) : dayContent.implicitHeight + Theme.spaceSm * 2
                            accentBorder: today
                            color: today ? Theme.selectedSurface(Theme.accent) : outside && root.monthGrid ? Theme.panelSurface : Theme.panelSurfaceRaised
                            ColumnLayout {
                                id: dayContent
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spaceXs }
                                spacing: Theme.spaceXs
                                RowLayout {
                                    Layout.fillWidth: true
                                    Line {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: root.monthGrid ? dayCell.modelData.getDate() : dayCell.modelData.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                                        color: dayCell.today ? Theme.accent : dayCell.outside && root.monthGrid ? Theme.fgDim : Theme.fg
                                        font.bold: dayCell.today
                                    }
                                    Line { visible: dayCell.today && !root.monthGrid; text: "TODAY"; color: Theme.accent; font.pixelSize: Theme.fontCaption }
                                }
                                Line { visible: dayCell.entries.length === 0 && !root.monthGrid; text: "No events"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                                Repeater {
                                    model: dayCell.entries.slice(0, dayCell.shownCount)
                                    CalendarEvent {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        event: modelData
                                        tone: root.calendarTone(modelData.calendarKey)
                                        compact: root.monthGrid
                                        onTriggered: root.edit(modelData)
                                    }
                                }
                                ControlButton {
                                    visible: dayCell.entries.length > dayCell.shownCount
                                    Layout.fillWidth: true
                                    clip: true
                                    text: "+" + (dayCell.entries.length - dayCell.shownCount)
                                    accessibleName: "Show all events on " + dayCell.modelData.toLocaleDateString(Qt.locale(), Locale.LongFormat)
                                    onTriggered: { root.anchor = dayCell.modelData; root.mode = "Agenda"; root.refresh(); }
                                }
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.page === "accounts"
                SectionHeader { Layout.fillWidth: true; text: "Accounts and calendar visibility" }
                Repeater {
                    model: root.backend.accounts
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Line { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.name + " · " + modelData.provider }
                        ControlButton { text: "Disconnect…"; enabled: !root.backend.busy; onTriggered: { root.prepareDisconnect(modelData.id); } }
                    }
                }
                Repeater {
                    model: root.backend.calendars
                    PanelRow {
                                        interactive: true
                        required property var modelData
                        Layout.fillWidth: true
                        title: (modelData.visible ? "[x] " : "[ ] ") + modelData.name + (modelData.writable ? "" : " · read only")
                        enabled: !root.backend.busy
                        onTriggered: root.backend.run({op: "visibility", calendar: modelData.key, visible: !modelData.visible})
                    }
                }
                SectionHeader { Layout.fillWidth: true; text: "Connect an independent account" }
                Segments { Layout.fillWidth: true; rowWidth: width; options: [{label: "iCloud", value: "icloud"}, {label: "Google", value: "google"}]; current: root.provider; onChosen: value => { root.provider = value; password.clear(); clientSecret.clear(); } }
                TextField { id: accountName; Layout.fillWidth: true; placeholderText: "Account label" }
                TextField { id: username; Layout.fillWidth: true; visible: root.provider === "icloud"; placeholderText: "Apple Account email" }
                TextField { id: password; Layout.fillWidth: true; visible: root.provider === "icloud"; placeholderText: "App-specific password"; password: true }
                Line { Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.provider === "icloud" ? "Create an app-specific password in your Apple Account. CalDAV discovery uses iCloud only. The password is saved in desktop Secret Service." : "Supply your Google Desktop OAuth client. Calendar event and calendar-list permissions are required. Browser consent follows; no Mail access is requested." }
                TextField { id: clientId; Layout.fillWidth: true; visible: root.provider === "google"; placeholderText: "Google Desktop OAuth client ID" }
                TextField { id: clientSecret; Layout.fillWidth: true; visible: root.provider === "google"; placeholderText: "Google OAuth client secret"; password: true }
                ControlButton { text: root.provider === "google" ? "Sign in with Google…" : "Connect iCloud"; enabled: !root.backend.busy; onTriggered: root.connectAccount() }
                ControlButton { text: "Back"; onTriggered: root.back() }
            }
            ColumnLayout {
                Layout.fillWidth: true; visible: root.page === "editor"
                Line { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Calendar"; color: Theme.fgDim }
                Flow {
                    Layout.fillWidth: true; spacing: Theme.spaceXs
                    Repeater {
                        model: root.backend.calendars.filter(c => c.writable && (!root.selectedEvent || (c.id === root.selectedEvent.calendar && c.account === root.selectedEvent.account)))
                        ControlButton {
                            required property var modelData
                            width: Math.min(implicitWidth, parent.width)
                            clip: true
                            text: root.calendarLabel(modelData)
                            selected: !!root.destination && root.destination.key === modelData.key
                            accessibleName: (root.backend.accounts.find(a => a.id === modelData.account)?.name || "") + " / " + modelData.name
                            onTriggered: root.destination = modelData
                        }
                    }
                }
                Line { Layout.fillWidth: true; wrapMode: Text.Wrap; visible: !!root.selectedEvent && (root.selectedEvent.blocked || !root.selectedEvent.writable); text: "View only: read-only calendar, recurrence or scheduled meeting. Use the provider app to change it." }
                Line { text: "Title" }
                TextField { id: titleField; objectName: "titleField"; Layout.fillWidth: true; placeholderText: "Title" }
                ControlButton { text: root.allDay ? "[x] All day" : "[ ] All day"; onTriggered: root.toggleAllDay() }
                Line { text: "Start" }
                EventTimeField { id: startField; objectName: "startField"; Layout.fillWidth: true; allDay: root.allDay; accessibleName: "Start" }
                Line { text: root.allDay ? "Last day" : "End" }
                EventTimeField { id: endField; objectName: "endField"; Layout.fillWidth: true; allDay: root.allDay; inclusiveEnd: true; accessibleName: root.allDay ? "Last day" : "End" }
                Line { text: "Times use your local time zone · 24-hour format"; visible: !root.allDay; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Flow {
                    Layout.fillWidth: true; spacing: Theme.spaceSm
                    ControlButton { text: "Save…"; enabled: !!root.destination && root.destination.writable && !root.backend.stale && !root.backend.busy && (!root.selectedEvent || !root.selectedEvent.blocked); onTriggered: root.prepare(root.selectedEvent ? "edit" : "create") }
                    ControlButton { text: "Delete…"; danger: true; visible: !!root.selectedEvent; enabled: !!root.destination && root.destination.writable && !root.backend.stale && !root.backend.busy && !root.selectedEvent?.blocked; onTriggered: root.prepare("delete") }
                    ControlButton { text: "Back"; onTriggered: root.back() }
                }
            }
        }
    }
}
