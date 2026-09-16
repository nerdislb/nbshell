# Bluetooth: Omarchy alignment

`BluetoothSection.qml` brings Omarchy Quattro's Bluetooth hierarchy (reference
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`) into nbshell's existing combined
control panel. It does not add another bar widget or replace the DuoBar icon,
network area, VPN or brightness controls.

- Bluetooth heading, radio switch, real status, device icons and two-line
  connected rows with battery levels; connected, paired and available groups.
- All devices remain reachable, replacing the old eight-device truncation.
  A font-relative 400 px list viewport and the outer panel scroll handle long
  lists and small screens.
- Enter/Space, pointer and accessibility use the same guarded actions. Native
  Tab and the control panel's Up/Down/J/K navigation remain available.
- Forget appears on row hover/focus, requires a second activation, and Escape
  cancels the confirmation without closing the panel. A missing device or
  disabled radio clears it. A separate sibling control and pointer hit exclusion
  prevent forgetting from also triggering connect/disconnect.
- Discovery refreshes preserve focus by address. Delegates hold primitive
  snapshots only; actions resolve the current BlueZ object at activation time.
- The existing scan ownership and 30-second limit remain. Scan/Stop controls
  operate only nbshell's request, not another application's discovery session.
  Closing the combined panel releases its scan as before.
- The established pairing agent and backend, device battery reporting and
  notification behavior are unchanged. Pairing errors are also visible inline.

## Intentional differences

Bluetooth stays embedded in the combined panel rather than becoming a separate
Omarchy popout. Connected rows share its bounded list viewport. The scan button,
two-step forget confirmation, explicit device counts/state and nbshell's existing
pairing workflow are retained. No automatic audio-output switching, new BlueZ
agent, Omarchy command dependencies, destructive right-click shortcut or rotating
status slogans are introduced. Existing paired-versus-bonded backend semantics
are not changed by this visual round. The active theme/font/radius remain yours.

## Verification

`tests/wayland-lifecycle.py --bluetooth-contract` uses the production QML on an
isolated Umbriel seat with a private D-Bus/network namespace and synthetic devices.
It checks connect/disconnect/pair dispatch, current-object resolution after a
snapshot, twelve reachable devices, focus restoration, scan ownership, keyboard
and pointer forget confirmation/cancel/disappearance, disabled/empty/no-adapter
states, popup dismissal and return to an underlying window. Device operations
cannot reach host BlueZ. Dark/standard and small light/Reduced Motion renders
are inspected alongside a regression run of the network contract and QML suite.

The reference UI is also rendered in isolation using synthetic devices. This is
not an end-to-end Bluetooth radio/pairing test. Physical-desktop inspection at
deployment remains unavailable while the laptop reports no enabled display.

The keyboard test uses one persistent virtual keyboard before a separate
pointer-only phase. An exploratory interleaving of newly created virtual pointer
clients with that held keyboard did not satisfy the return-key assertion; it is
not treated as proof of physical-seat behavior or as a fixed compositor issue.
Outside-click checks target the underlying application: a click on empty space
without a client surface did not dismiss the popup in the isolated small-output
probe. The existing native popup/reopen boundaries are not repaired by this
Bluetooth styling change.
