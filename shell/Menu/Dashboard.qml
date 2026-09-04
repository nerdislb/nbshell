import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Bar.Widgets

// Die Uhr als Eingang in den Alltag: Termine, Wetter und die Dinge,
// die nicht dauerhaft Platz in der Bar brauchen. Angeregt vom Asked Dashboard
// fuer Omarchy, aber vollstaendig auf nbshells vorhandenen Diensten aufgebaut.
PanelWindow {
    id: root

    property int page: 0
    property var weather: ({})
    property bool weatherLoading: false
    property bool updatesOpen: false
    property var afterClose: null
    readonly property date now: clock.date
    readonly property real cardGap: Theme.cellW * 1.5
    readonly property var nextEvents: Calendar.events.filter(e => e.end >= new Date()).slice(0, 7)

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.dashboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        updatesOpen = false;
        Runtime.calendarOpen = false;
        Runtime.dashboardOpen = false;
    }
    function requestClose(done) {
        box.dismiss(() => {
            const next = root.afterClose;
            root.afterClose = null;
            if (!Runtime.dashboardOpen && next) next();
            done();
        });
    }
    function requestOpen() {
        afterClose = null;
        box.enter();
    }
    function openSurface(fn) {
        root.afterClose = fn;
        root.close();
    }
    function refreshWeather() {
        if (weatherLoading)
            return;
        weatherLoading = true;
        weatherProc.running = true;
    }
    function eventWhen(e) {
        const loc = Qt.locale(Config.value("locale", "en_US"));
        const day = e.start.toLocaleString(loc, "ddd dd.MM");
        return e.allDay ? day : day + "  " + e.start.toLocaleTimeString(loc, "HH:mm");
    }

    function weatherGlyph(code, day) {
        if (code === 0) return String.fromCodePoint(day ? 0xE30D : 0xE32B);
        if (code <= 2) return String.fromCodePoint(0xE302);
        if (code === 3) return String.fromCodePoint(0xE312);
        if (code === 45 || code === 48) return String.fromCodePoint(0xE313);
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return String.fromCodePoint(0xE319);
        if (code >= 71 && code <= 86) return String.fromCodePoint(0xE31A);
        if (code >= 95) return String.fromCodePoint(0xE31D);
        return String.fromCodePoint(0xE374);
    }

    onVisibleChanged: if (visible) {
        page = Runtime.dashboardPage;
        Runtime.calendarOpen = page === 1;
        Calendar.ensure(new Date());
        AiUsage.refresh();
        refreshWeather();
        keys.forceActiveFocus();
    } else {
        Runtime.calendarOpen = false;
    }
    onPageChanged: {
        Runtime.dashboardPage = page;
        Runtime.calendarOpen = root.visible && page === 1;
    }

    Connections {
        target: Runtime
        function onDashboardPageChanged() {
            if (root.page !== Runtime.dashboardPage)
                root.page = Runtime.dashboardPage;
        }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Process {
        id: weatherProc
        command: ["bash", "-c",
            "p=\"${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/plugins/wetter/weather.sh\"; "
            + "[ -r \"$p\" ] || exit 44; exec bash \"$p\" current \"$1\" 300", "nbshell-weather", Config.value("weatherPlace", "Wien")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.weather = JSON.parse(text); }
                catch (e) { root.weather = ({ "ok": false, "grund": "Weather data is unreadable" }); }
                root.weatherLoading = false;
            }
        }
        onExited: (code) => {
            if (code !== 0 && code !== 44)
                root.weather = ({ "ok": false, "grund": "Weather request failed" });
            if (code === 44)
                root.weather = ({ "ok": false, "grund": "Weather plugin is not installed" });
            root.weatherLoading = false;
        }
    }

    // Kleine, wiederverwendbare TUI-Karte.
    component Card: PanelSurface {
        property string title: ""
        property string badge: ""
        property var run: null
        property bool primary: false
        default property alias content: body.data
        raised: primary
        border.color: primary ? Theme.panelBorder : "transparent"

        HoverHandler {
            enabled: parent.run !== null
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: parent.run !== null
            onTapped: if (parent.run)
                parent.run()
        }

        Line {
            anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.2
            anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.65
            text: parent.title.toUpperCase(); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; font.bold: true; font.letterSpacing: 0.6
        }
        Line {
            anchors.right: parent.right; anchors.rightMargin: Theme.cellW * 1.2
            anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.65
            text: parent.badge; color: Theme.readable(Theme.accent, Theme.bg); font.pixelSize: Theme.fontCaption
        }
        Column {
            id: body
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.topMargin: Theme.cellH * 2
            anchors.bottom: parent.bottom
            anchors.margins: Theme.cellW * 1.2
            spacing: Theme.cellH * 0.25
        }
    }

    component Action: DashboardAction {}

    Item {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: {
            if (root.updatesOpen)
                root.updatesOpen = false;
            else
                root.close();
        }
        Keys.onPressed: event => {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                root.page = event.key - Qt.Key_1;
                event.accepted = true;
            }
        }
        Rectangle { anchors.fill: parent; z: -1; color: Theme.scrim; opacity: box.opacity * 0.45 }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        OverlaySurface {
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 112
            preferredHeight: Theme.cellH * 38
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                id: dashboardContent
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.55

                Item {
                    width: parent.width
                    height: Theme.cellH * 2.6
                    Column {
                        anchors.left: parent.left
                        Line { text: root.now.toLocaleString(Qt.locale(Config.value("locale", "en_US")), "dddd, dd. MMMM"); color: Theme.fgBright; font.pixelSize: Theme.fontTitle; font.bold: true }
                        Line { text: "WEEK " + Calendar.isoWeek(root.now) + "  ·  " + Calendar.moonName(root.now); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    }
                    Line { anchors.right: parent.right; anchors.top: parent.top; text: root.now.toLocaleTimeString(Qt.locale(), "HH:mm"); color: Theme.readable(Theme.accent, Theme.bg); font.pixelSize: Theme.fontHeading; font.bold: true }
                }

                Row {
                    width: parent.width
                    spacing: Theme.cellW
                    Repeater {
                        model: ["OVERVIEW", "CALENDAR", "TOOLS"]
                        ControlButton {
                            required property var modelData
                            required property int index
                            width: (parent.width - Theme.cellW * 2) / 3
                            height: Theme.cellH * 1.7
                            text: modelData
                            selected: root.page === index
                            textColor: Theme.fgDim
                            onTriggered: root.page = index
                        }
                    }
                }

                // ── TODAY ───────────────────────────────────────────────
                Item {
                    visible: root.page === 0
                    width: parent.width
                    height: parent.height - Theme.cellH * 8.2

                    Row {
                        anchors.fill: parent
                        anchors.margins: root.cardGap
                        spacing: root.cardGap

                        Column {
                            width: (parent.width - root.cardGap) * 0.58
                            height: parent.height
                            spacing: root.cardGap

                            Card {
                            width: parent.width; height: (parent.height - root.cardGap) / 2
                            title: "Upcoming events"
                            primary: true
                            badge: Calendar.loading ? "…" : "OPEN  ·  " + String(root.nextEvents.length)
                            run: () => root.page = 1
                            Line { visible: root.nextEvents.length === 0; text: Calendar.available ? "nothing in the next few days" : Calendar.problem; color: Theme.muted }
                            Repeater {
                                model: root.nextEvents.slice(0, 5)
                                Item {
                                    required property var modelData
                                    width: parent.width; height: Theme.cellH * 1.65
                                    Rectangle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: Theme.borderWidth * 2; height: parent.height * 0.55; color: Theme.accent }
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.33; text: root.eventWhen(parent.modelData); color: Theme.fgDim; elide: Text.ElideRight }
                                    Line { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.64; text: parent.modelData.title; color: Theme.fg; elide: Text.ElideRight }
                                }
                            }
                        }

                            Card {
                            width: parent.width; height: (parent.height - root.cardGap) / 2
                            title: "Weather"
                            badge: root.weather.ok ? String(root.weather.ort || Config.value("weatherPlace", "")) : ""
                            Row {
                                visible: root.weather.ok === true
                                spacing: Theme.cellW * 2
                                Line { text: root.weatherGlyph(root.weather.code || 0, root.weather.tag !== false); color: Theme.accent; font.pixelSize: Theme.fontSize + 24 }
                                Column {
                                    Line { text: Math.round(root.weather.temp) + " °C"; color: Theme.fgBright; font.pixelSize: Theme.fontSize + 8 }
                                    Line { text: "feels like " + root.weather.gefuehlt + " °C"; color: Theme.fgDim }
                                    Line { text: "Wind " + root.weather.wind + " km/h  ·  Humidity " + root.weather.feuchte + " %"; color: Theme.fgDim }
                                }
                            }
                            Line { visible: root.weather.ok !== true; text: root.weatherLoading ? "loading weather …" : (root.weather.grund || "no weather data yet"); color: Theme.muted }
                            Row {
                                visible: root.weather.ok === true
                                spacing: Theme.cellW * 2
                                Repeater {
                                    model: (root.weather.tage || []).slice(0, 5)
                                    Column {
                                        required property var modelData
                                        Line { text: new Date(modelData.datum + "T12:00:00").toLocaleString(Qt.locale(Config.value("locale", "en_US")), "ddd").slice(0, 2); color: Theme.fgDim }
                                        Line { text: root.weatherGlyph(modelData.code || 0, true); color: Theme.accent }
                                        Line { text: Math.round(modelData.max) + "°/" + Math.round(modelData.min) + "°"; color: Theme.fg }
                                    }
                                }
                            }
                            }
                        }

                        Column {
                            width: (parent.width - root.cardGap) * 0.42
                            height: parent.height
                            spacing: root.cardGap

                            Card {
                            width: parent.width; height: (parent.height - root.cardGap * 2) / 3
                            title: "System"
                            badge: SysInfo.uptimeText(SysInfo.detail?.laufzeit ?? 0)
                            Line { text: "CPU  " + String(SysInfo.cpuPercent).padStart(3, " ") + " %"; color: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.fg }
                            LevelBar { width: parent.width; cells: 26; value: SysInfo.cpuPercent; fillColor: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.accent }
                            Line { text: "RAM  " + String(SysInfo.memPercent).padStart(3, " ") + " %   " + SysInfo.memUsedGb.toFixed(1) + "/" + SysInfo.memTotalGb.toFixed(1) + " GB"; color: Theme.fg }
                            LevelBar { width: parent.width; cells: 26; value: SysInfo.memPercent; fillColor: Theme.cyan }
                        }

                            Card {
                            width: parent.width; height: (parent.height - root.cardGap * 2) / 3
                            title: "Today"
                            badge: Todo.count + " open"
                            Line { text: Icons.todo + "  Tasks     " + Todo.count; color: Todo.count > 0 ? Theme.fg : Theme.fgDim }
                            Line { text: Icons.habit + "  Habits " + Habits.doneCount + "/" + Habits.count; color: Habits.doneCount >= Habits.count && Habits.count > 0 ? Theme.green : Theme.fg }
                            Line { text: Icons.download + "  Updates      " + (Updates.checking ? "checking …" : Updates.count); color: Updates.count > 0 ? Theme.yellow : Theme.fgDim }
                        }

                            Card {
                            width: parent.width; height: (parent.height - root.cardGap * 2) / 3
                            title: MediaService.active ? "Now playing" : "Media"
                            badge: MediaService.playing ? "PLAY" : (MediaService.active ? "PAUSE" : "")
                            Line { width: parent.width; text: MediaService.active ? (MediaService.title || "unknown") : "no active player"; color: Theme.fgBright; elide: Text.ElideRight }
                            Line { width: parent.width; text: MediaService.artist; color: Theme.fgDim; elide: Text.ElideRight }
                            Row {
                                visible: MediaService.active
                                spacing: Theme.cellW * 3
                                ActionButton { text: "Previous"; compact: true; onTriggered: MediaService.previous() }
                                ActionButton { text: MediaService.playing ? "Pause" : "Play"; tone: "primary"; compact: true; onTriggered: MediaService.playPause() }
                                ActionButton { text: "Next"; compact: true; onTriggered: MediaService.next() }
                            }
                            }
                        }
                    }
                }

                // ── TOOLS ───────────────────────────────────────────
                Item {
                    visible: root.page === 2
                    width: parent.width
                    height: parent.height - Theme.cellH * 8.2

                    Flow {
                        anchors.centerIn: parent
                        width: Theme.cellW * 84 + root.cardGap * 3
                        height: childrenRect.height
                        spacing: root.cardGap

                        Action { label: "Tasks"; detail: Todo.count + " open"; glyph: Icons.todo; run: () => root.openSurface(() => Runtime.todoOpen = true) }
                        Action { label: "Notes"; detail: Notes.count + " saved"; glyph: "󰎞"; run: () => root.openSurface(() => Runtime.notesOpen = true) }
                        Action { label: "Habits"; detail: Habits.doneCount + "/" + Habits.count + " today"; glyph: Icons.habit; run: () => root.openSurface(() => Runtime.habitsOpen = true) }
                        Action {
                            id: updatesAction
                            readonly property int availableKinds: (Updates.count > 0 ? 1 : 0)
                                + (ShellUpdates.updateAvailable ? 1 : 0)
                                + (ShellUpdates.compositorUpdateAvailable ? 1 : 0)
                            label: "Updates"
                            detail: Updates.checking || ShellUpdates.checking || ShellUpdates.compositorChecking
                                ? "checking all sources …"
                                : (availableKinds > 0 ? availableKinds + " update sources ready" : "system, nbshell and Umbriel current")
                            glyph: Icons.download
                            tone: availableKinds > 0 ? Theme.yellow : Theme.green
                            run: () => {
                                root.updatesOpen = true;
                                if (!Updates.ready)
                                    Updates.refresh();
                                if (!ShellUpdates.ready || !ShellUpdates.compositorReady)
                                    ShellUpdates.refresh();
                            }
                        }
                        Action { label: "Capture"; detail: CaptureService.recording ? "running" : "Screenshot, OCR, QR"; glyph: CaptureService.recording ? Icons.record : Icons.camera; tone: CaptureService.recording ? Theme.red : Theme.accent; run: () => root.openSurface(() => Runtime.captureOpen = true); rightLabel: "Toggle screen recording"; rightRun: () => CaptureService.toggleRecording() }
                        Action { label: "Theme"; detail: Config.theme; glyph: Icons.palette; run: () => root.openSurface(() => Runtime.themePickerOpen = true); rightLabel: "Next theme"; rightRun: () => ThemeIndex.step(1) }
                        Action { label: "Keep awake"; detail: Idle.caffeine ? "active" : "idle automation active"; glyph: Icons.coffee; tone: Idle.caffeine ? Theme.yellow : Theme.fgDim; run: () => Idle.toggleCaffeine() }
                        Action { label: "AI usage"; detail: AiUsage.list.length ? AiUsage.list.map(e => e.id + " " + e.percent + "%").join(" · ") : "no data"; glyph: Icons.cp(0xF1218); run: () => AiUsage.refresh() }
                        Action { label: "System-Hub"; detail: "Services, sync, ports"; glyph: Icons.matrix; run: () => root.openSurface(() => Runtime.hubOpen = true) }
                        Action { label: "Modules"; detail: "Arrange the bar"; glyph: Icons.cp(0xF12E); run: () => root.openSurface(() => Runtime.modulesOpen = true) }
                        Action { label: "Clipboard"; detail: Clipboard.entries.length + " entries"; glyph: Icons.clipboard; run: () => root.openSurface(() => Runtime.clipOpen = true) }
                        Action { label: "Audio"; detail: "Mixer and equalizer"; glyph: Icons.volumeHigh; run: () => root.openSurface(() => Runtime.audioToolsOpen = true) }
                        Action { label: "Displays"; detail: Displays.outputs.length + " connected"; glyph: Displays.outputs.length > 1 ? Icons.monitors : Icons.monitor; run: () => root.openSurface(() => Runtime.displayOpen = true) }
                        Action { label: "Settings"; detail: "Appearance and behavior"; glyph: Icons.cp(0xF0493); run: () => root.openSurface(() => Runtime.settingsOpen = true) }
                    }
                }

                // ── CALENDAR ─────────────────────────────────────────
                // The month view predates the dashboard. Keeping it as one
                // shared component preserves khal/vdirsyncer events, calendar
                // colours and day markers instead of introducing a second
                // calendar implementation just for this surface.
                Item {
                    visible: root.page === 1
                    width: parent.width
                    height: parent.height - Theme.cellH * 8.2

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: root.cardGap
                        clip: true
                        contentWidth: width
                        contentHeight: calendarPanel.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        CalendarPanel {
                            id: calendarPanel
                            x: Math.round((parent.width - width) / 2)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.cellH * 2.2

                    Line {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Esc closes  ·  1–3 switch pages  ·  R marks a right-click action"
                        color: Theme.muted
                    }
                }
            }

            // The dashboard and the clock-adjacent bar signal share one update
            // surface. System packages, nbshell and Umbriel therefore keep the
            // same hierarchy, states and actions everywhere.
            ModalSurface {
                id: updatesModal

                visible: root.updatesOpen
                z: 20
                blockedItem: dashboardContent
                initialFocusItem: updatePanel.initialFocusItem
                restoreFocusItem: updatesAction
                dialogTitle: qsTr("Updates")
                dialogDescription: qsTr("Review and install available system, nbshell, and Umbriel updates")
                preferredWidth: Theme.cellW * 72
                preferredHeight: updatePanel.implicitHeight + Theme.panelPadding * 2
                edgeMarginX: root.cardGap * 2
                edgeMarginY: root.cardGap * 2
                scrimRadius: box.radius
                onCloseRequested: root.updatesOpen = false

                UpdatePanel {
                    id: updatePanel
                    anchors.centerIn: parent
                    rowWidth: parent.width - Theme.panelPadding * 2
                    showClose: true
                    closePanel: () => root.updatesOpen = false
                }
            }
        }
    }
}
