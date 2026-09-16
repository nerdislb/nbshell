# Remaining surfaces: joint acceptance batch

## Scope and reference

The user requested that the remaining inventory be processed in one batch,
with joint visual acceptance afterwards. Rounds 1–20 remain approved; round 21
and this batch are not user-approved until that review.

Reference: Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`.
The Wi-Fi QR surface follows `shell/plugins/panels/wifiqr/Panel.qml`: floating
matrix, quiet caption and strong scrim, without a decorated card. Native
black/white modules, quiet zone, connection metadata and helper remain.
Theme-derived scrim/text and explicit retry/close are deliberate additions;
no new password-reveal feature or upstream networking backend is introduced.

For processes, notes, tasks, habits, shopping, dashboards, work views, agent
center, audio tools, phone/nearby, updates, library and specialized editors,
there is no identical upstream application. Use the pinned panel/menu and
`dev-gallery` language: flat panel, plain title, quiet sections, restrained
selection and shared controls. Retain native services, data and all actions.
Do not describe those adaptations as pixel-identical upstream ports.

Third-party application content keeps its own semantics (mail reader, music,
calendar, gaming). Audit each bundled/installed entry point; correct demonstrated
integration/design defects without replacing original application layouts.
No provider authentication, messaging, device operations or installs are part
of visual verification. Only synthetic fixtures may exercise writable actions.

Custom bar/island/pill and shared theme/motion tokens are unchanged. Previously
approved panels are not restyled. Work-desktop overlays are additional surfaces,
not permission to alter the bar. Existing helper and service implementations
remain authoritative.

## Evidence

Before screenshots and native baseline checks are produced with
`tests/wayland-lifecycle.py --parity-contract --parity-snapshot` in its private
HOME, network, D-Bus and Wayland namespace. The QR fixture contains no credential.
Final checks and limitations are recorded below after verification.


## Inventory and disposition

| Area | Result | Preserved behavior |
|---|---|---|
| Wi-Fi QR | Floating integer-module code, quiet caption, adaptive geometry | Native Wi-Fi helper, black/white quiet zone, retry and error states |
| Processes | Flat frame, compact two-line rows on narrow outputs, focusable rows | PID/start-time identity guard, filter/sort, stop/force-stop; explicit second action confirms |
| Notes / tasks / shopping | Quiet headings, bounded frames and responsive content | Existing editing, dirty-note guard, task shortcuts, shopping preview/send backend |
| Habits | Shared controls, responsive history, scrolling mode-specific actions | 20-week history, routines, all five modes, streaks, shields, sync file; deletion confirms |
| Dashboard / calendar / work | Scrollable narrow overview, bounded month grid, flat work surfaces | Native events/media/tools, work modules and all telemetry sources |
| System hub / agents | Plain titles, readable detail rows and bounded content | Refresh, commands, profiles and install actions unchanged; no profile changed |
| Audio / touchpad | Flat headings, scrollable actions, draft wording | Focus audio/equalizer, apply/revert safeguards and external editors |
| Phone / KDE Connect / Nearby | Wrapping actions and narrow popout bounds | Pairing, camera, mirror, ping/share and transfer backends unchanged |
| Updates / fork / library | Shared update surface retained; library stacks and scrolls | Existing update/apply/manage actions; installs never auto-enable plugins |
| Specialized settings | Dynamic wallpaper header/actions adapted | Immediate-save semantics, file picker, time validation and focus scrolling retained |
| Mail | Four missing `Text.PlainText` declarations fixed | Native account, settings, reader and send behavior unchanged |
| YouTube Music | Narrow window support, wrapping login actions, stacked player footer | Existing shortcuts, two-Escape close guard, playback/login/library/settings semantics |
| Pit Wall | Bounded window and scrollable timing canvas, explicit pan hint | Full timing columns; left/right pan; refresh and close remain |
| Weather / headset / buds / Hermarchy | Bounded popout content; quiet weather/headset headings | Bar cells unchanged; backend/data contracts retained, including legacy headset charging field |
| Existing main/module/display/plugin editors and tray settings | Audited, already use the accepted shared language; not restyled | Previously accepted layouts and guards retained |
| External cloud / prettyzap / quick-translate / omawhatsapp | Installed entry points inspected read-only | Existing native adapters and user installations untouched; authenticated flows not exercised |

Calendar's standalone plugin, update/fork content, and existing compliant editor
bodies were inspected without inventing cosmetic changes. No shared primitive,
bar arrangement, island/pill geometry, provider credentials or agent auth changed.

## Verification

- `tests/qml.sh`: 120 QML tests plus helper/security/behavior suites passed.
- `tests/plugin-validation.sh`, `tests/text-format-contracts.py`,
  `tests/umbriel-contracts.py`, Python compilation and `git diff --check`: passed.
- Real private Umbriel/Wayland rendering: dark 1280×900 with standard motion,
  light 420×600 with reduced motion, intermediate light 600×720, and core
  surfaces at 1440×1080 / 150% output scale. Final full runs contain 73 checks;
  the scaled core run contains 44. Screenshots were inspected, not merely created.
- Native probes exercise frame bounds, focus and Escape; a rendered QR decodes
  back to the synthetic Wi-Fi payload. Task/habit add-and-toggle and unsaved-note
  protection run against disposable files. Held Ctrl-K only arms confirmation;
  a second press terminates the selected private test process.
- Integration fixtures cover offline/empty states, long content, phone/nearby
  sample devices, weather/headset sample values and WorkDesktop. Plugin panel
  services are persistent in the fixture, matching production lifetime.
- Omamail settings native QML: 19 tests passed; its own text-format check passed.
  `make qml-check` exits successfully with existing import/type warnings.
  Full `make validate` is **not green**: the bundled Makefile references missing
  `app/tests/test_theme.js`; the preceding Rust tests passed. No missing upstream
  app tree was fabricated to hide that limitation.

Reproduce the isolated native pass (requires the native pointer client with
`key-press`/`key-release` support):

```sh
python3 tests/wayland-lifecycle.py \
  --compositor /usr/local/bin/umbriel --render-node /dev/dri/renderD128 \
  --pointer-client /path/to/pointer-client --output /tmp/parity-check \
  --parity-contract --width 420 --height 600 \
  --theme catppuccin-latte --motion reduced --qt-backend rhi
