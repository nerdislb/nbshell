#!/usr/bin/env python3
"""Pure layout-policy tests for the Niri grid-scroll helper."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


path = Path(__file__).parents[1] / "shell/scripts/grid-layout.py"
spec = spec_from_file_location("grid_layout", path)
assert spec and spec.loader
grid = module_from_spec(spec)
spec.loader.exec_module(grid)


assert [grid.desired_column_sizes(count) for count in range(7)] == [
    [], [1], [1, 1], [2, 1], [2, 2], [2, 2, 1], [2, 2, 2]
]

# A partial page may face either direction. Closing one half of a 2x2 grid
# must therefore settle immediately instead of expelling and merging windows.
assert grid.stable_column_sizes([2, 1], 3)
assert grid.stable_column_sizes([1, 2], 3)
assert grid.stable_column_sizes([2, 2], 4)
assert not grid.stable_column_sizes([1, 1, 1], 3)
assert not grid.stable_column_sizes([1, 2, 1], 4)
assert not grid.stable_column_sizes([3], 3)

# The policy remains predictable beyond the first 2x2 page.
for count in range(13):
    desired = grid.desired_column_sizes(count)
    assert sum(desired) == count
    assert all(size in (1, 2) for size in desired)
    assert grid.stable_column_sizes(desired, count)

# Focus, keyboard, overview and configuration events must not wake the layout
# controller. Niri can emit many of these while no window arrangement changed.
assert grid.event_affects_layout('{"WindowsChanged":{"windows":[]}}')
assert grid.event_affects_layout('{"WorkspacesChanged":{"workspaces":[]}}')
assert not grid.event_affects_layout('{"OverviewOpenedOrClosed":{"is_open":true}}')
assert not grid.event_affects_layout('{"KeyboardLayoutsChanged":{"current_idx":0}}')
assert not grid.event_affects_layout('not json')

assert grid.ipc_action("ConsumeOrExpelWindowLeft", 42) == {
    "ConsumeOrExpelWindowLeft": {"id": 42}
}
assert grid.CLI_ACTION_NAMES["ConsumeOrExpelWindowLeft"] == "consume-or-expel-window-left"
assert grid.compositor_override_text(Path("/tmp/niri-atomic")) == (
    "[Service]\nExecStart=\nExecStart=/tmp/niri-atomic --session\n"
)
assert grid.SESSION

print("Grid layout policy: OK")
