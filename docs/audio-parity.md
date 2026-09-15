# Audio panel: Omarchy alignment

The audio popout follows Omarchy Quattro's audio panel at upstream commit
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`, with the existing nbshell Audio
service and Umbriel popup lifecycle. The bar and its passive preview are not
restyled. Routing and Bluetooth codec controls remain below the core sections.

## Presentation and interaction

- Font-relative 380 px outer width, 14 px padding, 2 px accent border and a
  560 px height cap (values at a 12 px base font), also bounded by the screen.
- Audio heading, combined mute switch, smooth monochrome volume sliders,
  output/input device rows and per-application sources.
- Microphone volume, input-device selection and an input peak meter are now
  available directly. Peak monitoring only runs while an audio panel is open.
- **Up/Down** or **J/K** move focus. **Left/Right** or **H/L** adjust the focused
  channel by 5 percentage points; **M**, **Enter** or **Space** mute it. Enter
  on a device, route or codec selects it. **Tab/Shift+Tab** retain native nbshell
  traversal rather than switching to a different panel.
- The header switch mutes/unmutes **both output and microphone**, as in the
  reference. Its accessible name and tooltip explicitly describe both.
- Right-click a slider to mute that channel. Bar wheel/right-click behavior is
  unchanged. Existing configured output/application volume limits remain in
  force; microphone volume is limited to 100%.
- Keyboard focus and mouse hover use the same visible cursor. Long lists
  scroll, including late-arriving routes and codecs, without remapping or
  resizing the open native Wayland popup. Escape/outside click dismiss it;
  audio no longer closes merely because the pointer left it.

The active font, palette and corner radius remain user-controlled. nbshell
retains its own device names, routing/backend semantics, volume limits and
bar anchoring. It does not implement all Omarchy `shell.toml` overrides, DSP
sink resolution, or cross-panel Tab switching. This is a scoped alignment,
not pixel identity across every theme and compositor.

## Verification

`tests/audio-lifecycle.py`, via `tests/wayland-lifecycle.py --audio-contract`,
uses real Quickshell components on a private Umbriel seat. In-memory nodes
replace PipeWire data **only in the disposable test copy**; neither host audio,
network nor the system bus is exposed. Tests cover volume/mute input, output,
streams, device switching, route/codec actions, late content, empty state,
bounds and focus return. Dark/standard and small light/Reduced Motion runs
are used together with the existing panel-switch focus regression.

## Focus probe boundary

The full native matrix covers a passive-preview-to-panel transition, real key
input, device removal while the panel is open, and return to an underlying
window. A separate empty-panel probe succeeds with 300 ms between pointer
entry and click (less than the 420 ms preview delay).

A synthetic immediate move/click, and a separate rapid empty-state reopen
sequence with a volume OSD, exposed a native-focus timing gap: QML reported
focus while Escape reached the underlying window. The precise compositor /
parent-layer / OSD interaction is not resolved by this styling change. Do not
interpret the passing main matrix as proof that every synthetic reopen timing
is fixed. No such keys were injected into the user's desktop.
