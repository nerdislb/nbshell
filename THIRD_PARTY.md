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

Omarchy, niri, Quickshell, and the other named projects are independent. Their
mention does not imply endorsement or an official relationship.
