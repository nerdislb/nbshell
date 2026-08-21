# Use an Android phone as a webcam

nbshell can use an Android 12 or newer phone as a camera for OBS, browsers, and
video-call applications. The integration uses ADB, scrcpy, and the separate
[`nbphone`](https://github.com/nerdislb/nbphone) tool. No Android camera app is
required.

## What it provides

- front and rear camera selection;
- a standard `Phone Camera` V4L2 source at `/dev/video10`;
- a low-latency floating preview;
- direct OBS launch from the phone panel;
- USB or existing wireless ADB connections.

Mirroring and camera capture are separate processes. You may use one without
the other.

## Install nbphone

```bash
sudo pacman -S android-tools scrcpy
git clone https://github.com/nerdislb/nbphone.git ~/projects/nbphone
~/projects/nbphone/install.sh
```

Enable **Developer options > USB debugging** on Android, connect the phone, and
approve the computer.

Run the one-time webcam setup:

```bash
nbphone camera setup
```

This installs `v4l2loopback-dkms`, `v4l-utils`, and the header package matching
the running Arch kernel. Reboot once if `/dev/video10` is not immediately
available.

## Use it from nbshell

1. Open the phone/KDE Connect panel in the bar.
2. Find **PHONE CAMERA · WEBCAM**.
3. Select **Back** or **Front**.
4. Select **Preview** to check framing in a floating 16:9 window.
5. Select **OBS** and add a **Video Capture Device (V4L2)** source.
6. Choose **Phone Camera** or `/dev/video10`.
7. Select **Stop** when finished.

The preview closes automatically when the camera changes or stops. A two-second
service timeout also removes mpv if the V4L2 source disappears unexpectedly.

## CLI

```bash
nbphone camera list
nbphone camera back
nbphone camera front
nbphone camera status
nbphone camera off
```

## Troubleshooting

Check the connection and video device:

```bash
adb devices -l
nbphone status --json
v4l2-ctl --device=/dev/video10 --all
```

If ADB shows `unauthorized`, unlock the phone and approve the computer. If no
device appears, restart ADB with `adb kill-server` followed by `adb start-server`.

If the loopback driver was installed for a different kernel, update the system,
install the matching kernel headers, and reboot. The camera log is stored below
the user's runtime directory in `nbphone/camera.log`.
