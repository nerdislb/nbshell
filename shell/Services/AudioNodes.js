.pragma library

function uniqueSinks(nodes, preferred) {
    var result = [];
    var positions = Object.create(null);
    var values = nodes || [];

    for (var index = 0; index < values.length; index++) {
        var node = values[index];
        if (!node || !node.audio || !node.isSink || node.isStream)
            continue;

        var name = String(node.name || "").trim();
        var key = name === "" ? "anonymous:" + index : "name:" + name;
        var existing = positions[key];
        if (existing === undefined) {
            positions[key] = result.length;
            result.push(node);
        } else if (node === preferred) {
            result[existing] = node;
        }
    }

    return result;
}
