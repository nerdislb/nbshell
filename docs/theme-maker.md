# Theme Maker

Open **Menu → Personalize → Look & Feel → Theme Maker**, or run
`nbshell theme-maker`.

The main view uses the same components as `nbshell ui-gallery`, including bar,
controls, inputs, rows and modal states. The editor runs in a separate process:
editing colors does not change the running desktop. **Apply** temporarily previews the draft on the desktop. It does not save a
theme, change the selected library theme or write shell configuration.

- **Basics, Accents, Surfaces:** select a color, enter `#RRGGBB`, open the color
  picker or adjust hue, saturation and lightness. Linked surfaces derive related
  colors when background or text changes; disable linking for individual edits.
  Contrast indicators help assess body and secondary text.
- **Background:** choose any local folder, then an image or video/GIF. Enable the
  background to preview and include it in saved themes. Video is silent and loops;
  animation pauses when the window is inactive or Reduced Motion is enabled.
  Dimming and panel opacity affect the preview only.
- **Files:** load an installed theme, restore the last saved draft or export a
  portable theme folder. Undo can recover edits after loading another base.
- **Compare:** show the original base palette. Undo/Redo restore editing steps.

**Save draft** stores the current editor state locally. **Save theme** creates a
new theme library entry without activating it. **Export** copies the theme and
enabled media to a folder you choose. Existing theme folders are never overwritten;
repeated saves receive a numeric suffix. **Apply** also previews enabled media;
with Background disabled, it preserves the current desktop background.
**Reset preview**, selecting a library theme, or restarting the shell restores
saved settings. Apply leaves the draft marked unsaved. To keep a result, use
**Save theme**, then select it in the theme library for use across restarts.

GIF packaging requires `ffmpeg`: the original GIF is retained and converted to a
video with a still poster for the desktop wallpaper service. Saved media is copied
into the theme so moving the source does not break the saved theme. Drafts retain
source paths, so keep their media in place until saving or exporting a theme.

Shortcuts: `Ctrl+S` saves a draft, `Ctrl+Z` undoes, `Ctrl+Shift+Z` redoes, and
`Ctrl+Q` closes with an unsaved-change prompt. In narrow windows, **Edit theme**
opens the editor over the preview; **Hide editor** reveals the full preview.
