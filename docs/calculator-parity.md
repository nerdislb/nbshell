# Calculator alignment

## Scope and reference

Round 20 adapts the standalone calculator to the pinned Omarchy Quattro
`6ea3215542fbb269dfe5c2be928e6144f9cb6466` panel/menu language
(`shell/plugins/menu/Menu.qml`, `shell/Ui/`, `shell/Commons/`). There is no
corresponding standalone calculator in that source: this is an adaptation,
not a pixel-identical port. The approved settings and auxiliary native panels
are the closest precedent for retaining a functional nbshell-only window.

Keep the resizable FloatingWindow, all twenty keypad actions, arithmetic-only
CalculatorEngine, keyboard expressions, percent/comma input, backspace, sign,
result continuation and clipboard copy. The custom bar, launcher calculator,
IPC evaluator and global Theme tokens are outside this round.

Use the shared PanelSurface and ControlButton, quiet title and secondary labels,
foreground border and flat selection/hover, with accent only for focus and result.
Retain native window sizing; cap initial size to the focused output. Long
expressions/results must remain inspectable and small windows usable.

## Native behavior and intentional differences

- Remains a regular floating, resizable window without an overlay scrim or
  outside-click dismissal. Compositor decorations remain compositor-owned.
- Uses existing character-cell geometry for the keypad, not a fictitious
  upstream calculator geometry. Initial size is capped to the current screen.
  Only the calculator's fixed 430×650 compositor override was removed; floating
  and automatic focus rules remain. All other window rules are untouched.
- Reuses PanelSurface, Rule, ControlButton, Line and Qt Flickable/ScrollBar.
  No new shared component or global token changes.
- Clear is no longer styled as a destructive system action. Operators remain
  visible; accent is reserved for result/equals and focus.
- Long expressions wrap and can be inspected by wheel, drag, scrollbar or
  PageUp/PageDown. A new expression reveals its result after layout settles.
- Tab visits Copy then the twenty keys in reading order. Space/Enter activates
  the focused control; direct typing and Enter calculation use a dedicated
  leaf focus target. Pointer activation returns there for continued typing.
- Copy is disabled for invalid expressions and all copy paths reject invalid
  data. Negative numbers now pass `--` to wl-copy, avoiding option parsing.
  Copy confirmation still indicates dispatch, not a monitored subprocess exit.
- Arithmetic-only parser, all key labels/actions and the IPC evaluator are
  unchanged. No eval, network access or new dependency was introduced.

## Verification

`tests/calculator-lifecycle.py` extends the existing private Wayland harness.
It applies the actual shipped calculator window policy and exercises real
keyboard/pointer input, accessible actions, isolated wl-copy/wl-paste, focus
return, lifecycle, long/invalid content and minimum size. Run with:

```sh
python3 tests/wayland-lifecycle.py --compositor /usr/local/bin/umbriel \
  --render-node /dev/dri/renderD128 --output /tmp/calculator-dark \
  --calculator-contract --pointer-client /path/to/pointer-client \
  --width 1280 --height 800 --qt-backend rhi
```

Repeat at 420×600 with `--theme catppuccin-latte --motion reduced`.
The output directory must not already exist. The harness has private HOME,
Wayland, D-Bus and network namespaces; clipboard fixtures never touch the user
clipboard. Its white background window is a synthetic focus-return target.

Visual baseline: old native calculator, pinned original Menu select render
(reused from round 19, same dark theme/font/output), then running new calculator
in dark/light. This compares visual language, not calculator pixel parity.
The early old screenshot was tiled by the minimal harness; final native tests
apply the production floating policy. No exact upstream calculator exists.

Review limitation: earlier bounded subscription-only Claude and Gemini calls
in this alignment session hit quota/timeouts. No independent approval for this
round is claimed, and no paid fallback or repeated probe loop was enabled.

Final checks: 38 native assertions per dark/light run (76 total), plus 120 shared
QML tests and their helper/security suites; design and Umbriel contracts pass.
Native compositor resize actions (not ignored client-side size requests) exercise
the minimum geometry. The installed configuration validates, runtime source is
byte-identical and the existing user configuration hash is unchanged.
The global PlainText scan still reports four pre-existing Omamail findings
(CalendarSettings:171; SettingsPage:280,308,316), unrelated to this round.
The installed live calculator was opened and visually inspected; no QML runtime
type or binding errors appeared. A bare checkout's nbshell.toml references a
runtime-generated outputs include; validate the installed complete configuration.
