# Upstream source review — 2026-09-03

The read-only source audit reported changes in Umbriel, Omazen, Mail, Pit Wall,
and Hermes Agent. No external source was imported wholesale.

## Applied or accepted

- **Omazen `1c11bc65c6a5c6d075ecd4019a6ae0ec615cad94` (1.6.0):** the
  nbshell Arch external-provider patch still applies cleanly. The reviewed build
  pin and documentation now target 1.6.0.
- **Mail `6fdf2903e7c8f3d3b289e44d5b20d1f4c109c992`:** the bundled nbshell
  port remains intentionally divergent. Upstream's CR/LF rejection from
  `7c7f72d5bebac06902eba7bb1359886ae6b1ce19` was ported because the old remote
  image path allowed a mail sender to inject curl configuration directives.
  Other changes are feature work rather than required compatibility fixes.
- **Pit Wall `2ab03dbc5a38841c8fa1648f4f9cc71a6c82243e`:** the upstream delta is
  marketplace text and tests; the native nbshell port needs no code change.
- **Hermes Agent `77adb80d52c70e7ff8186276d977c0fdca320311`:** compatibility and
  security checks passed in isolation. Details are recorded in
  `hermes-upstream-review-2026-09-03.md`.

## Deferred

- **Umbriel `8235b9e0cb97725bcaec9fe1757f5597c847b7e6`:** the release build and
  all nbshell/Umbriel contract tests passed, and the installed compositor at
  this revision validates the active configuration. The full upstream suite
  passed 45 of 50 tests; five vendored `umbrielfx` color/HDR tests failed on the
  review host, including four FP16 readback failures with unsupported format
  `0x30334241` and one PQ round-trip mismatch. The build also reports a possible
  dangling pointer at `umbrielfx/render/fx_renderer/fx_pass.c:1507`. The
  installer and ISO pin remain at `e677dbb` until the renderer failures and
  warning are explained or fixed. The source audit intentionally continues to
  report Umbriel as needing review.
