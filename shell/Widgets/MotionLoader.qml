import QtQuick

// Keeps a lazy top-level surface mounted until its visual exit completes.
// The requested flag is product state; mounted is rendering lifetime. A loaded
// window may expose requestClose(done) and requestOpen() to drive its shared
// MotionSurface. Without that contract the loader still closes safely.
Loader {
    id: root

    required property bool requested
    property bool mounted: false
    property bool closing: false
    property int generation: 0

    active: mounted
    asynchronous: false

    function beginClose() {
        if (!mounted || closing)
            return;
        if (!item) {
            mounted = false;
            return;
        }
        closing = true;
        const closeGeneration = generation;
        if ("requestClose" in item && typeof item.requestClose === "function")
            item.requestClose(() => root.finishClose(closeGeneration));
        else
            finishClose(closeGeneration);
    }

    function finishClose(closeGeneration) {
        if (closeGeneration !== generation)
            return;
        if (requested) {
            closing = false;
            if (item && "requestOpen" in item && typeof item.requestOpen === "function")
                item.requestOpen();
            return;
        }
        closing = false;
        mounted = false;
    }

    onRequestedChanged: {
        generation += 1;
        if (requested) {
            const wasClosing = closing;
            mounted = true;
            closing = false;
            if (wasClosing && item && "requestOpen" in item && typeof item.requestOpen === "function")
                item.requestOpen();
        } else {
            beginClose();
        }
    }

    onLoaded: {
        if (!requested)
            beginClose();
    }

    Component.onCompleted: mounted = requested
}
