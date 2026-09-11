import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var accounts: []
    property var calendars: []
    property var events: []
    property string error: ""
    property bool stale: true
    property bool busy: process.running
    property string loadedAt: ""
    property string authorizationUrl: ""
    property var request: ({})
    property bool received: false
    property bool fixtureMode: false
    property string rangeStart: ""
    property string rangeEnd: ""
    property string operation: ""
    signal changed(string operation)

    function run(value) {
        if (busy || fixtureMode) return;
        request = value;
        operation = value.op;
        error = "";
        received = false;
        authorizationUrl = "";
        process.running = true;
    }
    function refresh(start, end) {
        rangeStart = start;
        rangeEnd = end;
        run({op: "refresh", start: start, end: end});
    }
    function accept(data) {
        if (data.authorizationUrl) {
            authorizationUrl = data.authorizationUrl;
            // Backend constructs this fixed-origin URL, never a provider-supplied redirect.
            if (authorizationUrl.indexOf("https://accounts.google.com/o/oauth2/v2/auth?") === 0)
                Qt.openUrlExternally(authorizationUrl);
            return;
        }
        received = true;
        authorizationUrl = "";
        if (!data.ok) {
            error = data.error || "Calendar operation failed.";
            stale = true;
            return;
        }
        if (data.changed) {
            changed(operation);
            return;
        }
        accounts = data.accounts || [];
        // Keep failed accounts' last in-memory snapshot, visibly stale and never writable.
        const good = (data.calendars || []).map(c => c.account);
        const failed = data.stale ? accounts.filter(a => good.indexOf(a.id) < 0).map(a => a.id) : [];
        calendars = (data.calendars || []).concat(calendars.filter(c => failed.indexOf(c.account) >= 0));
        events = (data.events || []).concat(events.filter(e => failed.indexOf(e.account) >= 0));
        stale = !!data.stale;
        error = (data.errors || []).join("\n");
        loadedAt = data.loadedAt || "";
    }
    function cancel() {
        if (busy) {
            process.running = false;
            stale = true;
            error = "Operation interrupted; its outcome may be unknown. Refresh before retrying.";
        }
        request = ({});
        authorizationUrl = "";
    }
    Process {
        id: process
        command: ["python3", Qt.resolvedUrl("backend/calendar_backend.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify(root.request) + "\n");
            root.request = ({});
            stdinEnabled = false;
        }
        onRunningChanged: if (!running) stdinEnabled = true
        stdout: SplitParser {
            onRead: data => {
                try { root.accept(JSON.parse(data)); }
                catch (_) { root.error = "Invalid backend reply."; root.stale = true; }
            }
        }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            if (!root.received && !root.error) {
                root.error = "Calendar backend stopped. Check Python dependencies and refresh.";
                root.stale = true;
            }
        }
    }
    Component.onDestruction: cancel()
}
