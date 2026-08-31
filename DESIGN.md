# nbshell design system

nbshell is a compact, keyboard-first desktop shell with a character-grid rhythm, a visible wallpaper, semantic theme roles, and one shared interaction language across core surfaces and plugins. This document is the stable design contract for new UI. It describes the incumbent system; it does not replace nbshell's identity with a generic toolkit.

## Public UI contracts

There are two supported import paths:

- `qs.Common` and `qs.Widgets` are the native nbshell API. New nbshell surfaces and plugins should prefer them.
- `qs.Commons` and `qs.Ui` are the compatibility API for portable Omarchy-style controls and existing plugins.

Both paths resolve to the same active theme and state language. Do not create a third token layer inside a plugin.

## Visual identity

- Monospace typography and measured character cells establish the layout rhythm.
- Panels are flat, compact, and mostly square, with the active theme visible through semantic color roles.
- Wallpaper remains part of the composition; scrims separate summoned surfaces without erasing workspace context.
- Accent is reserved for focus, selection, activity, and meaningful status. Urgent colors identify actual warnings or destructive actions.
- The bar keeps its own island and pill geometry. Shared panel rules must not make the bar larger or card-like.

## Tokens

Use `Theme` roles instead of private values:

- Palette: `bg`, `fg`, `fgDim`, `fgBright`, `accent`, status colors, and contrast helpers.
- Surfaces: `panelSurface`, `panelSurfaceRaised`, `panelBorder`, `focusBorder`, and `scrim`.
- Typography: `fontCaption`, `fontBody`, `fontSubtitle`, `fontTitle`, `fontHeading`, and `fontDisplay`.
- Spacing and geometry: `spaceXs` through `spaceXl`, `controlHeight`, `rowHeight`, `panelPadding`, overlay dimensions, cell metrics, and bar metrics.
- Motion: effects, spatial, enter, exit, attention, and loop tokens. Every animation must honor `reducedMotion`.
- State: `controlFill()`, `controlBorder()`, selected surfaces, and readable foreground helpers.

A hard-coded metric is acceptable only for a domain-specific visualization whose meaning cannot be expressed by an existing token. It must not become a second spacing, typography, color, or motion system.

## Components

Prefer the highest-level shared primitive that matches the task:

- Surfaces: `PanelSurface`, `MotionSurface`, `OverlaySurface`, and `Popout`.
- Structure: `PanelHead`, `SectionHeader`, `PanelRow`, `PanelSeparator`, `Rule`, and `Facts`.
- Actions: `ControlButton`, `ActionButton`, `InteractiveSurface`, `Segments`, and `MenuView`.
- Input: `TextField`, `PanelSlider`, `LevelBar`, and established Qt controls adapted through the shared theme.
- Bar: `Cell`, `IconText`, `Glyph`, and the shared bar icon slots.

Do not rebuild a standard button, row, text field, slider, focus surface, or panel shell from `Rectangle` and `MouseArea`. Extract a new shared primitive only after the same intent appears in at least three places.

## Interaction

- Pointer hover and keyboard cursor use the same visible state.
- Persistent selection remains visible when the selected control receives focus.
- Every interactive control has an accessible role, name, visible focus, and one guarded activation path.
- Panels and overlays close with Escape and expose the plugin `open(payloadJson)` / `close()` lifecycle when applicable.
- Tab follows visual reading order. Panel-local directional navigation must not trap focus inside editors or popups.
- Destructive actions name the consequence and require confirmation when they are not easily reversible.

## Motion and performance

- Animate only when motion explains state, relationship, or causality.
- Use shared effects/spatial tokens and the `MotionSurface` lifecycle.
- Keep Wayland surface geometry stable during transitions; transform content instead of resizing complex trees per frame.
- Avoid continuously repainted `Canvas`, hidden perpetual animations, aggressive polling, and duplicate desktop services.
- Reduced Motion replaces non-essential motion with an immediate state change.

## Adaptive and theme verification

Every visible surface must be checked with:

- one dark and one light theme;
- keyboard-only operation and visible focus;
- Reduced Motion;
- a narrow or small-screen geometry;
- empty, loading, error, disabled, selected, and long-content states that apply to it.

`nbshell ui-gallery` is the living reference for shared primitives and states. New shared components belong in the gallery using their real implementation, never a visual copy.

## Plugin golden path

Create new plugins with:

```sh
nbshell plugin new io.github.user.example --kind panel
```

Then run:

```sh
nbshell plugin validate .
nbshell plugin design-check . --strict
```

The design check flags private color palettes, fixed UI metrics, hard-coded animation durations, missing shared imports, and incomplete panel or overlay lifecycle behavior. A narrowly scoped suppression comment is allowed for an intentional specialist visualization; it is not a waiver for a private design system.
