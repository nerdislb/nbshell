import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Die Uhr als Eingang in den Alltag: Termine, Wetter, Media und die Dinge,
// die nicht dauerhaft Platz in der Bar brauchen. Angeregt vom Asked Dashboard
// fuer Omarchy, aber vollstaendig auf nbshells vorhandenen Diensten aufgebaut.
PanelWindow {
    id: root

    property int page: 0
    property var weather: ({})
    property bool weatherLoading: false
    property bool updatesOpen: false
    readonly property date now: clock.date
    readonly property real cardGap: Theme.cellW * 1.5
    readonly property real panelWidth: Math.min(width - Theme.cellW * 8, Theme.cellW * 104)
    readonly property real panelHeight: Math.min(height - Theme.cellH * 6, Theme.cellH * 43)
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
        Calendar.ensure(new Date());
        AiUsage.refresh();
        refreshWeather();
        keys.forceActiveFocus();
    }
    onPageChanged: Runtime.dashboardPage = page

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
    component Card: Rectangle {
        property string title: ""
        property string badge: ""
        default property alias content: body.data
        color: Theme.alpha(Theme.bgLight, 0.72)
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.alpha(Theme.accent, 0.55)

        Line {
            anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.2
            anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.65
            text: parent.title.toUpperCase(); color: Theme.fgDim
        }
        Line {
            anchors.right: parent.right; anchors.rightMargin: Theme.cellW * 1.2
            anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.65
            text: parent.badge; color: Theme.readable(Theme.accent, Theme.bg)
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
        width: Theme.cellW * 21
        height: Theme.cellH * 3.2
        radius: Theme.radius
        color: actionHover.hovered ? Theme.hover : Theme.alpha(Theme.bgLight, 0.72)
        border.width: Theme.borderWidth
        border.color: actionHover.hovered ? action.tone : Theme.alpha(action.tone, 0.55)

        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.55; text: action.glyph + (action.glyph !== "" ? "  " : "") + action.label; color: action.tone }
        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.right: rightHint.left; anchors.rightMargin: Theme.cellW * 0.5; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.cellH * 0.45; text: action.detail; color: Theme.fgDim; elide: Text.ElideRight }
        Line { id: rightHint; visible: action.rightRun !== null; anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.cellH * 0.45; text: "R"; color: Theme.muted }
        HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
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
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            width: root.panelWidth
            height: root.panelHeight
            anchors.centerIn: parent
            color: Theme.bg
            radius: Theme.radius
            border.width: Math.max(Theme.borderWidth, 2)
            border.color: Theme.accent
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
                        Line { text: root.now.toLocaleString(Qt.locale(Config.value("locale", "en_US")), "dddd, dd. MMMM"); color: Theme.fgBright; font.pixelSize: Theme.fontSize + 5 }
                        Line { text: "WEEK " + Calendar.isoWeek(root.now) + "  ·  " + Calendar.moonName(root.now); color: Theme.fgDim }
                    }
                    Line { anchors.right: parent.right; anchors.top: parent.top; text: root.now.toLocaleTimeString(Qt.locale(), "HH:mm"); color: Theme.readable(Theme.accent, Theme.bg); font.pixelSize: Theme.fontSize + 12 }
                }

                Row {
                    width: parent.width
                    spacing: Theme.cellW
                    Repeater {
                        model: ["TODAY", "MEDIA", "TOOLS"]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: (parent.width - Theme.cellW * 2) / 3
                            height: Theme.cellH * 1.7
                            color: root.page === index ? Theme.selection : (tabHover.hovered ? Theme.hover : "transparent")
                            border.width: Theme.borderWidth
                            border.color: root.page === index ? Theme.accent : Theme.muted
                            Line { anchors.centerIn: parent; text: parent.modelData; color: root.page === parent.index ? Theme.on(Theme.selection) : Theme.fgDim }
                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.page = parent.index }
                        }
                    }
                }

                // ── TODAY ───────────────────────────────────────────────
                Item {
                    visible: root.page === 0
                    width: parent.width
                    height: parent.height - Theme.cellH * 7

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
                            badge: Calendar.loading ? "…" : String(root.nextEvents.length)
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
                    height: parent.height - Theme.cellH * 7

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - root.cardGap * 2, Theme.cellW * 76)
                        spacing: root.cardGap

                        Item {
                            width: parent.width; height: Theme.cellH * 17
                            Rectangle {
                                width: parent.height; height: parent.height; anchors.centerIn: parent
                                color: Theme.bgLight; border.width: Theme.borderWidth; border.color: Theme.accent; radius: Theme.radius
                                Image { anchors.fill: parent; anchors.margins: Theme.borderWidth; source: MediaService.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                Line { anchors.centerIn: parent; visible: (MediaService.player?.trackArtUrl ?? "") === ""; text: Icons.play; color: Theme.muted; font.pixelSize: Theme.fontSize + 40 }
                            }
                        }

                        Rectangle {
                            width: parent.width; height: Theme.cellH * 11.5
                            color: Theme.alpha(Theme.bgLight, 0.72); radius: Theme.radius
                            border.width: Theme.borderWidth; border.color: Theme.alpha(Theme.accent, 0.55)
                            Column {
                                anchors.fill: parent; anchors.margins: Theme.cellW * 1.5
                                spacing: Theme.cellH * 0.35
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.active ? (MediaService.title || "Unknown title") : "No active player"; color: Theme.fgBright; font.pixelSize: Theme.fontSize + 4; elide: Text.ElideRight }
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.artist; color: Theme.fgDim; elide: Text.ElideRight }
                                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: MediaService.zeit(MediaService.position) + "  /  " + MediaService.zeit(MediaService.length); color: Theme.fgDim }
                                LevelBar { width: parent.width; cells: 56; value: MediaService.length > 0 ? 100 * MediaService.position / MediaService.length : 0; fillColor: Theme.accent }
                                Row {
                                    width: parent.width
                                    spacing: Theme.cellW * 2
                                    Action { width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: "Previous"; glyph: Icons.cp(0xF04AE); detail: "previous track"; run: () => MediaService.previous() }
                                    Action { width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: MediaService.playing ? "Pause" : "Play"; glyph: MediaService.playing ? Icons.pause : Icons.play; detail: MediaService.playing ? "pause playback" : "resume playback"; run: () => MediaService.playPause() }
                                    Action { width: (parent.width - Theme.cellW * 4) / 3; height: Theme.cellH * 2.8; label: "Next"; glyph: Icons.cp(0xF04AD); detail: "next track"; run: () => MediaService.next() }
                                }
                                Line { visible: MediaService.volumeSupported; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "PLAYER VOLUME  " + Math.round(MediaService.volume * 100) + " %"; color: Theme.fgDim }
                                LevelBar { visible: MediaService.volumeSupported; width: parent.width; cells: 56; value: MediaService.volume * 100; fillColor: Theme.cyan; interactive: true; onMoved: value => MediaService.setVolume(value / 100) }
                            }
                        }
                    }
                }

                // ── TOOLS ───────────────────────────────────────────
                Item {
                    visible: root.page === 2
                    width: parent.width
                    height: parent.height - Theme.cellH * 7

                    Flow {
                        anchors.centerIn: parent
                        width: Theme.cellW * 84 + root.cardGap * 3
                        height: childrenRect.height
                        spacing: root.cardGap

                        Action { label: "Tasks"; detail: Todo.count + " open"; glyph: Icons.todo; run: () => root.openSurface(() => Runtime.todoOpen = true) }
                        Action { label: "Habits"; detail: Habits.doneCount + "/" + Habits.count + " today"; glyph: Icons.habit; run: () => root.openSurface(() => Runtime.habitsOpen = true) }
                        Action {
                            label: "Updates"
                            detail: Updates.checking ? "checking …" : Updates.count + " available"
                            glyph: Icons.download
                            tone: Updates.count > 0 ? Theme.yellow : Theme.green
                            run: () => {
                                root.updatesOpen = true;
                                if (!Updates.ready)
                                    Updates.refresh();
                            }
                            rightRun: () => root.openSurface(() => Updates.update())
                        }
                        Action { label: "Capture"; detail: CaptureService.recording ? "running" : "Screenshot, OCR, QR"; glyph: CaptureService.recording ? Icons.record : Icons.camera; tone: CaptureService.recording ? Theme.red : Theme.accent; run: () => root.openSurface(() => Runtime.captureOpen = true); rightRun: () => CaptureService.toggleRecording() }
                        Action { label: "Theme"; detail: Config.theme; glyph: Icons.palette; run: () => root.openSurface(() => Runtime.themePickerOpen = true); rightRun: () => ThemeIndex.step(1) }
                        Action { label: "Keep awake"; detail: Idle.caffeine ? "active" : "idle automation active"; glyph: Icons.coffee; tone: Idle.caffeine ? Theme.yellow : Theme.fgDim; run: () => Idle.toggleCaffeine() }
                        Action { label: "AI usage"; detail: AiUsage.list.length ? AiUsage.list.map(e => e.id + " " + e.percent + "%").join(" · ") : "no data"; glyph: Icons.cp(0xF1218); run: () => AiUsage.refresh() }
                        Action { label: "System-Hub"; detail: "Services, sync, ports"; glyph: Icons.matrix; run: () => root.openSurface(() => Runtime.hubOpen = true) }
                        Action { label: "Modules"; detail: "Arrange the bar"; glyph: Icons.cp(0xF12E); run: () => root.openSurface(() => Runtime.modulesOpen = true) }
                        Action { label: "Clipboard"; detail: Clipboard.entries.length + " entries"; glyph: Icons.clipboard; run: () => root.openSurface(() => Runtime.clipOpen = true) }
                        Action { label: "Audio"; detail: "Mixer and equalizer"; glyph: Icons.volumeHigh; run: () => root.openSurface(() => Runtime.audioToolsOpen = true) }
                        Action { label: "Settings"; detail: "Appearance and behavior"; glyph: Icons.cp(0xF0493); run: () => root.openSurface(() => Runtime.settingsOpen = true) }
                    }
                }

                Line { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Esc closes  ·  R marks a right-click action"; color: Theme.muted }
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

                Rectangle {
                    width: Math.min(parent.width - root.cardGap * 4, Theme.cellW * 78)
                    height: Math.min(parent.height - root.cardGap * 4, Theme.cellH * 34)
                    anchors.centerIn: parent
                    color: Theme.bg
                    radius: Theme.radius
                    border.width: Math.max(Theme.borderWidth, 2)
                    border.color: Theme.accent
                    MouseArea { anchors.fill: parent; onClicked: {} }

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.cellW * 2
                        spacing: Theme.cellH * 0.55

                        Item {
                            width: parent.width; height: Theme.cellH * 2
                            Line {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: "UPDATES  (" + Updates.count + ")"; color: Theme.fgBright; font.pixelSize: Theme.fontSize + 4
                            }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.cellW * 2
                                ActionButton {
                                    text: Updates.checking ? "Prueft …" : "Check again"
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

                        Rule { rowWidth: parent.width; label: "PAKETE" }

                        Item {
                            width: parent.width
                            height: parent.height - Theme.cellH * 6.6

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
        }
    }
}
