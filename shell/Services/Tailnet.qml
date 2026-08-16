pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property string state: ""
    property string host: ""
    property string ip: ""
    property var peers: []
    readonly property int onlinePeers: peers.filter(p => p.online).length

    function refresh() {
        if (!status.running) status.running = true;
    }

    function copy(value) {
        if (value !== "") Quickshell.execDetached(["wl-copy", "--", value]);
    }

    Process {
        id: status
        command: ["tailscale", "status", "--json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.available = true;
                    root.state = data.BackendState ?? "";
                    root.host = data.Self ? (data.Self.HostName ?? "") : "";
                    root.ip = data.Self && data.Self.TailscaleIPs ? (data.Self.TailscaleIPs[0] ?? "") : "";
                    const out = [];
                    const source = data.Peer ?? {};
                    for (const key in source) {
                        const peer = source[key];
                        out.push({
                            "host": peer.HostName || peer.DNSName || key,
                            "dns": String(peer.DNSName || "").replace(/\.$/, ""),
                            "ip": peer.TailscaleIPs ? (peer.TailscaleIPs[0] ?? "") : "",
                            "online": peer.Online === true
                        });
                    }
                    root.peers = out.sort((a, b) => Number(b.online) - Number(a.online) || a.host.localeCompare(b.host));
                } catch (e) {
                    root.available = false;
                    root.peers = [];
                }
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
