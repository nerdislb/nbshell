# Join the nbshell public beta

nbshell is an independent, keyboard-first desktop shell for the Umbriel Wayland
compositor, with Niri retained as a recovery fallback. It combines a searchable interface,
coherent themes, system controls, capture tools, and optional device and plugin
integrations without replacing the normal Linux tools underneath.

The first beta is intended for people who already use Arch Linux or an
Arch-based distribution and are comfortable selecting a fallback session or
recovering from a terminal. Commands and configuration may still change before version 1.0.

## What is worth testing

- Fresh Umbriel installation, login, update, and Niri fallback recovery.
- Bar, island, and pill layouts at different display scales.
- The workspace-local grid-scroll mode with two, three, and eight windows.
- Search across nested shell actions and installed desktop applications.
- Theme switching, compatible Omarchy theme import, terminal colors, lock
  screen, and wallpapers selected independently from the active theme.
- NetworkManager VPN, PipeWire audio, display, capture, and power controls.
- Published-release checks, checksum verification, and the distinction between
  nbshell, system-package, and plugin updates.
- Optional plugins and phone integrations on systems where their dependencies
  already exist.

Use the full [beta checklist](beta-testing.md) for structured testing.

## Install

Do not run the setup as root. Start from an existing session or TTY:

```bash
git clone https://github.com/nerdislb/nbshell.git
cd nbshell
./setup.sh
nbshell switch on
```

Log out and select Umbriel. The installer keeps Niri available as a recovery
session and preserves personal nbshell settings during updates.

## Report feedback

Use a GitHub bug report for reproducible failures and a feature request for a
specific improvement. Include the nbshell revision, Umbriel, Niri, and
Quickshell versions, display layout, GPU/driver, and the shortest reproduction
sequence.
Sanitize logs: never post tokens, notification text, clipboard contents,
calendar entries, network addresses, or private file paths.

## Suggested announcement

> I built nbshell, an independent Quickshell desktop shell for Umbriel with a
> Niri recovery fallback. Its first public beta brings a searchable
> keyboard-first UI, native scrolling/dwindle layouts, coherent desktop theming
> with compatible Omarchy theme import,
> a wallpaper library, system controls, capture tools, and optional phone and
> plugin integrations, plus a checksum-verified updater for published shell
> releases. It keeps Niri selectable for recovery and normal Linux tools underneath
> instead of becoming another full desktop environment. If you use Arch and
> Wayland and enjoy testing early desktop software, I would value your feedback.

Add the repository link, the hero screenshot, and a short grid-scroll video to
the post. Describe the project as Omarchy-inspired and compatible, never as an
Omarchy port or an endorsed project.

## Screenshot and video sequence

1. Lead with `01-menu-grid.png`: three windows demonstrate the layout while
   the main menu establishes the visual language.
2. Use `04-theme-picker.png` to show live palette selection and explain that
   compatible Omarchy themes can be imported locally.
3. Use `02-wallpaper-picker.png` to demonstrate that wallpaper and color theme
   are independent choices.
4. Use `03-dashboard-tools.png` for the integrated tools overview.
5. Use `05-quick-notes.png` as a smaller feature image, especially when also
   showing synchronization with nbOS.

For the video, lead with Umbriel's smooth scrolling/dwindle switch, overview,
and one live theme change so the bar, menu,
terminal, and lock-screen preview visibly change together. Keep the clip under
90 seconds. A second short Niri clip may demonstrate the fallback-only paired
grid-scroll mode. Avoid notifications, calendar data, network names, and
personal paths.
