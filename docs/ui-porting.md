# Porting Omarchy surfaces and building new ones

This is the working procedure behind [the design contract](../DESIGN.md) and
[the reference map](omarchy-look-and-feel.md). It exists so that reaching
Omarchy's look and feel is a mechanical step, not a negotiation repeated on
every surface.

## The one rule

**Port what upstream has; compose what it doesn't.** A component that exists in
the pinned Omarchy kit is ported into `qs.Ui`, not rebuilt. A surface upstream
has no counterpart for is assembled from the ported components and the shared
`qs.Widgets` primitives — never from a fresh `Rectangle` with its own colours,
metrics or animation durations.

Rebuilding is what makes parity drift: every hand-built control is a second
opinion about spacing, states and focus, and the two opinions separate over
time.

## The two layers

| Layer | Module | Role |
|---|---|---|
| Upstream channel | `qs.Commons` (`Color`, `Style`, `Border`, `Util`), `qs.Ui` | Runs original Omarchy QML unchanged on nbshell tokens |
| Native channel | `qs.Common` (`Theme`, `Config`), `qs.Widgets` | nbshell's own primitives and the character-grid rhythm |

New nbshell-only work should prefer the native channel. Anything that is
supposed to look like an upstream surface goes through the upstream channel.

## Two ways a port fails

Both were real, and both were invisible until something was measured:

1. **A missing singleton member.** Upstream calls `Style.bar.iconSlot` or
   `Color.popups.text`; the adapter does not provide it. QML reports nothing
   useful at the call site, the property is simply `undefined`.
2. **A missing component.** Upstream ships `Dropdown`; nbshell has none, so the
   surface gets hand-built chrome.

`tests/ui-kit-coverage.py` reports both. Run it before and after a port:

```sh
tests/ui-kit-coverage.py                       # report, exits 0
tests/ui-kit-coverage.py --strict              # gate, exits 1 on any gap
tests/ui-kit-coverage.py --omarchy <checkout>  # a specific revision
```

It only knows about `shell/Ui`. A checkout that is not the pinned commit gives
approximate numbers; point it at the pin for a decision.

## Porting a component

1. Read the component at the pinned commit, not from a convenience checkout.
   The local research clones are shallow and older than the pin.
2. Copy it into `shell/Ui/` and register it in `shell/Ui/qmldir`.
3. Change **only** the import if needed (`qs.Commons` / `qs.Ui` already map to
   nbshell). Do not restyle it on the way in; a port that also redesigns is no
   longer a port.
4. Add its contract to `tests/tst_uicompat.qml` — public API, signals, focus
   and accessibility behaviour, activation guards.
5. Run `bash tests/qml.sh` and `tests/ui-kit-coverage.py --strict`.
6. Deploy with `./install.sh` and inspect the real surface. A green test is not
   a visual match.

## Building a surface upstream has no counterpart for

1. Compose it from ported `qs.Ui` components and `qs.Widgets` primitives.
2. Reuse `Theme` tokens for colour, spacing, type and motion. No private
   palette, no new spacing scale, no literal duration.
3. Record it in the surface map in [omarchy-look-and-feel.md](omarchy-look-and-feel.md)
   as an intentional addition, and add a `docs/<surface>-parity.md` note naming
   the reference surface, the reused primitives and the exceptions.
4. Add a real component to `nbshell ui-gallery` when the work extends the
   shared set.
5. Add a native contract to `tests/wayland-lifecycle.py`
   (`--<surface>-contract`) so behaviour is probed, not assumed.

If a surface genuinely needs a new visual language rather than a composition,
that is a deliberate exception. It needs the owner's approval and an entry in
the surface map — not a quiet local decision.

## Adapter fidelity, and where it deliberately differs

The adapter is faithful in **structure**: names, arities and call order match
upstream so ported code runs unchanged. It is deliberately different in
**palette**, because nbshell keeps its own semantic roles:

- `Style.controlFill` accepts both conventions. Four arguments mean upstream
  order `(focused, hot, foreground, accent)`; three arguments with a state
  string mean the nbshell convention. The arity disambiguates them.
- `Style.controlBorder(focused, hot, foreground, accent, urgent)` and
  `Style.controlBorderWidth(focused, hot)` follow upstream order. The earlier
  `controlBorder(enabled, hot, ...)` "disabled means muted" special case is
  gone; a caller that needs it handles disabled state itself.
- Selection uses the reference treatment: a **foreground wash**, not an accent
  tint. `selectedSurface()` returns `mix(bg, fg, 0.18)` — upstream's
  `[controls] selected-color = foreground` with `selected-fill-alpha = 0.18` —
  and the text on it stays accent, which is upstream's
  `[menu] selected-text = accent`. The wash is mixed opaquely so a control's
  foreground contrast never depends on what sits behind a translucent fill.
  The `tone` argument is kept because 46 call sites pass it positionally; it no
  longer tints the surface.
- `Theme.hover` is `mix(bg, fg, 0.08)`, upstream's
  `hover-cursor-fill-alpha = 0.08`. This is **not** cosmetic: with the wash in
  place, the earlier `0.14` left hover and selection four alpha points apart in
  the same hue, and surfaces that give selection and focus the same border
  (for example `Menu/AgentCenter.qml`) became unable to show which item was
  chosen and which merely focused. The reference ratio `0.08 : 0.18` restores
  the gap.
- `Util.execDetached` and `Util.execArgv` are **not** ported. Both need
  `Quickshell.execDetached`, and importing the Quickshell module in a compat
  singleton breaks the stock Qt test runner (the `quickshell-coreplugin` cannot
  load outside the Quickshell process), which takes the whole `qs.Commons`
  module down with it. Use a nbshell service to launch processes.
