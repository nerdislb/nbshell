# Windows stores through Faugus

The Gaming menu uses a shared background setup panel for **Battle.net**, **GOG Galaxy**, and **Epic Games**. Steam, Prism/Minecraft, RetroArch, Moonlight, cloud gaming and controller support remain native. Existing Heroic and Lutris installations are not removed or migrated.

## Flow

Choose **Gaming → Install → launcher**. The panel checks prerequisites, prepares missing Faugus/Proton components, downloads the vendor installer and runs it on a private authenticated X display. Installer dialogs never use the desktop display. After successful setup it creates an Apps entry with the original executable icon and an entry in Faugus, then opens the launcher for sign-in.

Normal Apps starts show the same panel until a new matching launcher window appears. The panel then hides; the launcher remains usable. This detects a window, not authenticated readiness or successful game launch. Account sign-in, MFA and purchases remain in the vendor client.

System package installation may require a normal polkit password prompt. Only packages available in the machine's configured pacman repositories are installed. No repositories are added and no AUR builds run as root. If native Faugus is unavailable there, install it first. This integration does not configure graphics drivers; a working Vulkan/Proton system is required.

## Preservation and recovery

- Each launcher gets its own `~/Faugus/<store>-nbshell` prefix. Existing directories without the expected executable or this installer's ownership marker are refused.
- A running launcher or Faugus library editor blocks setup. Keep Faugus closed until setup completes. Library registration preserves other entries, saves a backup and rechecks for concurrent changes; Faugus itself does not participate in our lock.
- Setup jobs are serialized. Cancellation is tied to a per-job token so an old panel cannot cancel a newer job.
- Cancelling retains incomplete installation files for retry. It terminates only the worker's own process group. Package transactions finish before cancellation is honored.
- Once the vendor installer succeeds, registration retries do not rerun it.
- **Remove → launcher app entry** removes only the nbshell Apps shortcut. It never deletes games, login data, the Wine prefix or the Faugus library entry.
- The Wine `ShowSystray=0` setting suppresses the small Wine desktop/tray helper. The first registry backup is retained before changing it.

## Launcher-specific settings

| Launcher | Installer | Launch options |
|---|---|---|
| Battle.net | Official Blizzard bootstrapper, private X display; close `Battle.net Login` through WM_DELETE_WINDOW and await installer/Agent completion | `--disable-gpu` for the launcher's Chromium UI |
| GOG Galaxy | Faugus components v1.0.1 archive, SHA-256 verified; `GalaxySetup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES` | `--in-process-gpu /deelevated`; **automatic updates are not disabled** |
| Epic Games | Official Epic MSI, `msiexec /i … /passive /norestart` | No extra flags |

Battle.net/Epic use live official HTTPS download URLs rather than frozen installer hashes. GOG uses the pinned archive digest `f024ec31dc90001496986296c63cefc939bca21f6a8e36f17ef9a7edf6923333`. Archive extraction rejects links, absolute paths, traversal and excessive sizes. No vendor binaries or icons are shipped in Git.

Sources: [Faugus recipes](https://github.com/Faugus/faugus-launcher/blob/main/faugus/launcher.py), [Bottles GOG recipe](https://github.com/bottlesdevs/programs/blob/main/Games/gog.yml).

## Commands and state

```sh
nbshell gaming install battlenet
nbshell gaming install gog
nbshell gaming install epic
nbshell gaming launch gog
nbshell gaming status
```

Configuration: `$XDG_CONFIG_HOME/nbshell/gaming/<store>.json` (prefix and Proton paths only).
Logs, download cache and recovery backups: `$XDG_STATE_HOME/nbshell/gaming/<store>/`.
Faugus library: `$XDG_DATA_HOME/faugus-launcher/games.json`.

For an explicit alternate installation location or runner, set `NBSHELL_GAMING_PREFIX` and `NBSHELL_GAMING_PROTON` before invoking setup. Do not point these at a running prefix. The prior `nbshell gaming desktop battlenet` registration command remains available for compatibility.

## Validation scope

Local tests on Umbriel with Faugus 2.3.0 and Proton-CachyOS Latest:

- Battle.net: hidden installation, cancellation/retry, graceful hidden-login handoff, icon and library registration.
- GOG: silent installation returns zero; visible login renders with the documented flags, without suppressing updates.
- Epic: hidden MSI installation, icon/library registration, visible login and loading-panel handoff.
- Fresh-account authentication, actual GOG/Epic game installation, a completely cold dependency bootstrap and other GPUs still require acceptance testing. Reaching a login screen does not prove these paths.

The implementation is developed in an isolated worktree. A source preview is not a deployment: run the normal `./install.sh` from a reviewed complete checkout before testing the Gaming menu on another computer.
