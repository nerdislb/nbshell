# Library, launcher providers, and demo tools

nbshell groups its existing content paths in one on-demand **Library**. Open it
from the main menu or run `nbshell store`. The three tabs have deliberately
different trust models:

- **Themes** lists installed nbshell and compatible imported themes. Applying
  one changes the palette through the normal theme service.
- **Wallpapers** searches every discovered collection and applies an image
  without changing the active theme.
- **Plugins** shows installed extensions and links to the reviewed plugin
  manager and catalog. Browsing never installs or enables a plugin.

The Library is destroyed when it closes. It does not maintain a remote theme
service or another background catalog process.

## Launcher prefixes

The normal application launcher also has lightweight search providers:

| Prefix | Result | Enter |
| --- | --- | --- |
| `#` | Open windows | Focus the selected window |
| `^` | Existing clipboard history | Copy the selected entry |
| `=` | Calculator expression | Copy the result |
| `@` | Files below the home directory | Open the selected file |
| `>` | nbshell commands only | Run the selected command |
| `!` | Installed applications only | Launch the selected application |

Applications, commands, open windows, and calculator answers also participate
in useful unprefixed searches. File search is the exception: it starts `fd`
only after an explicit `@` query, waits briefly while typing, caps the result
set, and keeps no indexer resident.

## Agent-safe system report

`nbshell system-report` prints a stable Markdown map of the compositor, shell,
outputs, services, plugin state, important paths, and available support tools.
Use `--json` for automation or `--write [path]` to create a shareable report.

The report intentionally excludes window titles, clipboard and notification
contents, network addresses, credentials, and tokens. It is suitable as the
first diagnostic attachment for an AI agent, but should still be reviewed
before publishing because host names and output models are included.

## Focused demo recording

The demo helper builds on nbshell's existing capture and Omacut paths:

```bash
nbshell demo start region off   # region or screen; off, mic, or desktop audio
nbshell demo stop
nbshell demo edit               # trim the newest recording in Omacut
nbshell demo export reddit      # also: discord or github
nbshell demo open
```

Recordings live in `~/Videos/nbshell-demos`. Export profiles create smaller,
compatible copies on demand; no recorder or transcoder remains active after
the command finishes.
