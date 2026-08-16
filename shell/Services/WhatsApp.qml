pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Schmale NDJSON-Anbindung an die lokal laufende, benutzereigene Bridge.
Singleton {
    id: root

    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/nbshell-whatsapp.sock"
    readonly property string helper: Qt.resolvedUrl("../scripts/whatsapp.sh").toString().replace("file://", "")

    property bool online: false
    property string connection: "unknown"
    property bool needsLogin: false
    property bool linked: false
    property bool hasQr: false
    property string qrPng: ""
    property int unread: 0
    property var chats: []
    property string currentJid: ""
    property var currentChat: null
    property var messages: []
    property string error: ""
    property int retry: 0

    readonly property bool ready: online && linked && connection === "open"

    function send(frame) {
        if (!socket.connected)
            return false;
        socket.write(JSON.stringify(frame) + "\n");
        socket.flush();
        return true;
    }
    function refresh() { send({ "t": "hello" }); }
    function beginLogin() { send({ "t": "login" }); }
    function selectChat(jid) {
        currentJid = String(jid || "");
        messages = [];
        if (currentJid !== "") {
            send({ "t": "messages", "jid": currentJid, "limit": 40 });
            send({ "t": "read", "jid": currentJid });
        }
    }
    function sendText(text) {
        const clean = String(text || "").trim();
        return currentJid !== "" && clean !== "" && send({ "t": "send", "jid": currentJid, "text": clean });
    }
    function openWeb() { opener.running = true; }
    function setup() { setupProc.running = true; }

    function frame(f) {
        switch (f.t) {
        case "state":
            online = true;
            connection = f.connection || "unknown";
            needsLogin = f.needsLogin === true;
            linked = f.linked === true;
            hasQr = f.hasQr === true;
            qrPng = f.qrPng || "";
            unread = f.unread || 0;
            if (f.chats !== undefined) chats = f.chats || [];
            error = f.lastError || "";
            break;
        case "chats":
            chats = f.chats || [];
            unread = f.unread || 0;
            break;
        case "messages":
            if (String(f.jid || "") === currentJid) {
                currentChat = f.chat || null;
                messages = f.messages || [];
            }
            break;
        case "message":
            if (f.unread !== undefined) unread = f.unread || 0;
            if (String(f.jid || "") === currentJid && f.message)
                messages = messages.concat([f.message]);
            break;
        case "error": error = f.message || "Unbekannter Fehler"; break;
        }
    }

    Socket {
        id: socket
        path: root.socketPath
        connected: true
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                try { root.frame(JSON.parse(line)); }
                catch (e) { console.warn("nbshell/whatsapp: ungueltige Bridge-Antwort", e); }
            }
        }
        onConnectionStateChanged: {
            root.online = connected;
            if (connected) {
                root.retry = 0;
                root.refresh();
            } else retryTimer.restart();
        }
        onError: error => {
            root.online = false;
            retryTimer.restart();
        }
    }

    Timer {
        id: retryTimer
        interval: Math.min(8000, 1200 + root.retry * 800)
        onTriggered: {
            root.retry += 1;
            if (root.retry === 2) starter.running = true;
            socket.connected = false;
            socket.connected = true;
        }
    }
    Timer { interval: 20000; repeat: true; running: true; onTriggered: root.send({ "t": "ping" }) }
    Process { id: starter; command: ["systemctl", "--user", "start", "nbshell-whatsapp.service"] }
    Process { id: setupProc; command: [root.helper, "setup"]; onExited: starter.running = true }
    Process { id: opener; command: [root.helper, "open"] }
}
