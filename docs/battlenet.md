# Battle.net: verified Faugus launcher setup

> The shared background installer is documented in [Windows stores through Faugus](gaming-faugus.md). The registration commands below remain compatible.

This checkpoint packages the tested **launcher**, original app icon and Wine
workarounds. It does **not** yet implement the proposed one-click background
installer or native progress panel. Gaming > Install > Battle.net still uses
the older Lutris setup. No account, prefix, installer binary or game data is
included in this repository.

## Test on another machine

1. Update nbshell and run `./install.sh` from its checkout.
2. Install native Faugus Launcher and `icoextract` through your package manager.
   Install Battle.net using Faugus and provision a Proton runner. This flow is
   for native Faugus, not its Flatpak sandbox.
3. Close Battle.net and wait for its update agent to exit. Register its existing
   prefix (adjust both paths for that computer):

   ```bash
   NBSHELL_BATTLENET_PREFIX="$HOME/Faugus/battlenet" \
   NBSHELL_BATTLENET_PROTON="$HOME/.local/share/Steam/compatibilitytools.d/Proton-CachyOS Latest" \
     nbshell gaming desktop battlenet
   ```

4. Open **Battle.net** from Apps, or run `nbshell gaming launch battlenet`.
   Sign in on that computer normally; never copy account data through Git.

Registration saves the paths in `~/.config/nbshell/gaming/battlenet.json`
(respecting XDG overrides). Without saved settings, the helper checks
`~/Faugus/battlenet-nbshell`, then `~/Faugus/battlenet`. The existing Faugus games
list is not rewritten. The launcher uses Faugus' downloaded `umu-run` directly.

## Verified fixes

- `--disable-gpu` fixes the black **launcher UI** after login on the tested
  Proton-CachyOS/Umbriel setup. It does not change games' graphics settings.
- `PROTON_ENABLE_WAYLAND=0` and `WINE_SIMULATE_WRITECOPY=1` match the tested recipe.
- `HKCU\Software\Wine\Explorer\ShowSystray` (`REG_DWORD`, `0`) suppresses the
  separate little Wine tray window for this prefix without hiding Battle.net.
- Original logo is extracted locally from the installed EXE.
- A shared launch lock prevents duplicate nbshell launches. Logs and the first
  registry backup are private under `~/.local/state/nbshell/battlenet/`.

To restore Wine's default tray behavior, delete only the `ShowSystray` value
using this prefix's `reg.exe`; do not restore an old complete registry after
account/settings changes.

## Evidence and remaining scope

Tested locally on 2026-09-14: Faugus 2.3.0, its UMU 1.4.4, Proton-CachyOS Latest,
Umbriel/Xwayland. An isolated Xvfb installation reached login without installer
clicks, then a normal desktop launch worked. After login, disabling launcher GPU
acceleration restored the rendered client. Apps name/logo and the preserved
login after moving the prefix to persistent storage were visually verified.

The portable registration command needs its own second-machine acceptance.
Fresh-machine provisioning, automatic installer-to-login handoff, cancellation,
download failure recovery and the native loading panel remain future work.
No claim is made about game compatibility or performance.
