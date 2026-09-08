.pragma library

function defaults() {
    return { daytimeEnabled: false, videoEnabled: false, image: "", video: "",
        phases: [
            { name: "Morning", time: "06:00", image: "", video: "" },
            { name: "Day", time: "10:00", image: "", video: "" },
            { name: "Evening", time: "18:00", image: "", video: "" },
            { name: "Night", time: "22:00", image: "", video: "" }
        ] };
}

function minutes(time) {
    if (typeof time !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) return -1;
    return Number(time.slice(0, 2)) * 60 + Number(time.slice(3));
}

function normalize(raw) {
    var result = defaults();
    if (!raw || typeof raw !== "object") return result;
    result.daytimeEnabled = raw.daytimeEnabled === true;
    result.videoEnabled = raw.videoEnabled === true;
    result.image = typeof raw.image === "string" ? raw.image : "";
    result.video = typeof raw.video === "string" ? raw.video : "";
    var seen = {};
    if (Array.isArray(raw.phases) && raw.phases.length === 4) {
        var valid = raw.phases.every(function(p) {
            if (!p || minutes(p.time) < 0 || seen[p.time]) return false;
            seen[p.time] = true;
            return true;
        });
        if (valid) result.phases = raw.phases.map(function(p, i) {
            return { name: result.phases[i].name, time: p.time,
                image: typeof p.image === "string" ? p.image : "",
                video: typeof p.video === "string" ? p.video : "" };
        });
    }
    return result;
}

function phaseAt(phases, minute) {
    var ordered = phases.slice().sort(function(a, b) { return minutes(a.time) - minutes(b.time); });
    var result = ordered[ordered.length - 1];
    ordered.forEach(function(p) { if (minutes(p.time) <= minute) result = p; });
    return result;
}

function sources(settings, minute, fallback) {
    var phase = phaseAt(settings.phases, minute);
    return { image: (settings.daytimeEnabled ? phase.image : settings.image) || fallback,
        video: settings.daytimeEnabled ? phase.video : settings.video,
        phase: phase.name };
}

function desktopClear(output, workspaces, windows) {
    var active = workspaces.filter(function(w) { return w.output === output && w.is_active; });
    if (!output || active.length !== 1) return false;
    // Unknown window placement is treated conservatively during IPC resync.
    return !windows.some(function(w) { return w.workspace === undefined || w.workspace === null
        || String(w.workspace) === String(active[0].id); });
}

function playbackReason(enabled, video, onBattery, reducedMotion, asleep, available, clear) {
    if (!enabled) return "Video disabled";
    if (!video) return "No video assigned";
    if (onBattery) return "Still image · battery power";
    if (reducedMotion) return "Still image · Reduced Motion";
    if (asleep) return "Still image · screen resting";
    if (!available) return "Still image · waiting for compositor";
    if (!clear) return "Still image · window on this workspace";
    return "Video ready · mains power / desktop";
}

function localUrl(path) {
    // Config stores decoded absolute paths. Encode URL metacharacters in names.
    return path && path[0] === "/" ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
}
