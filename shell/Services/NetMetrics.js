function defaultInterface(routeText) {
    const lines = String(routeText || "").split("\n");
    for (var i = 1; i < lines.length; i++) {
        const fields = lines[i].trim().split(/\s+/);
        if (fields.length >= 4 && fields[1] === "00000000"
                && (parseInt(fields[3], 16) & 0x1) !== 0)
            return fields[0];
    }
    return "";
}

function interfaceCounters(deviceText, iface) {
    if (!iface)
        return null;
    const lines = String(deviceText || "").split("\n");
    for (var i = 2; i < lines.length; i++) {
        const halves = lines[i].split(":");
        if (halves.length !== 2 || halves[0].trim() !== iface)
            continue;
        const fields = halves[1].trim().split(/\s+/);
        if (fields.length < 9)
            return null;
        const rx = Number(fields[0]);
        const tx = Number(fields[8]);
        return isFinite(rx) && isFinite(tx) ? { "rx": rx, "tx": tx } : null;
    }
    return null;
}
