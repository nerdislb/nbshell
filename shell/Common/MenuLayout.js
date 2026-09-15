// Shared menu geometry and pointer arbitration. No application/service state.
.pragma library

function rowsHeight(heights, spacing) {
    return heights.reduce((sum, height) => sum + height, 0) + Math.max(0, heights.length - 1) * spacing;
}

// Leave a partial row at the fold, as in Omarchy. A selected row is still
// revealed in full by each view's normal scrolling contract.
function foldedHeight(heights, spacing, available) {
    const cap = Math.max(1, available);
    const total = rowsHeight(heights, spacing);
    if (total <= cap) return total;
    let used = 0;
    for (let i = 0; i < heights.length; ++i) {
        const peek = Math.round(heights[i] * 0.55);
        if (used + heights[i] > cap)
            return Math.max(1, Math.min(cap, used + peek));
        used += heights[i] + spacing;
    }
    return cap;
}

function nextIndex(index, delta, count) {
    return count > 0 ? ((index + delta) % count + count) % count : 0;
}

// List mutations can synthesize hover events without physical pointer motion.
// Track in window coordinates so a moving/resizing card cannot steal selection.
function moved(previous, point) {
    return previous !== null && (Math.abs(point.x - previous.x) > 1 || Math.abs(point.y - previous.y) > 1);
}
