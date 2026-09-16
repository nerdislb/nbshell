# On-screen volume and brightness display

Reference: pinned Omarchy `shell/plugins/osd/Osd.qml` and `OsdModel.js`.
Measured glyph, smooth track and fixed readout replace the old text/block meter.
The attributed 16px padding/gaps, 142px track and 67px edge clearance use native
`Theme.uiScale`; typography, colors, border and motion use shared Theme roles.
The uniform accent track intentionally replaces kind-specific tints, matching
Omarchy; mic/brightness keep distinct symbols. The Qt ProgressBar is display-only, with the entire Wayland input region empty.

Preserved nbshell exceptions:

- All screens show the OSD, opposite the bar's configured edge.
- Pill ownership suppresses the standalone card, without changing the pill.
- User timeout, enabled setting, startup guard and open-panel suppression remain
  in the unchanged service. No audio/brightness backend writes are added.
- Microphone and mute states remain supported; muted uses a zero meter and a
  readable Muted label. Values above 100 keep their readout but clamp the track.
- Width animation uses shared motion tokens, is disabled for Reduced Motion,
  and never changes the Wayland surface geometry.

`tests/osd-lifecycle.py` exercises the real OSD service's timeout/suppression with
synthetic value/mute properties only in a disposable shell copy. Native pointer
and keyboard events verify click-through and unchanged underlying focus.
Dark/light, narrow output, repeated updates, mute, mic, brightness, bounds,
pill and opposite-edge cases are covered. No real hardware value is changed.
Original upstream geometry/code is inspected; a separate original-OSD rendering
is not claimed. Physical multi-monitor rendering remains a separate check.
