# Display settings presentation

Reference: pinned Omarchy `shell/plugins/panels/monitor/Panel.qml`, plus the
approved native settings language in [the reference map](omarchy-look-and-feel.md).
The monitor panel supplies quiet section hierarchy and scale presets; nbshell's
full-screen editor keeps its extra resolution, orientation and placement controls.
This is an adaptation, not a claim of pixel-identical monitor-panel parity.
Brightness stays in the existing control panel and text size in settings.

- Plain title and compact display identity replace the large raised hero card.
- Output selectors and preset controls wrap; descriptions and errors wrap too.
- A single scroll area contains the variable content. Heading and Close stay fixed.
- Tab/Shift+Tab navigate without changing outputs; focused controls scroll into view.
- Escape first collapses the mode list, then closes. Choosing a mode restores focus
  from the destroyed delegate to the mode button through the surviving root.
- Empty/hot-unplugged outputs leave Refresh and Close usable. The last enabled
  output cannot be turned off. Disabled outputs still offer Turn on without a
  misleading last-output warning. All presets and relative positions remain.
  With three or more monitors, the reference remains the first other output.
- `Displays.qml` and the Umbriel configuration backend are unchanged. Opening the
  panel refreshes status only; installation does not change physical outputs.

`tests/displays-lifecycle.py` replaces the display service only inside a disposable
Wayland/home fixture. Native keyboard/pointer tests check emitted set/place requests,
scrolling, wrapping, long mode lists, unplugging, empty/error states, single-output
protection, reopen, outside/Escape close and focus return. They never change the
host resolution, scale, orientation or layout and do not certify physical hotplug
or real mode-switch success.
