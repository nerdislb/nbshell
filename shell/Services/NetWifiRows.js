// Keep display data independent of ephemeral backend QObject wrappers.
function key(network) {
    return JSON.stringify([String(network.name || ""), network.security]);
}

function preferred(a, b) {
    if (!!a.connected !== !!b.connected) return a.connected ? -1 : 1;
    return (b.signalStrength || 0) - (a.signalStrength || 0);
}

function rows(networks) {
    const selected = Object.create(null);
    for (const network of networks) {
        if (!network || !network.name) continue;
        const row = {key: key(network), name: String(network.name),
            security: network.security, connected: !!network.connected,
            known: !!network.known, signalStrength: network.signalStrength || 0};
        if (!selected[row.key] || preferred(row, selected[row.key]) < 0)
            selected[row.key] = row;
    }
    return Object.keys(selected).map(k => selected[k]).sort(preferred);
}

// Resolve at activation time; never send credentials to a different security
// type merely because it advertises the same SSID.
function resolve(networks, row) {
    if (!row) return null;
    let result = null;
    for (const network of networks) {
        if (network && key(network) === row.key && (!result || preferred(network, result) < 0))
            result = network;
    }
    return result;
}
