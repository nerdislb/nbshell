# Omarchy look-and-feel reference

This is the reference map for the mandatory [design contract](../DESIGN.md).
It applies to every agent and contributor working on nbshell UI, including plugins.

## Baseline and original guidance

The approved alignment rounds use Omarchy Quattro commit
`6ea3215542fbb269dfe5c2be928e6144f9cb6466`. Do not silently chase a moving branch;
record a new reference revision explicitly before adopting later changes.

Upstream paths at that revision:

- [AGENTS.md](https://github.com/omacom/omarchy/blob/6ea3215542fbb269dfe5c2be928e6144f9cb6466/AGENTS.md): task routing and visual verification.
- [Shell reference](https://github.com/omacom/omarchy/blob/6ea3215542fbb269dfe5c2be928e6144f9cb6466/docs/omarchy-shell.md): Color, Style, Border, interactive states, spacing and typography.
- [Visual verification](https://github.com/omacom/omarchy/blob/6ea3215542fbb269dfe5c2be928e6144f9cb6466/agents/skills/visual-verification.md): inspect running UI, not just generated artifacts.
- `default/themed/shell.toml.tpl`, `shell/Commons/`, `shell/Ui/`, and
  `shell/plugins/dev-gallery/`: tokens, actual controls and living examples.

Those files are references, not instructions to run Omarchy/Hyprland services
on this desktop. nbshell's native lifecycle, configuration and Umbriel adapters
remain authoritative for integration.

## Approved surface map

| Surface | Upstream reference | nbshell implementation / intentional additions |
|---|---|---|
| Menu / launcher | `shell/plugins/menu/` | `shell/Menu/Menu.qml`, launcher; extra categories/search modes |
| Audio, network, Bluetooth, power | `shell/plugins/panels/` | Native panels; routing, codecs, VPN, device batteries retained |
| Notification toasts | `shell/plugins/notifications/` | Native notifications; history, DND and actions retained |
| Activity / clipboard | `shell/plugins/clipboard/` | Two-column activity view; history tab and search retained |
| Themes / wallpaper | `shell/plugins/image-picker/` | ThemeGallery / WallpaperPicker; collections and dynamic wallpaper retained |
| Settings main view | Panel / developer-gallery language; no exact upstream editor | Native settings navigation; all options and recovery retained |
| Module arrangement | Approved settings language; no exact upstream editor | Native four-group editor; independent island layout retained |
| Plugin manager | Approved settings language; no identical upstream manager | Installed/store/porting tabs and confirmations retained |
| Display settings | `shell/plugins/panels/monitor/` + native settings language | Resolution/orientation/placement retained; backend unchanged |
| Calculator | Panel/menu language; no standalone upstream calculator | Native floating keypad, arithmetic parser, keyboard and clipboard retained; `docs/calculator-parity.md` |
| Custom bar | Deliberate nbshell exception | Existing bar/island/pill preserved; DuoBar icon explicitly requested |

Approved rounds above must not drift during unrelated work. See the relevant
`docs/*parity.md` notes and task evidence for behavior and verification limits.

## Settings and surfaces without an exact counterpart

Omarchy routes setup through its menu and dedicated panels; the pinned source
has no direct equivalent of nbshell's all-in-one settings editor. Do not claim
pixel-identical parity for an invented upstream settings window. Use its panel
and developer-gallery navigation language: a plain title, quiet section labels,
subtle selection/hover, proportional spacing, flat borders and clear focus.
Keep native settings, config errors/recovery and specialized views reachable.

## Required handoff

Every visible change records:

1. Surface scope, pinned source paths and preserved nbshell extras.
2. Reused primitives/tokens, deliberate deviations and any inaccessible reference.
3. Before/reference/after inspection; keyboard, pointer, Escape, focus return,
   long content, dark/light, small output and Reduced Motion where applicable.
4. Focused test results and installed-state verification; explicitly state gaps.

Passing a linter is not a visual match. Model agreement is not verification.
No new palette, spacing system or animation language may be introduced locally.
A source-derived geometry may be scoped and attributed; a reusable token change
requires explicit impact review across its consumers. Extend the real UI gallery
when adding a shared primitive. Keep UI and repository documentation in English.
