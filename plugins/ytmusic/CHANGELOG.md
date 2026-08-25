# Changelog

## 1.2.0

- Make first playback more reliable with an Android yt-dlp client, a larger
  cold-cache resolve budget, and background challenge-cache warm-up.
- Recover automatically from stopped or disconnected backends and keep Home
  shelves cached across reconnects.
- Add local play history, merged with YouTube history when signed in.
- Add queue reordering and a persistent ten-band equalizer with presets.
- Improve sign-in errors, responsive artwork, controls, tooltips, and keyboard
  accessibility while retaining nbshell's Zen session import.
- Keep the live spectrum analyzer out to avoid a continuous capture process,
  FFT work, and high-frequency UI updates.

## 1.1.0

- Recreate the backend socket after a dropped connection so the player can recover.
- Sign in by copying the YouTube Music session already in Chromium on this computer.
- Keep pasted request headers as a fallback.
- Keep the local mpv process off the Wayland session so tracks actually start.
- Use a D-Bus-safe mpv client name so MPRIS cannot freeze playback.
- Publish the song title to MPRIS instead of the googlevideo stream URL.
- Refresh that MPRIS title when the next track starts, not after the stream URL loads.
- Keep the bar slot as the YouTube Music logo only.

## 1.0.0

- First release: Omarchy bar widget, mini-player, and full player for YouTube Music.
- Started from [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify).
- Local playback through a plugin-owned mpv backend and yt-dlp, not Chromium.
- Library, search, playlists, queue, likes, radio, sleep timer, and Omasing lyrics.
