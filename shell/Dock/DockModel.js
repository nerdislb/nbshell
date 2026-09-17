// Pure app identity/grouping rules shared by the production dock and tests.
function normalized(value) {
    return String(value || "").replace(/\.desktop$/i, "").toLowerCase();
}

function entryFor(appId, entries) {
    const key = normalized(appId);
    if (!key) return null;
    const exact = entries.filter(e => normalized(e.id) === key);
    if (exact.length === 1) return exact[0];
    const classes = entries.filter(e => normalized(e.startupClass) === key);
    if (classes.length === 1) return classes[0];
    // Common reverse-DNS IDs (e.g. com.mitchellh.ghostty). Do not guess when
    // two desktop entries share a basename; webapps must remain distinct.
    const suffix = entries.filter(e => normalized(e.id).split(".").pop() === key);
    return suffix.length === 1 ? suffix[0] : null;
}

function groups(entries, windows, pins) {
    const result = [];
    const byKey = Object.create(null);
    function append(key, entry, pinned, appId) {
        const group = {key: key, entry: entry, pinned: pinned, appId: appId,
            name: entry ? entry.name : (appId || "Application"), windows: []};
        result.push(group);
        byKey[key] = group;
        return group;
    }
    for (const id of Array.isArray(pins) ? pins : []) {
        const entry = entries.find(e => e.id === id);
        if (entry && !byKey[entry.id]) append(entry.id, entry, true, "");
    }
    for (const window of windows) {
        const entry = entryFor(window.app_id, entries);
        const key = entry ? entry.id : (window.app_id ? "app:" + window.app_id : "window:" + window.id);
        const group = byKey[key] || append(key, entry, false, window.app_id);
        group.windows.push(window);
    }
    return result;
}
