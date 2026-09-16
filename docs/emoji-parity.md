# Emoji picker: Omarchy alignment

Reference: Omarchy Quattro `6ea3215542fbb269dfe5c2be928e6144f9cb6466`,
`shell/plugins/emojis/Emojis.qml`. Scope: native `Menu/EmojiWindow.qml` only.
Reuse its centered 400×500 card and minimum 44px cells, scaled with the existing
menu scale, menu palette, foreground border, plain search heading and adaptive
scrolling grid. Native MotionSurface, TextField and InteractiveSurface provide
the controls; no global token, bar, or other approved-surface changes.

Preserve all 69 existing emoji sequences and German/English keyword aliases.
Add English accessible names (also searchable). Keep native wl-copy semantics,
not Omarchy's external emoji-insert helper or a new auto-paste behavior. The
existing compact curated catalog is intentionally retained, not replaced by
Omarchy's larger dataset. This round introduces no dependencies.

Deliberate native additions: a real editable search field (caret, selection,
paste and input-method support), focus outlines, accessible cell names, a short
footer, explicit empty state and single guarded copy path. Escape clears a
query first, then closes, matching Omarchy. Native text editing retains
Left/Right/Home/End in the search field; Down/Up/Tab enter the grid. Grid arrows,
Home/End and Page keys reveal the selected cell; Tab returns to search. Ctrl+F
or Ctrl+L selects the query. Pointer movement changes the selected copy target
without stealing focus from active text entry. Enter/Space on a cell and its
accessibility action use the same copy path; auto-repeat cannot copy twice.

## Verification

`tests/wayland-lifecycle.py --emoji-contract` passes 37 checks at each of
1280×800/TokyoNight and 360×480/Latte/Reduced Motion (74 total). Real private
Umbriel, keyboard/pointer input and wl-copy/wl-paste verify native search editing,
Ctrl+A/Ctrl+V, empty results, grid navigation, scrolling, focus return, hover,
Escape/outside/IPC close and reopen, stale-selection rejection, accessible press,
and exact flag/variation-selector sequences. Only copy-call recording is added;
the copy effect itself is not replaced. Host clipboard and user data are never
exposed to this fixture. All original emoji/keyword pairs and their ordering
also match the pre-change source exactly.

Before/after, dark/light, empty/search and scrolled states were inspected.
The unmodified pinned upstream Emojis.qml and its real catalog/controls were
also rendered on private Umbriel at 1280×800 and 14px base font, including a
heart search, for a direct geometry/typography comparison. Only a standalone
ShellRoot wrapper is supplied. Expected missing-hyprctl style-probe warnings
remain confined to that reference sandbox; no Hyprland dependency is added.

All 120 shared QML tests, design/Umbriel contracts, Python compilation, installer
shell syntax and compositor configuration validate. Native field selection and
paste are verified; external IME composition, physical multi-monitor behavior
and screen-reader operation are not separately exercised.

Independent review remains unavailable: the bounded Haiku attempt timed out
at 60 seconds, after Sonnet and Antigravity/Gemini attempts in this same alignment
session had already timed out. No independent review approval is claimed;
existing subscriptions only, no paid fallback or authentication changes.

Installation verified: runtime source is byte-identical, nbshell remains active,
user configuration hash is unchanged, and the live picker was opened/inspected
without copying into the host clipboard. No QML type/reference/binding errors
appeared in the checked live interval. The full text-format scan still reports
four pre-existing Omamail plugin labels (CalendarSettings:171 and
SettingsPage:280/308/316), outside this change.
