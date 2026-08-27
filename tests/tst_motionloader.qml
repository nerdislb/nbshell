import QtQuick
import QtTest
import "../shell/Widgets" as Widgets

TestCase {
    name: "MotionLoaderLifecycle"
    when: windowShown

    Component {
        id: fakeSurface
        Item {
            property var completion: null
            property int reopened: 0
            function requestClose(done) { completion = done; }
            function requestOpen() { reopened += 1; }
            function finishExit() {
                const done = completion;
                completion = null;
                if (done) done();
            }
        }
    }

    Item {
        width: 10
        height: 10

        Widgets.MotionLoader {
            id: loader
            requested: false
            sourceComponent: fakeSurface
        }
    }

    function cleanup() {
        loader.requested = false;
        if (loader.item && loader.item.completion)
            loader.item.finishExit();
        tryCompare(loader, "active", false);
    }

    function test_exit_keeps_surface_mounted_until_completion() {
        loader.requested = true;
        tryCompare(loader, "active", true);
        verify(loader.item !== null);

        loader.requested = false;
        compare(loader.active, true);
        compare(loader.closing, true);
        verify(loader.item.completion !== null);

        loader.item.finishExit();
        tryCompare(loader, "active", false);
        compare(loader.closing, false);
    }

    function test_reopen_during_exit_preserves_surface() {
        loader.requested = true;
        tryCompare(loader, "active", true);
        loader.requested = false;
        compare(loader.closing, true);

        loader.requested = true;
        compare(loader.active, true);
        compare(loader.closing, false);
        compare(loader.item.reopened, 1);

        // A stale completion from the interrupted exit must not unload a surface
        // whose requested state is open again.
        loader.item.finishExit();
        compare(loader.active, true);
        compare(loader.requested, true);
    }

    function test_stale_first_exit_cannot_finish_second_exit() {
        loader.requested = true;
        tryCompare(loader, "active", true);
        loader.requested = false;
        const firstCompletion = loader.item.completion;
        verify(firstCompletion !== null);

        loader.requested = true;
        loader.requested = false;
        const secondCompletion = loader.item.completion;
        verify(secondCompletion !== null);

        firstCompletion();
        compare(loader.active, true);
        compare(loader.closing, true);

        secondCompletion();
        tryCompare(loader, "active", false);
    }
}