- `Border.surfaceSpec` is not provided yet.

The compat singletons must stay loadable by `qmltestrunner`. Anything that
requires the `Quickshell` module belongs in `shell/Widgets`, `shell/Services`
or a plugin, not in `qs.Commons`.

## Bar adoption

The bar keeps nbshell's own island/pill geometry and its collapse behaviour —
the owner's explicit exception — while following the reference for its optics.
The pinned reference gives `[bar] size-horizontal = 26` at a 12px font base,
scaling with the font. nbshell's character-grid derivation produced 27px at its
14px font: a ratio of 1.93 against the reference's 2.17, so the bar sat tighter
around its text than the reference does.

Adopted, measured on the running shell:

| Metric | Reference at base 12 | nbshell at font 14 | Result |
|---|---|---|---|
| bar cross-axis | 26 | 27 (grid-derived) | 30, the reference ratio, used as a floor |
| icon canvas | 16 | 19 | unchanged, already at the reference ratio |
| status slot | 21 | 21 | exposed to ports through `Style.bar.statusSlot` |

`Config.lines` and `Config.padY` stay user settings: the reference ratio is a
floor (`Theme.barReferenceHeight`), so a multi-line bar still grows. Before and
after were inspected at 27px and 30px; no clipping, icons stay centred.

Not adopted, and why: `size-vertical`, upstream's fixed status slot as a
requirement, and the Hyprland-derived corner radius. nbshell's icon slot is a
glyph advance width, not a button width, so upstream's 27 is a different
measurement and copying it would space the bar wrongly.

## Gates

| Check | Catches |
|---|---|
| `tests/qml.sh` | adapter fixture drift, component contracts, accessibility behaviour |
| `tests/design-system-contracts.py` | adapter references a `Theme`/`Config` member the fixture or production lacks |
| `tests/ui-kit-coverage.py` | missing adapter member, unported component |
| `tests/text-format-contracts.py` | formatted/rich text where plain text is required |
| `tests/motion.sh` | literal animation durations |
| `nbshell plugin design-check <dir> --strict` | plugin-side private palettes and metrics |
| `tests/wayland-lifecycle.py --<surface>-contract` | real behaviour under a private compositor |

## Reference bump

A new pinned commit is a deliberate act, not a routine update:

1. Note the old and new commit in [omarchy-look-and-feel.md](omarchy-look-and-feel.md).
2. Check out the new revision and run `tests/ui-kit-coverage.py --omarchy <path>`.
3. Diff `default/themed/shell.toml.tpl` and the `Style`/`Color` singletons
   against the previous pin. A changed token value is a surface-wide change.
4. List what the new revision adds, removes or renames.
5. Adopt it in one recorded step, re-verify the affected surfaces, and update
   the non-conforming list below.

Never follow the branch implicitly. "Upstream changed" is not a reason for the
installed shell to change appearance without a decision.

## Known non-conforming list

This is the honest remainder, to be shortened deliberately:

- `Border.surfaceSpec` (adapter member)
- 21 upstream components, listed by `tests/ui-kit-coverage.py`
- the bar's own island/pill geometry and collapse behaviour (intentional)
- `Util.execDetached` / `Util.execArgv` (see above)
- selection and focus still share one border on several surfaces, for example
  `Menu/AgentCenter.qml`, `Menu/Dashboard.qml`, `Habits/HabitsList.qml` and
  `Procs/ProcessList.qml`. Upstream drops the border on a selected control
  (`selected-border-width = 0`); nbshell keeps it, so the fill gap is doing the
  work. Worth aligning one surface at a time.
- `Habits/HabitsList.qml` expresses the *done* status through `ControlButton`'s
  `selected`, and `Procs/ProcessList.qml` replaces a red CPU warning with the
  selection fill. Both are statuses, not selections, and read weaker since the
  wash replaced the accent tint.

## Selection and focus: decision taken 2026-09-17

The owner asked for the reference selection treatment, so it is adopted and the
open decision is closed:

| Token | Value | Upstream |
|---|---|---|
| `selectedSurface()` | `mix(bg, fg, 0.18)` | `[controls] selected-color = foreground`, `selected-fill-alpha = 0.18` |
| `Theme.hover` | `mix(bg, fg, 0.08)` | `[controls] hover-cursor-fill-alpha = 0.08` |
| text on selection | accent, contrast-adjusted | `[menu] selected-text = accent` |

Upstream has no `[panels]` section, so `0.18` is the control-chrome value and
there is no documented panel-row value to adopt. Panel **rows** therefore carry
the controls value; menus and launchers already used the lighter `0.08` through
`Theme.menuSelection` and were not touched.

The surface-by-surface re-check this change requires is not complete. Reviewed
and confirmed unaffected: `Menu/Menu.qml`, `Launcher/Launcher.qml`, the emoji,
keybindings, capture, calculator, toast and speed-test surfaces (all either on
`menuSelection` or without a selection state). Regression fixes made so far:
`Widgets/ActionButton.qml` (primary emphasis is not selection),
`Bar/Widgets/CalendarPanel.qml` (selected day outside the shown month), and
`Theme.hover` above.

One correction to the record: the message of commit `f6ac022` cites "the
launcher's selected row" as evidence for the new treatment. The launcher reads
`Theme.menuSelection` and was not affected by that commit. Only the second half
of that claim — the AI popout's `Widgets/Segments.qml:85` — holds.
