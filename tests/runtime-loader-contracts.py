#!/usr/bin/env python3
"""Keep Runtime surface flags and shell loader wiring in sync."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
runtime = (ROOT / "shell/Common/Runtime.qml").read_text(encoding="utf-8")
shell = (ROOT / "shell/shell.qml").read_text(encoding="utf-8")

open_flags = set(re.findall(r"\bproperty\s+bool\s+(\w+Open)\s*:", runtime))
lazy_flags = set(re.findall(r"LazyLoader\s*\{\s*active:\s*Runtime\.(\w+Open)\s*;", shell))
motion_flags = set(re.findall(r"requested:\s*Runtime\.(\w+Open)\b", shell))
loaded_flags = lazy_flags | motion_flags

# These flags are hosted by permanent bar/window roots rather than shell.qml's
# on-demand surface loaders. Keeping the list explicit makes a newly added flag
# fail until its lifecycle owner is deliberately classified.
always_mounted = {
    "audioPanelOpen",
    "calendarOpen",
    "clipOpen",
    "controlOpen",
    "islandOpen",
    "launcherOpen",
    "menuOpen",
    "notifyOpen",
}

unknown_wiring = loaded_flags - open_flags
if unknown_wiring:
    raise SystemExit(f"shell loaders reference undeclared Runtime flags: {sorted(unknown_wiring)}")

unowned = open_flags - loaded_flags - always_mounted
if unowned:
    raise SystemExit(f"Runtime surface flags have no loader or permanent owner: {sorted(unowned)}")

stale_allowlist = always_mounted - open_flags
if stale_allowlist:
    raise SystemExit(f"permanent Runtime owner allowlist is stale: {sorted(stale_allowlist)}")

for match in re.finditer(
    r"MotionLoader\s*\{\s*requested:\s*Runtime\.(\w+Open)\s*"
    r"sourceComponent:\s*Component\s*\{\s*(\w+)\s*\{",
    shell,
    re.S,
):
    flag, component = match.groups()
    if not any((ROOT / "shell").glob(f"**/{component}.qml")):
        raise SystemExit(f"{flag} loads missing component {component}")

for match in re.finditer(
    r"LazyLoader\s*\{\s*active:\s*Runtime\.(\w+Open)\s*;\s*(\w+)\s*\{",
    shell,
):
    flag, component = match.groups()
    if not any((ROOT / "shell").glob(f"**/{component}.qml")):
        raise SystemExit(f"{flag} loads missing component {component}")

print(f"Runtime/loader contracts: OK ({len(open_flags)} surface flags)")
