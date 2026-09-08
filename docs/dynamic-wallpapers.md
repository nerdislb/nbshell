# Dynamic wallpapers

Double-click an empty desktop to open the wallpaper picker, then choose **DYNAMIC**
(or press **d**). Settings save immediately; **BACK** returns to the picker.
Both modes are off by default and work independently.

- **DAYTIME** selects one of four slots using local time: Morning 06:00, Day
  10:00, Evening 18:00, Night 22:00. Edit the unique HH:MM start times to suit
  your routine. The last slot continues across midnight. The clock is checked
  every 30 seconds, including after resume; this does not continuously render.
- **VIDEO** enables silent, looping local video files. With DAYTIME off it uses
  the All Day video; with DAYTIME on it uses the current slot's video.
- Assign an **IMAGE** to each slot as its still wallpaper. Empty image slots
  use your usual theme/custom wallpaper. Empty video slots stay static.
  Missing images fall back to the usual wallpaper; video errors keep the still
  image and display an error in the settings.

Videos only run on external power, including computers without a battery.
A fully charged laptop on external power is eligible. Any mapped window on
that output's active workspace stops its video. Windows on other workspaces
or outputs do not prevent an otherwise empty desktop from animating. Unknown
compositor state keeps playback stopped.

The player is destroyed on battery, when windows appear, during the native
nbshell lock, during automatic idle screen-off/screensaver, with Reduced Motion,
or when wallpapers/video are disabled. Playback resumes from the start after
750 ms of an eligible desktop. There is no separate audio output. A matching
still image avoids an obvious jump when a loop stops.

Manual DPMS commands outside the idle service and third-party lockers do not
currently expose their state to this feature. Their hidden videos are not
explicitly stopped by those events alone. This is an energy-management
limitation, not a lock-security change.

Use short 720p or 1080p H.264 MP4 loops at 24–30 fps initially. Qt Multimedia
chooses the available decoder; hardware decoding is platform/codec dependent
and is not guaranteed. Each eligible output creates its own player. Stills
have no continuous video workload; active video adds decode, rendering and
memory cost. Measure CPU, GPU and power with the actual clip and screen layout
before assigning a percentage or watt estimate. Synthetic headless
tests establish functionality, not real desktop power consumption.

Settings live under `dynamicWallpaper` in the normal nbshell config, independently
of per-theme carousel selections. **CLEAR** removes a slot assignment; turning
a mode off preserves its assignments for later use.

Run the isolated integration regression with an Intel/AMD render node:

```sh
python3 tests/wayland-wallpaper.py --compositor /usr/local/bin/umbriel \
  --render-node /dev/dri/renderD128 --output /tmp/wallpaper-check
```

It uses a private Wayland and D-Bus session, generates a small test clip, checks
keyboard entry, decoding progress, window gating, repeated native-lock marker
cycles and missing-video fallback, and saves screenshots. The output directory
must not already exist. Use `--theme catppuccin-latte --motion reduced --width
640 --height 480` to exercise the alternate UI fixture (playback is subsequently
tested with standard motion). OpenGL is required to inspect VideoOutput frames;
Qt's software scene graph did not display them in the local test.
