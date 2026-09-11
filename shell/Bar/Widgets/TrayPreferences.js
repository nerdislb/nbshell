.pragma library

// SNI Id identifies an application across reconnects; titles and bus names do not.
function key(item) {
    const id = String(item?.id || "").trim();
    return id ? "app:" + id : "";
}

function mode(preferences, item) {
    const value = preferences && preferences[key(item)];
    return value === "pinned" || value === "hidden" ? value : "drawer";
}

function updated(preferences, item, next) {
    const result = Object.assign({}, preferences && typeof preferences === "object"
        && !Array.isArray(preferences) ? preferences : {});
    const id = key(item);
    if (!id)
        return result;
    if (next === "pinned" || next === "hidden")
        result[id] = next;
    else
        delete result[id];
    return result;
}

function visibleItems(items, preferences, expanded, passive) {
    const active = items.filter(item => item && item.status !== passive);
    return active.filter(item => mode(preferences, item) === "pinned")
        .concat(expanded ? active.filter(item => mode(preferences, item) === "drawer") : []);
}
