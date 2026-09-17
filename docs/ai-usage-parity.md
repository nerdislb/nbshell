# AI usage bar module

This note covers `shell/Bar/Widgets/AiFill.qml`, its hover preview and its
click popout. The same quota data reaches the dashboard through
`shell/Menu/WorkQuotas.qml`; the two are separate implementations and share no
code, but they now agree on the shared `LevelBar` and on the 90 % warning role.
It follows [the design reference](omarchy-look-and-feel.md) and records the
reference surface, the reused primitives and the deliberate exceptions.

## Reference surface

Omarchy has no AI usage module, so there is no direct port and no upstream
screenshot to match. This is an adaptation in the sense of
[DESIGN.md](../DESIGN.md): it uses the approved bar-module and panel language
plus nbshell's extra functions, and it does not invent new chrome.

Pinned reference: Omarchy Quattro commit
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`. Files read at that revision:

- `default/themed/shell.toml.tpl` — `[bar]`, `[controls]`, `[spacing]`,
  `[font]`, `[popups]`.
- `shell/Commons/Style.qml` — `Style.bar.*`, `Style.spacing.*`, `Style.font.*`,
  `Style.cornerRadius`.
- `shell/Ui/BarIconButton.qml` and `shell/Ui/BarIndicator.qml` — bar module
  geometry and state treatment.
- `docs/omarchy-shell.md` — token and interactive-state contract.

The local research checkouts under `~/.cache/omarchy-research/omarchy` (HEAD
`0b3f1b7`, 2026-08-29) and `~/projects/omarchy-comparison-20260907` (HEAD
`346e69e`, 2026-08-30) are **older** than the pin (2026-09-15) and are shallow
clones holding a single commit each, which is why `git cat-file` cannot resolve
the pin inside them. They must not be used as the reference: at the pin,
`shell/Ui/` also contains `BackgroundMedia.qml`, `BackgroundVideo.qml` and
`PluginBarApi.qml`. Every value quoted in this note was read from the pinned
commit itself. Do not adopt a different revision without recording a new pin
first.

## Extracted rules that apply here

Values are Omarchy defaults at `base-size = 12`, quoted only to make the intent
checkable. nbshell maps them onto `Theme` tokens; it does not copy pixels.

| Rule | Pinned value | Consequence for nbshell |
|---|---|---|
| Rounding is not invented per surface | `Style.cornerRadius` mirrors Hyprland `decoration:rounding` | keep the shared `Theme.radius` (`Config.radius`, 2 by default); no second rounding system |
| Persistent selection is a fill, not an outline | `selected-fill-alpha = 0.18`, `selected-border-width = 0` | use `Segments`, which fills the chosen option |
| Pointer hover, keyboard cursor and focus must be visible on the same control | `focus-*` mirrors `hover-cursor-*` (fill `0.08`, border `1` at `0.25`) | the shared helpers cover hover and selection only, so `Segments` had to pass `visualFocus` explicitly |
| Quota entries are sections, not cards | `[popups]`/`[menu]` describe one surface with its own background and border; approved nbshell panels separate sections with a line | the raised quota `PanelSurface` inside the provider card is gone and entries are separated by `Rule`. Provider `PanelSurface`s remain inside the popout surface, so one frame level remains |
| Bar text is quiet and the bar must not drift | `Style.bar.statusSlot` (21) reserves a fixed status slot; `Style.font.caption` (10) | the bar cell is unchanged and stays icon-only with `slotChars: 0`, so it reserves nothing and the bar cannot drift. This is deliberately not Omarchy's fixed status slot |
| Red is reserved for real attention | `[bar] active = red` | red only for the bar limit state and the LIMIT badge |
| Control padding and panel rhythm | `control-padding 10/6`, `panel-gap 14`, `panel-padding 18`, `popup-padding 14` | `Theme.controlHeight`, `spaceXs`…`spaceLg`, `Theme.panelPadding`. nbshell has no `Theme.popupPadding`; `Popout` and `Cell` both default to `Theme.panelPadding` |
| Numeric proportion uses the shared meter | not fixed upstream | `LevelBar`, the primitive the approved quota dashboard already uses, replaces a duplicated hand-written meter. This is not a claim that Omarchy forbids block meters: `LevelBar` still draws `█`/`░` unless `Config.meterStyle` is `line` |

## Implementation

- Bar cell: `Cell` with `Icons.agent`, `slotChars: 0`. Only the icon shows; the
  quota detail stays in hover and click. Unchanged by this round.
- Hover preview: `BarPreview` with one block per provider; each limit shows its
  label and percentage, a `LevelBar`, and the reset caption.
- Popout: `PanelHead`, a `Segments` view switch, one action row, and one flat
  `PanelSurface` per provider. Limits are sections separated by `Rule`; the
  token view uses `PanelRow` entries.
- Meters: `LevelBar` with `meterCells()` derived from the available width and
  `fillColor` from the shared warning role.
- Warning role: `Theme.yellow` at 90 % or more in the preview and the popout,
  matching the role `WorkQuotas.qml` already uses. The two surfaces still
  differ in detail: the dashboard passes a raw `Theme.yellow` without
  `Theme.readable`. `Theme.red` stays on the bar cell and the LIMIT badge,
  where the module asks for attention rather than reporting a number.

## Deliberate exceptions

- The label/percentage row of a quota entry is built from an `Item` and two
  `Line`s instead of `PanelRow`. `PanelRow` always draws a frame
  (`controlBorderWidth(false, false, false)` returns `borderWidth`), which
  would add yet another frame inside the already framed provider card.
- `meterCells()` clamps to 8…24 cells and measures one cell per 1.2 character
  widths, copied from the approved dashboard. It is a display heuristic rather
  than a layout token, and is recorded here as DESIGN.md requires.
- The popout opens with focus on `Refresh`, the same choice `UpdatePanel.qml`
  makes. The `Segments` switch therefore sits before the initially focused
  control in visual order.
- Two views (limits and local token usage), provider expand/collapse, the
  action row and the `R`/`E`/`Escape` shortcuts are nbshell additions with no
  upstream counterpart. The shortcuts do not test modifiers, so `Ctrl+R` and
  `Ctrl+E` trigger them too; that behaviour predates this round.
- The module is icon-only and has no upstream equivalent; it is not claimed to
  be a pixel match.
- Token usage comes from local history; Omarchy has no equivalent surface.

## Verification

Automated, actually run on 2026-09-17:

- `tests/qml.sh`: 120 passed, 0 failed.
- `tests/design-system-contracts.py`: OK (44 Theme members, 11 Ui exports).
- `tests/ai-local-stats.py` and `tests/text-format-contracts.py`: OK.
- `qmllint` on the changed file: no errors. The Quickshell module imports
  cannot resolve outside the shell, so only import warnings appear.
- `./install.sh` deployed and restarted the shell, kept the user
  configuration, and left no QML error in `nbshell log`.

Visual: before and after screenshots of the open popout were captured from the
running shell in the `nbdark` theme and inspected. Evidence lives in the Second
Brain under `05_Sources/assets/nbshell-ai-usage-lookfeel-2026-09-17/`.

Not inspected, and therefore not claimed:

- the hover preview, which needs a real pointer (no pointer tool is available
  in this session);
- a light theme, reduced motion and a narrow output;
- the isolated-compositor parity run.

Note that `tests/design-system-contracts.py` does not assert anything about
`AiFill.qml`; it guards the `qs.Commons`/`qs.Ui` adapter and the UI gallery.
