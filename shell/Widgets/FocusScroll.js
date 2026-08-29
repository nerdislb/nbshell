.pragma library

function contentYForFocus(itemTop, itemHeight, currentY, viewportHeight, contentHeight, margin) {
    const maxY = Math.max(0, contentHeight - viewportHeight);
    const top = Number(itemTop);
    const bottom = top + Math.max(0, Number(itemHeight));
    const inset = Math.max(0, Number(margin));
    let nextY = Math.max(0, Math.min(maxY, Number(currentY)));

    if (top < nextY + inset)
        nextY = top - inset;
    else if (bottom > nextY + viewportHeight - inset)
        nextY = bottom - viewportHeight + inset;

    return Math.max(0, Math.min(maxY, nextY));
}
