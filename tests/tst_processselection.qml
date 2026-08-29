import QtQuick
import QtTest
import "../shell/Procs/ProcessSelection.js" as ProcessSelection

TestCase {
    name: "ProcessSelection"

    readonly property var initialRows: [
        { "pid": 101, "started": "Sat Aug 29 10:00:01 2026", "cpu": 50.0, "name": "alpha" },
        { "pid": 202, "started": "Sat Aug 29 10:00:02 2026", "cpu": 30.0, "name": "beta" },
        { "pid": 303, "started": "Sat Aug 29 10:00:03 2026", "cpu": 10.0, "name": "gamma" }
    ]

    function test_selection_follows_process_identity_after_reorder() {
        const reordered = [initialRows[2], initialRows[0], initialRows[1]];
        compare(ProcessSelection.indexForProcess(reordered, 202, initialRows[1].started), 2);
        compare(ProcessSelection.entryAt(reordered, 2).pid, 202);
    }

    function test_reused_pid_does_not_match_old_process() {
        const reused = [
            initialRows[0],
            { "pid": 202, "started": "Sat Aug 29 11:00:00 2026", "cpu": 90.0, "name": "replacement" }
        ];
        compare(ProcessSelection.indexForProcess(reused, 202, initialRows[1].started), -1);
    }

    function test_missing_process_clears_selection() {
        const withoutSelected = [initialRows[0], initialRows[2]];
        compare(ProcessSelection.indexForProcess(withoutSelected, 202, initialRows[1].started), -1);
    }

    function test_movement_uses_reordered_process_position() {
        const reordered = [initialRows[2], initialRows[0], initialRows[1]];
        compare(ProcessSelection.movedEntry(reordered, 101, initialRows[0].started, 1).pid, 202);
        compare(ProcessSelection.movedEntry(reordered, 101, initialRows[0].started, -1).pid, 303);
    }

    function test_invalid_selection_starts_at_first_visible_row() {
        compare(ProcessSelection.movedEntry(initialRows, -1, "", 1).pid, 101);
        compare(ProcessSelection.entryAt(initialRows, -1), null);
        compare(ProcessSelection.entryAt(initialRows, initialRows.length), null);
    }

    function test_empty_model_has_no_selection() {
        compare(ProcessSelection.movedEntry([], 101, initialRows[0].started, 1), null);
        compare(ProcessSelection.indexForProcess([], 101, initialRows[0].started), -1);
    }

    function test_ps_line_parser_preserves_start_identity_and_name() {
        const row = ProcessSelection.parsePsLine("202 12.5 1.5 4096 Sat Aug 29 16:21:27 2026 process name");
        compare(row.pid, 202);
        compare(row.cpu, 12.5);
        compare(row.mem, 1.5);
        compare(row.rss, 4096);
        compare(row.started, "Sat Aug 29 16:21:27 2026");
        compare(row.name, "process name");
        compare(ProcessSelection.parsePsLine(""), null);
    }
}
