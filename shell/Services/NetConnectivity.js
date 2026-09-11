.pragma library

function state(connected, checksEnabled, value, states) {
    if (!connected) return "offline";
    // A cached successful or portal result is not current evidence when
    // NetworkManager probing is unavailable or disabled.
    if (!checksEnabled) return "unknown";
    if (value === states.Portal) return "portal";
    if (value === states.Limited) return "limited";
    if (value === states.Full) return "full";
    if (value === states.None) return "none";
    return "unknown";
}

function label(state, checksEnabled) {
    if (state === "offline") return "Not connected";
    if (state === "portal") return "Network sign-in required";
    if (state === "limited") return "Limited Internet access";
    if (state === "none") return "No Internet access";
    if (state === "full") return "Internet access available";
    return checksEnabled ? "Internet status unknown" : "Internet check unavailable or disabled";
}
