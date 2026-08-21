# Third-party components and inspiration

nbshell is an independent implementation. Some included components originate
from or were adapted from other MIT-licensed projects:

- Color definitions under `themes/` come from
  [Omarchy](https://github.com/basecamp/omarchy). See
  [themes/ATTRIBUTION.md](themes/ATTRIBUTION.md).
- Bongo Cat images and related behavior are based on wayland-bongocat and
  HANCORE's Omarchy plugin. Their licenses are included under
  `shell/assets/bongocat/`.
- Parts of KDE Connect discovery were adapted from
  [OmaConnect](https://github.com/jitendradara12/omaconnect).
- The AI usage provider was integrated from the MIT-licensed
  `aiOverviewControl`. Its license is stored in
  `shell/scripts/ai-usage/LICENSE`.
- Notification source detection, focus actions, and card structure were
  inspired by Jesse Burlamaque's MIT-licensed
  [Herald Notification Center](https://github.com/jesseburlamaque/herald-notification).
  nbshell keeps its own persistent notification service and TUI implementation.
- The interaction concept for granular per-output controls was inspired by
  nightdevil00's MIT-licensed
  [Better Displays](https://github.com/nightdevil00/better.displays). nbshell
  uses an independent Niri-native backend and does not use its Hyprland/Lua
  implementation.
- The bundled Omamail port comes from Jason Lee's MIT-licensed
  [Omamail](https://github.com/huacnlee/omamail). Its Gmail, IMAP/SMTP,
  credential-storage, and message-sanitization implementations and tests are
  retained; nbshell supplies the host lifecycle, bar widget, and theme adapter.
  The upstream license is stored in `plugins/omamail/LICENSE`.
- The bundled YouTube Music port comes from rlimberger's MIT-licensed
  [Omarchy YouTube Music](https://github.com/rlimberger/omarchy-ytmusic).
  nbshell replaces the Omarchy host integration and leaves its optional
  Omasing installer disabled. The upstream license is stored in
  `plugins/ytmusic/LICENSE`.
- Compatibility controls under `shell/Ui/` are adapted from the MIT-licensed
  [Omarchy](https://github.com/basecamp/omarchy) Quickshell UI kit and map its
  public visual tokens onto the nbshell theme system.

Omarchy, niri, Quickshell, and the other named projects are independent. Their
mention does not imply endorsement or an official relationship.
