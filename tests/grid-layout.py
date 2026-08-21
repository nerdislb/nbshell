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

print("Grid layout policy: OK")