```

### Review and functional limits

Independent review was attempted within existing subscriptions: Claude Fable
reported exhausted usage, Sonnet timed out; Antigravity Gemini 3.8 Flash High
was first denied file access and then produced no review with inline input.
Gemini 3.1 Pro High timed out with an empty partial response. None is counted as
an independent approval. No paid fallback or permission bypass was enabled.

Security verdict: **NOT VERIFIED by an independent reviewer**. Local inspection
and focused tests found no new blocking issue. This is not a full security audit.
No real mail/message sending, account login, update installation, Bluetooth/phone
control or cloud quotas were changed/tested. Fixture success does not certify
those external services. Full timing-table width in Pit Wall intentionally uses
horizontal panning on small windows. User visual acceptance remains pending.

## Joint acceptance checklist

1. Speed test from round 21, then Wi-Fi QR and process list (do not stop an
   unrelated process simply to review the appearance).
2. Notes, tasks, shopping and habits: ordinary long entries, scrolling and keys.
3. Dashboard's four tabs, system hub, agents and optional desktop work widgets.
4. Audio tools, touchpad, phone/KDE Connect, Nearby, updates and library.
5. Dynamic wallpaper settings and plugin windows/popouts: Mail, Music, Calendar,
   Pit Wall, Weather, Headset/Buds, Hermarchy; existing external integrations.
6. Confirm custom bar/extras unchanged, then record acceptance or concrete fixes
   in the canonical Brain roadmap. Until then, neither round 21 nor this batch
   should be labelled user-approved.


## Installed-state receipt (2026-09-16)

`./install.sh` completed; the restarted nbshell service is active and
`umbriel validate` passes. All 34 changed runtime files match the repository.
The user configuration SHA-256 is unchanged. The installed dashboard was opened,
visually inspected and closed; no new QML type/binding errors appeared.

Weather and Headset were older unmanaged copies. Their manifests and helper
scripts were retained byte-for-byte in staged packages, with only the new
repository QML installed through `plugins.sh add`. Original packages are backed
up under `~/.local/state/nbshell/parity-backup-20260916/`. Other external plugins
were not modified or enabled. Managed bundled plugins used the normal installer.

The agent terminal has no `WAYLAND_DISPLAY`; CLI instance selection works with
`WAYLAND_DISPLAY=wayland-0`. The earlier unqualified "No running instances"
message did not indicate a dead desktop service. No global environment was changed.
Only synthetic screenshots/logs are archived as project evidence; the live
user-desktop screenshot is excluded.
