# Minecraft

Choose **Gaming → Install → Minecraft**. The themed setup panel installs native
Prism Launcher and the Minecraft icon without a terminal. System authentication
may appear when packages are missing.

For a fresh profile, setup selects the latest stable Minecraft Java release
from Mojang's version manifest and creates a vanilla **Minecraft** instance.
Language, theme and automatic Java management are prepared, so Prism opens
directly at **Add Microsoft account**, without the language/Java/theme wizard.

Click **Add Microsoft account** and complete Microsoft's sign-in yourself.
Prism then finishes its login page automatically, downloads the compatible Java
runtime and game files, and starts Minecraft. Prism's own download/progress or
error dialogs can still appear; these are not suppressed. nbshell never reads,
stores or enters account tokens and never creates an offline account to bypass
ownership checks. A licensed Minecraft Java account is required to play.

**Minecraft** appears in Apps with a stable grass-block icon. Later launches use
the selected instance directly. Existing instances, worlds and configured
profiles are preserved rather than silently upgraded to another release. Close
Prism before running setup. Retry repairs the app entry without deleting games.
If a legacy/custom profile exists, its existing setup requirements still apply.

Cancel waits for an active package transaction to finish and keeps installed
packages and data. After handoff, use Prism's own cancel controls for sign-in or
downloads. Package logs live under `$XDG_STATE_HOME/nbshell/gaming/minecraft/`
(default `~/.local/state/nbshell/gaming/minecraft/`). Changed pre-existing Prism
settings are backed up there before fresh-instance preparation.

```sh
nbshell gaming install minecraft
nbshell gaming desktop minecraft
nbshell gaming launch minecraft
```

Minecraft uses native Linux packages, not Wine/Faugus. Setup does not add
repositories or invoke an AUR helper. The grass-block icon comes from the
installed `papirus-icon-theme` package, not bundled vendor artwork.

The onboarding contract was checked against [Prism Launcher 11.0.3 source](https://github.com/PrismLauncher/PrismLauncher/tree/11.0.3),
including `Application::createSetupWizard`, `LoginWizardPage` and `--launch`.
