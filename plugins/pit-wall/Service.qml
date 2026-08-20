import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

QtObject {
    id: root

    readonly property int refreshInterval: 900000
    readonly property int liveRefreshInterval: 20000
    readonly property int liveRowLimit: 10
    readonly property int standingsLimit: 5

    property var schedule: ({ season: "", races: [] })
    property bool scheduleLoaded: false
    property var driverRows: []
    property var constructorRows: []
    property var liveDrivers: ({})
    property var livePositions: ({})
    property var liveGaps: ({})
    property string liveFetchedFullAt: ""
    property string trackStatus: "green"
    property double liveSessionEndMs: 0
    property double nowMs: Date.now()
    property bool loading: false
    property string errorText: ""
    property date lastUpdated: new Date(0)

    readonly property var raceState: Model.currentOrNext(schedule.races, nowMs)
    readonly property bool scheduleLive: raceState.status === "live"
    readonly property bool openf1Live: liveSessionEndMs > 0 && nowMs < liveSessionEndMs
    readonly property bool isLive: scheduleLive || openf1Live
    readonly property var liveRows: isLive
        ? Model.boardRows(livePositions, liveGaps, liveDrivers, liveRowLimit) : []
    readonly property string trackTag: isLive ? Model.statusTag(trackStatus) : ""
    readonly property string label: {
        if (!scheduleLoaded)
            return loading ? "…" : "—";
        if (raceState.status === "off")
            return "OFF";
        return Model.pillText(raceState, Model.leaderAcronym(liveRows), trackTag);
    }
    readonly property string tooltip: {
        if (!scheduleLoaded)
            return errorText !== "" ? errorText : "Pit Wall — loading F1 schedule…";
        if (raceState.status === "off")
            return "Pit Wall — season complete";
        const race = raceState.race;
        return race.name + " — " + raceState.session.label
            + (isLive ? " · LIVE" : " · " + Qt.formatDateTime(new Date(raceState.session.startMs), "ddd d MMM · HH:mm"));
    }

    function curl(url) {
        return ["curl", "-fsS", "--max-time", "15", "--max-filesize", "8000000", url];
    }

    function refresh() {
        if (loading)
            return;
        loading = true;
        errorText = "";
        pendingRefreshes = 3;
        scheduleProc.running = true;
        driversStandingsProc.running = true;
        constructorStandingsProc.running = true;
    }

    property int pendingRefreshes: 0

    function refreshFinished(ok) {
        if (!ok && errorText === "")
            errorText = "Pit Wall — data refresh failed";
        pendingRefreshes = Math.max(0, pendingRefreshes - 1);
        if (pendingRefreshes === 0) {
            loading = false;
            lastUpdated = new Date();
        }
    }

    function liveTick() {
        nowMs = Date.now();
        if (!isLive)
            return;
        if (!liveDriversProc.running)
            liveDriversProc.running = true;
        if (!liveSessionProc.running)
            liveSessionProc.running = true;
        const since = liveFetchedFullAt === ""
            ? "&date>=" + new Date(nowMs - 3600000).toISOString()
            : "&date>=" + new Date(nowMs - 180000).toISOString();
        if (liveFetchedFullAt === "")
            liveFetchedFullAt = new Date(nowMs).toISOString();
        if (!livePositionProc.running) {
            livePositionProc.command = curl("https://api.openf1.org/v1/position?session_key=latest" + since);
            livePositionProc.running = true;
        }
        if (!liveGapsProc.running) {
            liveGapsProc.command = curl("https://api.openf1.org/v1/intervals?session_key=latest" + since);
            liveGapsProc.running = true;
        }
        if (!raceControlProc.running) {
            raceControlProc.command = curl("https://api.openf1.org/v1/race_control?session_key=latest");
            raceControlProc.running = true;
        }
    }

    onIsLiveChanged: {
        if (!isLive) {
            livePositions = ({});
            liveGaps = ({});
            liveDrivers = ({});
            liveFetchedFullAt = "";
            trackStatus = "green";
            liveSessionEndMs = 0;
        }
    }

    Component.onCompleted: refresh()

    property var scheduleProc: Process {
        command: root.curl("https://api.jolpi.ca/ergast/f1/current.json?limit=30")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const parsed = Model.parseSchedule(text);
                if (parsed.races.length) {
                    root.schedule = parsed;
                    root.scheduleLoaded = true;
                    root.refreshFinished(true);
                } else {
                    root.refreshFinished(false);
                }
            }
        }
    }

    property var driversStandingsProc: Process {
        command: root.curl("https://api.jolpi.ca/ergast/f1/current/driverstandings.json")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const rows = Model.parseStandings(text, "DriverStandings");
                if (rows.length)
                    root.driverRows = rows;
                root.refreshFinished(rows.length > 0);
            }
        }
    }

    property var constructorStandingsProc: Process {
        command: root.curl("https://api.jolpi.ca/ergast/f1/current/constructorstandings.json")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const rows = Model.parseStandings(text, "ConstructorStandings");
                if (rows.length)
                    root.constructorRows = rows;
                root.refreshFinished(rows.length > 0);
            }
        }
    }

    property var liveDriversProc: Process {
        command: root.curl("https://api.openf1.org/v1/drivers?session_key=latest")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const rows = Model.parseDrivers(text);
                if (Object.keys(rows).length)
                    root.liveDrivers = rows;
            }
        }
    }

    property var liveSessionProc: Process {
        command: root.curl("https://api.openf1.org/v1/sessions?session_key=latest")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const session = Model.pickLiveSession(text, root.nowMs);
                root.liveSessionEndMs = session ? Date.parse(session.date_end) : 0;
            }
        }
    }

    property var livePositionProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.livePositions = Model.mergeEvents(root.livePositions, text)
        }
    }

    property var liveGapsProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.liveGaps = Model.mergeEvents(root.liveGaps, text)
        }
    }

    property var raceControlProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.trackStatus = Model.foldTrackStatus(root.trackStatus, text)
        }
    }

    property var refreshTimer: Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    property var liveTimer: Timer {
        interval: root.liveRefreshInterval
        running: root.isLive
        repeat: true
        triggeredOnStart: true
        onTriggered: root.liveTick()
    }

    property var clockTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }
}
