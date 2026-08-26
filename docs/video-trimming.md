# Trim a screen recording

nbshell integrates its lightweight Video Trimmer, maintained in the
[`nerdislb/omacut`](https://github.com/nerdislb/omacut) repository. It previews a
video, lets you drag the start and end handles, and exports the result through
ffmpeg without the complexity of a full video editor.

## Install

The nbshell setup installs the Qt and ffmpeg build dependencies. Install the
trimmer explicitly for the current user:

```bash
nbshell video-trimmer install
```

The command clones the public fork to `~/projects/omacut`, builds it, and
installs only the executable, desktop entry, and icon below the current user's
home directory. Updates and removal remain explicit:

```bash
nbshell video-trimmer update
nbshell video-trimmer remove
```

The fork reads `~/.config/nbshell/palette.sh` and updates its background,
surface, text, light/dark mode, and accent when the nbshell theme changes.

## Daily workflow

After a screen recording stops, its notification offers two actions:

- **Play** opens the recording in the default video player.
- **Trim** opens that exact recording in Video Trimmer.

The Capture menu also contains **Trim latest recording** for the newest video
in the configured recording directory.

Inside Video Trimmer, drag the two handles or use the keyboard:

| Key | Action |
| --- | --- |
| `Space` | Play or pause |
| `Ctrl+Space` | Set trim start at the playhead |
| `Alt+Space` | Set trim end at the playhead |
| `Z` | Zoom into the selected range |
| `Ctrl+S` | Export |
| `Q` | Quit |

The original recording is kept. Exports use MP4 and are written through the
save dialog.
