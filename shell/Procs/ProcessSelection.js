.pragma library

function indexForProcess(entries, pid, started) {
    if (!Array.isArray(entries) || pid < 1 || started === "")
        return -1;

    for (let index = 0; index < entries.length; index++) {
        const entry = entries[index];
        if (Number(entry.pid) === Number(pid) && String(entry.started) === String(started))
            return index;
    }
    return -1;
}

function entryAt(entries, index) {
    if (!Array.isArray(entries) || index < 0 || index >= entries.length)
        return null;
    return entries[index];
}

function movedEntry(entries, selectedPid, selectedStarted, delta) {
    if (!Array.isArray(entries) || entries.length === 0)
        return null;

    const current = indexForProcess(entries, selectedPid, selectedStarted);
    const next = current < 0
        ? 0
        : Math.max(0, Math.min(entries.length - 1, current + delta));
    return entryAt(entries, next);
}

function parsePsLine(line) {
    const parts = String(line).trim().split(/\s+/);
    if (parts.length < 10)
        return null;

    return {
        "pid": parseInt(parts[0], 10),
        "cpu": parseFloat(parts[1]),
        "mem": parseFloat(parts[2]),
        "rss": parseInt(parts[3], 10),
        "started": parts.slice(4, 9).join(" "),
        "name": parts.slice(9).join(" ")
    };
}
