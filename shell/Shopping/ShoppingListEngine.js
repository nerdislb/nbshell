.pragma library

function normalizedItem(value) {
    return String(value || "")
        .replace(/^\s*(?:[-*•]|☐|☑|\[\s?\])\s*/, "")
        .replace(/^\s*(?:ich|wir)\s+brauche(?:n)?\s+/i, "")
        .replace(/^\s*(?:bitte|noch)\s+/i, "")
        .replace(/\s+/g, " ")
        .trim();
}

function parse(raw) {
    const text = String(raw || "")
        .replace(/\r\n?/g, "\n")
        .replace(/\s+(?:und|&)\s+/gi, "\n");
    const parts = text.split(/[\n,;]+/);
    const items = [];
    for (let index = 0; index < parts.length; index++) {
        const item = normalizedItem(parts[index]);
        if (item !== "")
            items.push(item);
    }
    return items;
}

function format(items, title) {
    const safeItems = Array.isArray(items) ? items : [];
    if (safeItems.length === 0)
        return "";
    const heading = String(title || "Einkauf").trim() || "Einkauf";
    return "🛒 *" + heading + "*\n\n" + safeItems.map(item => "☐ " + item).join("\n");
}
