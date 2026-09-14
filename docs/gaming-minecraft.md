# Minecraft

Choose **Gaming → Install → Minecraft** to prepare the native Prism Launcher,
Java 21 and the Minecraft app icon. The themed setup panel stays visible while
packages install in the background. System authentication may still appear;
there is no terminal and Prism does not open automatically.

After successful verification, **Minecraft** appears in Apps with the Papirus
Minecraft grass-block icon. Choose **Open Minecraft** or launch it later from
Apps. Existing Prism instances, accounts and worlds are not changed by setup.

On a new installation, sign in and create or import a game instance in Prism.
This interactive account/game-version step is not automated. Subsequent app
launches use the selected existing instance, falling back to another existing
instance or the Prism window when none exists.

Retrying setup repairs the app shortcut and icon even when packages are already
installed. Cancel waits for an active package transaction to finish and keeps
installed packages and game data. Errors remain visible with Retry; package
output is stored privately under `$XDG_STATE_HOME/nbshell/gaming/minecraft/`
(default `~/.local/state/nbshell/gaming/minecraft/`).

```sh
nbshell gaming install minecraft
nbshell gaming desktop minecraft
nbshell gaming launch minecraft
```

Minecraft uses native Linux packages, not Wine or Faugus. Packages must be
available in the configured Arch-compatible repositories; setup does not add
repositories or invoke an AUR helper. The icon comes from the installed
`papirus-icon-theme` package; no vendor artwork is bundled in nbshell.
