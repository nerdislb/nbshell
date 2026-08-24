import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Bar.Widgets

// Die Uhr als Eingang in den Alltag: Termine, Wetter, Media und die Dinge,
// die nicht dauerhaft Platz in der Bar brauchen. Angeregt vom Asked Dashboard
// fuer Omarchy, aber vollstaendig auf nbshells vorhandenen Diensten aufgebaut.
PanelWindow {
    id: root

    property int page: 0
    property var weather: ({})
    property bool weatherLoading: false
    property bool updatesOpen: false
    property bool shellUpdatesOpen: false
    readonly property date now: clock.date
    readonly property real cardGap: Theme.cellW * 1.5
    readonly property var nextEvents: Calendar.events.filter(e => e.end >= new Date()).slice(0, 7)

    visible: Runtime.dashboardOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        updatesOpen = false;
        shellUpdatesOpen = false;
        Runtime.calendarOpen = false;
        Runtime.dashboardOpen = false;
    }
    function openSurface(fn) {
        root.close();
        Qt.callLater(fn);
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
    function updateText(entry) {
        return entry.from === entry.to
            ? entry.name + "   " + entry.to + "  (new build)"
            : entry.name + "   " + entry.from + " → " + entry.to;
    }
    function compositorRevision(project, field) {
        const projects = ShellUpdates.compositorProjects || ({});
        const row = projects[project];
        return row && row[field] !== undefined ? row[field] : "unknown";
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
        Runtime.calendarOpen = page === 3;
        Calendar.ensure(new Date());
        AiUsage.refresh();
        refreshWeather();
        keys.forceActiveFocus();
    } else {
        Runtime.calendarOpen = false;
    }
    onPageChanged: {
        Runtime.dashboardPage = page;
        Runtime.calendarOpen = root.visible && page === 3;
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
        default property alias content: body.data
        raised: true

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

    component Action: Rectangle {
        id: action
        property string label: ""
        property string detail: ""
        property string glyph: ""
        property color tone: Theme.accent
        property var run: null
        property var rightRun: null
        property bool centered: false
        width: Theme.cellW * 21
        height: Theme.cellH * 3.2
        radius: Theme.radius
        color: Theme.controlFill(actionHover.hovered, false, actionTap.pressed)
        border.width: Theme.borderWidth
        border.color: actionHover.hovered ? action.tone : Theme.controlBorder(false, false, false)

        Line { visible: !action.centered; anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.55; text: action.glyph + (action.glyph !== "" ? "  " : "") + action.label; color: action.tone; font.pixelSize: Theme.fontBody; font.bold: true }
        Line { visible: !action.centered; anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.right: rightHint.left; anchors.rightMargin: Theme.cellW * 0.5; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.cellH * 0.45; text: action.detail; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
        Line { id: rightHint; visible: !action.centered && action.rightRun !== null; anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.cellH * 0.45; text: "R"; color: Theme.muted }
        Column {
            visible: action.centered
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spaceXs
            Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: action.glyph + (action.glyph !== "" ? "  " : "") + action.label; color: action.tone; font.pixelSize: Theme.fontBody; font.bold: true }
            Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: action.detail; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
        }
        HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: actionTap
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => {
                if (button === Qt.RightButton && action.rightRun)
                    action.rightRun();
                else if (button === Qt.LeftButton && action.run)
                    action.run();
            }
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: {
            if (root.shellUpdatesOpen)
                root.shellUpdatesOpen = false;
            else if (root.updatesOpen)
                root.updatesOpen = false;
            else
                root.close();
        }
        Keys.onPressed: event => {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                root.page = event.key - Qt.Key_1;
                event.accepted = true;
            }
        }
        Rectangle { anchors.fill: parent; z: -1; color: Theme.scrim }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        OverlaySurface {
            preferredWidth: Theme.cellW * 104
            preferredHeight: Theme.overlayHeightLarge
            border.width: Math.max(Theme.borderWidth, 2)
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.55

                Item {
                    width: parent.width
                    height: Theme.cellH * 3.5
                    Column {
                        anchors.left: parent.left
                        Line { text: root.now.toLocaleString(Qt.locale(Config.value("locale", "en_US")), "dddd, dd. MMMM"); color: Theme.fgBright; font.pixelSize: Theme.fontHeading; font.bold: true }
                        Line { text: "WEEK " + Calendar.isoWeek(root.now) + "  ·  " + Calendar.moonName(root.now); color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                    }
                    Line { anchors.right: parent.right; anchors.top: parent.top; text: root.now.toLocaleTimeString(Qt.locale(), "HH:mm"); color: Theme.readable(Theme.accent, Theme.bg); font.pixelSize: Theme.fontDisplay; font.bold: true }
                }

                Row {
                    width: parent.width
                    spacing: Theme.cellW
                    Repeater {
                        model: ["TODAY", "MEDIA", "TOOLS", "CALENDAR"]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: (parent.width - Theme.cellW * 3) / 4
                            height: Theme.cellH * 1.7
                            color: Theme.controlFill(tabHover.hovered, root.page === index, tabTap.pressed)
                            border.width: Theme.borderWidth
                            border.color: Theme.controlBorder(tabHover.hovered, root.page === index, false)
                            Line { anchors.centerIn: parent; text: parent.modelData; color: root.page === parent.index ? Theme.selectedForeground(Theme.accent) : Theme.fgDim; font.bold: root.page === parent.index }
                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: tabTap; onTapped: root.page = parent.index }
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
                            badge: Calendar.loading ? "…" : "OPEN  ·  " + String(root.nextEvents.length)
                            run: () => root.page = 3
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

                // ── MEDIA ──────────────────────────────────────────────
                Item {
                    visible: root.page === 1
                    width: parent.width
                    height: parent.height - Theme.cellH * 8.2

                    Column {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -Theme.cellH * 1.5
                        width: Math.min(parent.width - root.cardGap * 2, Theme.cellW * 76)
                        spacing: root.cardGap

                        Item {
                            width: parent.width; height: Theme.cellH * 17
                            PanelSurface {
                                width: parent.height; height: parent.height; anchors.centerIn: parent
                                accentBorder: false
                                Image { anchors.fill: parent; anchors.margins: Theme.borderWidth; source: MediaService.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                Line { anchors.centerIn: parent; visible: (MediaService.player?.trackArtUrl ?? "") === ""; text: Icons.play; color: Theme.muted; font.pixelSize: Theme.fontSize + 40 }
                            }
                        }

                        PanelSurface {
                            width: parent.width; height: Theme.cellH * 11.5
                            accentBorder: false
                            Column {
                                anchors.fill: parent; anchors.margins: Theme.cellW * 1.5
                                spacing: Theme.cellH * 0.35
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.active ? (MediaService.title || "Unknown title") : "No active player"; color: Theme.fgBright; font.pixelSize: Theme.fontHeading; elide: Text.ElideRight }
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.artist; color: Theme.fgDim; elide: Text.ElideRight }
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.zeit(MediaService.position) + "  /  " + MediaService.zeit(MediaService.length); color: Theme.fgDim }
                                LevelBar { width: parent.width; cells: 56; value: MediaService.length > 0 ? 100 * MediaService.position / MediaService.length : 0; fillColor: Theme.accent }
                                Row {
                                    width: parent.width
                                    spacing: Theme.cellW * 2
                                    Action { centered: true; width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: "Previous"; glyph: Icons.cp(0xF04AE); detail: "previous track"; run: () => MediaService.previous() }
                                    Action { centered: true; width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: MediaService.playing ? "Pause" : "Play"; glyph: MediaService.playing ? Icons.pause : Icons.play; detail: MediaService.playing ? "pause playback" : "resume playback"; run: () => MediaService.playPause() }
                                    Action { centered: true; width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: "Next"; glyph: Icons.cp(0xF04AD); detail: "next track"; run: () => MediaService.next() }
                                }
                                Line { visible: MediaService.volumeSupported; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "PLAYER VOLUME  " + Math.round(MediaService.volume * 100) + " %"; color: Theme.fgDim }
                                Item {
                                    visible: MediaService.volumeSupported
                                    width: parent.width
                                    height: visible ? Theme.cellH : 0
                                    LevelBar {
                                        anchors.centerIn: parent
                                        width: implicitWidth
                                        cells: 56
                                        value: MediaService.volume * 100
                                        fillColor: Theme.cyan
                                        interactive: true
                                        onMoved: value => MediaService.setVolume(value / 100)
                                    }
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
                            label: "System updates"
                            detail: Updates.rebootRecommended ? "restart recommended" : (Updates.checking ? "checking …" : Updates.count + " available")
                            glyph: Icons.download
                            tone: Updates.count > 0 ? Theme.yellow : Theme.green
                            run: () => {
                                root.updatesOpen = true;
                                if (!Updates.ready)
                                    Updates.refresh();
                            }
                            rightRun: () => root.openSurface(() => Updates.update())
                        }
                        Action {
                            label: "Desktop updates"
                            detail: ShellUpdates.checking || ShellUpdates.compositorChecking ? "checking releases …"
                                : (ShellUpdates.anyUpdateAvailable ? "updates available"
                                : (ShellUpdates.ready && ShellUpdates.compositorReady ? "nbshell and Umbriel current" : "published releases"))
                            glyph: Icons.refresh
                            tone: ShellUpdates.anyUpdateAvailable ? Theme.yellow : Theme.green
                            run: () => {
                                root.shellUpdatesOpen = true;
                                if (!ShellUpdates.ready || !ShellUpdates.compositorReady)
                                    ShellUpdates.refresh();
                            }
                            rightRun: (ShellUpdates.updateAvailable && ShellUpdates.installable)
                                || (ShellUpdates.compositorUpdateAvailable && ShellUpdates.compositorInstallable)
                                ? () => root.openSurface(() => ShellUpdates.installAll()) : null
                        }
                        Action { label: "Capture"; detail: CaptureService.recording ? "running" : "Screenshot, OCR, QR"; glyph: CaptureService.recording ? Icons.record : Icons.camera; tone: CaptureService.recording ? Theme.red : Theme.accent; run: () => root.openSurface(() => Runtime.captureOpen = true); rightRun: () => CaptureService.toggleRecording() }
                        Action { label: "Theme"; detail: Config.theme; glyph: Icons.palette; run: () => root.openSurface(() => Runtime.themePickerOpen = true); rightRun: () => ThemeIndex.step(1) }
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
                    visible: root.page === 3
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
                        text: "Esc closes  ·  1–4 switch pages  ·  R marks a right-click action"
                        color: Theme.muted
                    }
                }
            }

            // Update-Liste wie im frueheren Bar-Popout, aber als Ebene im
            // Dashboard: dieselben Daten, derselbe Check, kein zweiter Poller.
            Rectangle {
                anchors.fill: parent
                visible: root.updatesOpen
                z: 20
                color: Theme.alpha(Theme.bg, 0.82)
                radius: parent.radius

                MouseArea { anchors.fill: parent; onClicked: root.updatesOpen = false }

                PanelSurface {
                    width: Math.min(parent.width - root.cardGap * 4, Theme.cellW * 78)
                    height: Math.min(parent.height - root.cardGap * 4, Theme.cellH * 34)
                    anchors.centerIn: parent
                    accentBorder: false
                    MouseArea { anchors.fill: parent; onClicked: {} }

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.cellW * 2
                        spacing: Theme.cellH * 0.55

                        Item {
                            width: parent.width; height: Theme.cellH * 2
                            Line {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: "UPDATES  (" + Updates.count + ")"; color: Theme.fgBright; font.pixelSize: Theme.fontHeading
                            }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.cellW * 2
                                ActionButton {
                                    text: Updates.checking ? "Checking …" : "Check again"
                                    busy: Updates.checking; compact: true
                                    onTriggered: Updates.refresh()
                                }
                                ActionButton {
                                    visible: Updates.count > 0
                                    text: "Update"; tone: "primary"; accentColor: Theme.green; compact: true
                                    onTriggered: root.openSurface(() => Updates.update())
                                }
                                ActionButton { text: "Close"; compact: true; onTriggered: root.updatesOpen = false }
                            }
                        }

                        Rule { rowWidth: parent.width; label: "PACKAGES" }

                        Rectangle {
                            visible: Updates.rebootRecommended
                            width: parent.width
                            height: visible ? Theme.controlHeight * 1.45 : 0
                            color: Theme.selectedSurface(Theme.yellow)
                            border.width: Theme.borderWidth
                            border.color: Theme.yellow
                            radius: Theme.radius

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spaceMd
                                anchors.rightMargin: Theme.spaceSm
                                spacing: Theme.spaceMd

                                Line {
                                    width: parent.width - restartButton.width - parent.spacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Restart recommended" + (Updates.rebootPackages.length ? " · " + Updates.rebootPackages.join(", ") : "")
                                    color: Theme.readable(Theme.yellow, Theme.selectedSurface(Theme.yellow), 4.5)
                                    elide: Text.ElideRight
                                }
                                ActionButton {
                                    id: restartButton
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Restart…"
                                    tone: "primary"
                                    compact: true
                                    onTriggered: root.openSurface(() => Runtime.powerOpen = true)
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: parent.height - Theme.cellH * 6.6 - (Updates.rebootRecommended ? Theme.controlHeight * 1.45 + Theme.cellH * 0.55 : 0)

                            Line {
                                anchors.centerIn: parent
                                visible: Updates.count === 0
                                text: Updates.checking ? "Checking package sources …" : (Updates.ready ? "everything is up to date" : "not checked yet")
                                color: Theme.muted
                            }

                            Flickable {
                                anchors.fill: parent
                                visible: Updates.count > 0
                                clip: true
                                contentHeight: updateRows.height
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: updateRows
                                    width: parent.width
                                    spacing: Theme.cellH * 0.25
                                    Repeater {
                                        model: Updates.repo.concat(Updates.aur).concat(Updates.flatpak)
                                        Line {
                                            required property var modelData
                                            width: updateRows.width
                                            text: "  " + root.updateText(modelData)
                                            color: Theme.fg
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        Line {
                            width: parent.width
                            text: Updates.repo.length + " Repo  ·  " + Updates.aur.length + " AUR  ·  " + Updates.flatpak.length + " Flatpak"
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.muted
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.shellUpdatesOpen
                z: 21
                color: Theme.alpha(Theme.bg, 0.82)
                radius: parent.radius

                MouseArea { anchors.fill: parent; onClicked: root.shellUpdatesOpen = false }

                PanelSurface {
                    width: Math.min(parent.width - root.cardGap * 4, Theme.cellW * 70)
                    height: Math.min(parent.height - root.cardGap * 4, Theme.cellH * 31)
                    anchors.centerIn: parent
                    MouseArea { anchors.fill: parent; onClicked: {} }

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.cellW * 2
                        spacing: Theme.cellH * 0.8

                        Item {
                            width: parent.width; height: Theme.cellH * 2
                            Line { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "DESKTOP UPDATES"; color: Theme.fgBright; font.pixelSize: Theme.fontHeading }
                            ActionButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Close"; compact: true; onTriggered: root.shellUpdatesOpen = false }
                        }
                        Rule { rowWidth: parent.width; label: ShellUpdates.channel.toUpperCase() + " CHANNEL" }
                        Line { width: parent.width; text: "Installed"; color: Theme.fgDim }
                        Line { width: parent.width; text: ShellUpdates.current || "unknown"; color: Theme.fgBright; font.pixelSize: Theme.fontHeading }
                        Line { width: parent.width; text: "Latest published release"; color: Theme.fgDim }
                        Line { width: parent.width; text: ShellUpdates.checking ? "checking …" : (ShellUpdates.latest || "not checked yet"); color: ShellUpdates.updateAvailable ? Theme.yellow : Theme.fgBright; font.pixelSize: Theme.fontHeading }
                        Line {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: ShellUpdates.error !== "" ? ShellUpdates.error
                                : (ShellUpdates.updateAvailable ? "A new nbshell release is ready."
                                : (ShellUpdates.ready ? "nbshell is up to date." : "Check for a published release."))
                            color: ShellUpdates.error !== "" ? Theme.yellow : Theme.fg
                        }
                        Item { width: 1; height: Theme.cellH * 0.2 }
                        Row {
                            spacing: Theme.cellW * 2
                            ActionButton { text: ShellUpdates.checking ? "Checking …" : "Check again"; busy: ShellUpdates.checking; compact: true; onTriggered: ShellUpdates.refresh() }
                            ActionButton { visible: ShellUpdates.releaseUrl !== ""; text: "Release notes"; compact: true; onTriggered: ShellUpdates.openNotes() }
                            ActionButton {
                                visible: ShellUpdates.updateAvailable && ShellUpdates.installable
                                text: "Install in terminal"
                                tone: "primary"
                                accentColor: Theme.green
                                compact: true
                                onTriggered: root.openSurface(() => ShellUpdates.install())
                            }
                        }
                        Rule { rowWidth: parent.width; label: "UMBRIEL STACK" }
                        Line {
                            width: parent.width
                            text: "Umbriel  " + root.compositorRevision("umbriel", "current")
                                + (root.compositorRevision("umbriel", "available") === true ? " → " + root.compositorRevision("umbriel", "latest") : "")
                            color: root.compositorRevision("umbriel", "available") === true ? Theme.yellow : Theme.fgBright
                            font.pixelSize: Theme.fontBody
                        }
                        Line {
                            width: parent.width
                            text: "Portal    " + root.compositorRevision("xdg-desktop-portal-umbriel", "current")
                                + (root.compositorRevision("xdg-desktop-portal-umbriel", "available") === true ? " → " + root.compositorRevision("xdg-desktop-portal-umbriel", "latest") : "")
                            color: root.compositorRevision("xdg-desktop-portal-umbriel", "available") === true ? Theme.yellow : Theme.fgBright
                            font.pixelSize: Theme.fontBody
                        }
                        Line {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: ShellUpdates.compositorChecking ? "checking official Git repositories …"
                                : (ShellUpdates.compositorError !== "" ? ShellUpdates.compositorError
                                : (ShellUpdates.compositorUpdateAvailable ? "A compositor stack update is ready. It takes effect after the next login."
                                : (ShellUpdates.compositorReady ? "Umbriel and its portal are up to date." : "Check the installed compositor stack.")))
                            color: ShellUpdates.compositorError !== "" ? Theme.yellow : Theme.fg
                        }
                        Row {
                            spacing: Theme.cellW * 2
                            ActionButton { text: ShellUpdates.compositorChecking ? "Checking …" : "Check stack"; busy: ShellUpdates.compositorChecking; compact: true; onTriggered: ShellUpdates.refresh() }
                            ActionButton {
                                visible: ShellUpdates.compositorUpdateAvailable && ShellUpdates.compositorInstallable
                                text: "Update stack"
                                tone: "primary"
                                accentColor: Theme.green
                                compact: true
                                onTriggered: root.openSurface(() => ShellUpdates.installCompositor())
                            }
                            ActionButton {
                                visible: ShellUpdates.updateAvailable && ShellUpdates.installable && ShellUpdates.compositorUpdateAvailable && ShellUpdates.compositorInstallable
                                text: "Update all"
                                tone: "primary"
                                accentColor: Theme.accent
                                compact: true
                                onTriggered: root.openSurface(() => ShellUpdates.installAll())
                            }
                        }
                        Line { width: parent.width; text: "nbshell releases are checksum verified  ·  Umbriel builds only clean official checkouts"; color: Theme.muted; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }
        }
    }
}
