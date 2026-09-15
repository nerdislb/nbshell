# Network panel: Omarchy alignment and DuoBar indicator

The network area follows Omarchy Quattro at
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`, retaining nbshell's Net service,
Umbriel popup lifecycle, VPN controls, brightness, Bluetooth, QR and Speedtest.

## Panel

- Font-relative 380 px outer width, 14 px padding and 2 px accent border
  (at a 12 px base font), bounded by the available screen.
- Connection heading, QR/Speedtest/radio actions, compact connection facts,
  and connected/saved/other network groups. All Wi-Fi rows remain reachable;
  the old eight-network truncation is removed.
- A 240 px font-relative inner Wi-Fi viewport keeps extensions accessible;
  the full panel also scrolls when the screen is smaller than its content.
- Up/Down or J/K move focus. Enter/Space activate the focused action; Tab
  remains native nbshell traversal, not Omarchy's cross-panel switching.
- Unknown secured networks open a masked passphrase field. Enter submits;
  Escape clears the field without closing the panel. Scan snapshots preserve
  the editor. A disappearing network, disabled radio or destroyed panel clears
  the pending credential. Activation resolves the current node by SSID AND
  security, not a retained backend object.
- Escape/outside click dismiss the panel. Pointer leave alone does not.

This is a scoped visual/interaction alignment, not complete network-feature
parity: Omarchy's DNS provider/band controls, IP/gateway/ping metrics, enterprise
identity editor, forget flow and full asynchronous connection feedback are not
ported here. Existing known-network credential recovery limitations are unchanged:
a saved network whose password changed has no dedicated re-entry UI here.
The active palette/font/radius, service semantics and nbshell extensions remain.
The native reopen timing boundary documented in [audio-parity.md](audio-parity.md)
is not claimed fixed by this round.

## DuoBar symbol

At the user's request, the existing network cell now renders the compound
indicator from [leewhitfield/omarchy-duobar](https://github.com/leewhitfield/omarchy-duobar),
pinned at `a5f042e8595fde76752eac20763c664096cf907a`:

- outer arc: battery charge; urgent color at 20% or lower while on battery;
- center: Wi-Fi strength, disconnected/off state, or Ethernet;
- four dots: Bluetooth **radio** state, not a device count;
- lightning: charging.

The event-driven glyph is adapted with both MIT notices preserved in
`DuoGlyph.qml`. Only the visual is reused, not the upstream plugin installer or
its read-only popup. Click still opens the full nbshell control panel. Hover and
accessibility include battery/network/Bluetooth status. The separate battery
widget, bar geometry, text-only mode and existing cell actions remain available.
No extra daemon, polling process, network request or continuous paint timer is
introduced by the glyph.

## Verification

`tests/wayland-lifecycle.py --network-contract` runs production QML in a private
Umbriel/Wayland/D-Bus/network namespace. Only the disposable Net copy has synthetic
networks and harmless action recorders. No host connection is changed and no
password contents are written into receipts.

Checks cover 14 networks, last-row visibility, passphrase preservation/cancel/
submit/removal, open-network and disconnect actions, captive portal, VPN,
no-adapter fallback, scanner/traffic lifecycle and native keyboard return.
Dark/standard and small light/Reduced Motion runs accompany the existing
Control/Audio focus regression. `tst_duoglyph.qml` checks actual repaint differences
for battery, charging, Bluetooth, weak/off Wi-Fi, Ethernet and foreground changes.

Deployment is via `./install.sh`; user configuration is preserved. At deployment
the laptop reported no enabled output, so the installed physical-desktop visual
check remains pending. The isolated renders were inspected; these are not a
substitute for claiming an observed physical-desktop result.
