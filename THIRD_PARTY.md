# Third-party components and inspiration

nbshell is an independent implementation. Some included components originate
from or were adapted from other MIT-licensed projects:

The complete MIT notices for Omarchy, OmaConnect, Herald Notification Center,
Better Displays, and Omarchy Notification Center are retained in
[`LICENSES/THIRD_PARTY_MIT.md`](LICENSES/THIRD_PARTY_MIT.md). Components with
their own bundled license files are linked below.

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
  [Omarchy YouTube Music](https://github.com/rlimberger/omarchy-ytmusic) and
  incorporates selected MIT-licensed reliability, history, queue, equalizer,
  and UI work from Luke Morrison's
  [Wizwam fork](https://github.com/lukejmorrison/omarchy). nbshell keeps its
  own host, Zen authentication, bar integration, and disabled optional
  Omasing installer. The upstream notices are stored in
  `plugins/ytmusic/LICENSE`.
- The bundled Pit Wall data model and API integration are adapted from Jeremy
  Longshore's MIT-licensed
  [Omarchy Pit Wall Entry](https://github.com/jeremylongshore/omarchy-pit-wall-entry).
  Its license is stored in `plugins/pit-wall/LICENSE`.
- The optional OmaWhatsApp integration downloads a pinned, checksum-verified
  copy of Moiz Ibn Yousaf's MIT-licensed
  [OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp) and adapts
  its manifest and bar entry for nbshell. Its installed plugin retains the
  upstream license. WhatsApp connectivity is provided by the independent,
  MIT-licensed [wacli](https://github.com/openclaw/wacli) project.
- The combined activity center's card hierarchy and icon treatment are
  visually inspired by jankeesvw's MIT-licensed
  [Omarchy Notification Center](https://github.com/jankeesvw/omarchy-notification-center).
  nbshell retains its independent notification and clipboard services.
- Compatibility controls under `shell/Ui/` are adapted from the MIT-licensed
  [Omarchy](https://github.com/basecamp/omarchy) Quickshell UI kit and map its
  public visual tokens onto the nbshell theme system.

Omarchy, niri, Quickshell, and the other named projects are independent from
nbshell. Their names are used only to identify compatibility, provenance, or
inspiration. nbshell is not affiliated with, endorsed by, or an official part
of any of those projects. Their names and logos remain the property of their
respective owners; the software licenses do not grant trademark rights.
