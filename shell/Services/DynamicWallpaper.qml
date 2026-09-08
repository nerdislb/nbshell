pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import "../Wallpaper/WallpaperPolicy.js" as Policy

Singleton {
    id: root
    readonly property var settings: Policy.normalize(Config.value("dynamicWallpaper", {}))
    property date now: new Date()
    readonly property string fallback: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")
    readonly property var selection: Policy.sources(settings, now.getHours() * 60 + now.getMinutes(), fallback)
    readonly property string stillPath: selection.image
    readonly property string videoPath: selection.video
    property bool nativeLocked: false
    property string error: ""
    readonly property bool resting: nativeLocked || ["locked", "Screen off", "screen saver"].indexOf(Idle.state) >= 0
    readonly property bool videoEligible: settings.videoEnabled && videoPath !== "" && !UPower.onBattery
        && !Theme.reducedMotion && !resting && Compositor.available && Config.wallpaperEnabled

    function clearDesktop(output) {
        return Policy.desktopClear(output, Compositor.workspaces, Compositor.windows);
    }
    function reason(output) {
        if (!Config.wallpaperEnabled) return "Wallpaper disabled";
        return error || Policy.playbackReason(settings.videoEnabled, videoPath, UPower.onBattery,
            Theme.reducedMotion, resting, Compositor.available, clearDesktop(output));
    }
    function url(path) { return Policy.localUrl(path); }
    function update(key, value, index) {
        var next = JSON.parse(JSON.stringify(settings));
        if (index !== undefined && index >= 0) {
            if (key === "time" && (Policy.minutes(value) < 0 || next.phases.some((p, i) => i !== index && p.time === value))) {
                error = "Use a unique time in HH:MM format.";
                return false;
            }
            next.phases[index][key] = value;
        } else next[key] = value;
        if (!Config.set("dynamicWallpaper", next)) {
            error = "Could not save wallpaper settings.";
            return false;
        }
        error = "";
        now = new Date();
        return true;
    }
    Connections {
        target: Config
        function onWriteFailed(message) { root.error = message; }
    }
    onVideoPathChanged: error = ""
    onSettingsChanged: now = new Date()

    Timer {
        interval: 30000
        running: root.settings.daytimeEnabled
        repeat: true
        onTriggered: root.now = new Date()
    }
    // The existing native lock unit creates this marker only once secure and
    // removes it in ExecStopPost. Observing it does not implement a new lock.
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/nbshell-lock-ready"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.nativeLocked = true
        onLoadFailed: root.nativeLocked = false
    }
}
