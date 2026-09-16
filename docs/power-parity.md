# Battery / power: Omarchy alignment

`PowerPanel.qml` follows Omarchy Quattro's power panel at reference commit
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`: large percentage, battery hero,
slim charge meter, compact two-column facts and three profile choices. Width,
padding, typography and borders scale with the existing font/theme tokens.
The battery bar cell, hover preview, watts display and bar/island/pill stay.

Bluetooth and reachable paired KDE Connect battery reports remain below the
power controls, including low-charge warnings and devices without a report.
Long device lists scroll; read-only rows are keyboard-focusable so their full
accessible labels remain reachable. Names use the existing plain-text `Line`.
A small local gutter keeps the shared scroll indicator off the content.

- Arrows or H/J/K/L move focus; Enter/Space, pointer clicks and accessibility
  activation share one guarded profile action. Hover does not steal key focus.
- The active profile is read back from **tuned**, never optimistically selected.
  Requests while busy and invalid profile names are rejected. Nonzero exits
  and failure to start are visible; retrying does not require closing the panel.
- Unknown/custom profiles retain their actual name, select none of the three
  choices and offer Refresh. On reopening, initial focus goes to Refresh.
- Escape and clicks on underlying application surfaces dismiss the panel.
  The shared popup lifecycle and its existing empty-background/reopen limits
  are unchanged. No live keyboard injection is required to verify installation.

## Intentional differences

nbshell retains tuned (`powersave`, `balanced`, `throughput-performance`),
UPower, device battery sources, health and battery-side wattage. No
power-profiles-daemon, Omarchy helper dependency or additional polling is added.
Battery capacity, cycle count and charge-limit heuristics from the reference
are not newly implemented. Status is literal rather than rotating slogans;
charging does not continuously pulse. Zero percent really has zero fill.
Existing theme, radius, Reduced Motion and low-battery notification policy stay.

## Verification

`tests/wayland-lifecycle.py --power-contract` runs the production QML on a
private Umbriel seat with isolated network/D-Bus and synthetic UPower/device
data. The production profile methods and Process lifecycle invoke an absolute
private fake `tuned-adm` executable. No test can change the host energy profile.

It checks navigation without accidental activation, busy/invalid guards,
failed process, successful retry and canonical readback, missing executable
and recovery, a real pointer profile click, twelve-device scrolling, excluded
unpaired/offline devices, empty extras, unknown profile, charging/full/plugged/
low/zero states, dismissal and focus return to an underlying application.
Dark/standard and small light/Reduced Motion renders are inspected. These are
not hardware power-management or native screen-reader end-to-end tests.

Deployment inspection: installed source/runtime copies match and the existing
configuration is unchanged. The real desktop panel opens and closes by its
battery cell; the actual phone battery and unchanged Balanced profile are
visible. Existing agent notification toasts obscure its upper part, so full
hero/layout inspection uses the isolated renders. Those notifications are not
dismissed or modified by this round. Native screen-reader behavior is not claimed.
