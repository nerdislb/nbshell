# Developing nbshell plugins

nbshell plugins are QML components loaded into the long-running shell process.
They can add a bar widget, a floating panel, an overlay, or a background
service without changing nbshell itself.

Creativity is welcome. The compatibility and safety rules below are not
optional: plugin code runs unsandboxed with everything the current user can
access.

## Start from the scaffold

Create a plugin with the same generator used by the contract tests. Choose the
runtime kind that owns the plugin's primary responsibility:

```bash
nbshell plugin new io.github.alice.weather --kind bar-widget
nbshell plugin new io.github.alice.weather-panel --kind panel
nbshell plugin new io.github.alice.weather-overlay --kind overlay
nbshell plugin new io.github.alice.weather-service --kind service
```

The default output directory is the final segment of the plugin id in the
current working directory. Use `--output`, `--name`, or `--author` to override
the generated metadata. Each scaffold uses the public theme and component APIs,
contains no private palette or motion constants, and passes strict design
checks before it is written.

Validate the directory before loading it:

```bash
nbshell plugin validate /path/to/plugin
nbshell plugin design-check /path/to/plugin --strict
nbshell plugin add /path/to/plugin
nbshell plugin enable io.github.alice.weather
```

Newly cloned third-party plugins remain disabled until the user explicitly
enables them. `plugin add` and `plugin update` repeat the strict design check;
they reject a manifest id already installed under another directory, and an
update may not change the installed plugin's id. Bundled catalog identity fields
are checked against these manifests in CI, with the manifest as the canonical
source.

## Manifest v2

`manifest.json` lives at the repository root:

```json
{
  "schemaVersion": 2,
  "id": "io.github.alice.weather",
  "name": "Weather",
  "version": "1.0.0",
  "author": "Alice",
  "license": "MIT",
  "repository": "https://github.com/alice/nbshell-weather",
  "description": "Weather in the bar and a detailed forecast panel.",
  "kinds": ["bar-widget", "panel"],
  "hosts": ["bar", "panel"],
  "entryPoints": {
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml"
  },
  "activation": "on-demand",
  "dependencies": {
    "commands": ["curl"],
    "packages": ["curl"]
  },
  "barWidget": {
    "defaultSection": "right",
    "allowMultiple": false
  }
}
```

Supported kinds are:

| Kind | Contract |
| --- | --- |
| `bar-widget` | A component hosted by the nbshell bar. |
| `panel` | A floating surface with `open(payloadJson)` and `close()`. |
| `overlay` | A full-screen surface with `open(payloadJson)` and `close()`. |
| `service` | A headless, long-lived component. |

`hosts` is optional forward-compatible placement metadata. Supported values
are `bar`, `panel`, `overlay`, `window`, and `service`; unknown values are
rejected during validation. A plugin can use it to declare every shell context
its design can adapt to without creating separate packages. The host exposes
the active value through an optional `host` property when the component
declares one. Entry-point `kinds` remain the executable contract.

An entry point must stay inside the plugin directory. Symlinks that escape the
plugin tree are rejected. `activation: "on-demand"` is recommended for panels
and overlays so closed UI consumes no resources.

The host injects the properties a matching entry point declares: `shell`,
`manifest`, `service`, `pluginRegistry`, and `barWidgetRegistry`. Do not mark
an optional injected property as `required`.

## Required safety rules

- Never commit credentials, tokens, private prompts, personal paths, or user
  data.
- Never install packages, run `sudo`, modify the boot process, or enable a
  system service automatically. Declare dependencies and let the user decide.
- Do not execute an install or removal hook when the repository is cloned.
- Pass external values as separate process arguments. Do not concatenate them
  into a shell command.
- Treat message text, filenames, network responses, and catalog fields as
  untrusted plain text.
- Do not fetch remote images or HTML without a visible privacy decision.
- Store secrets in the desktop Secret Service and normal state below the XDG
  config, state, or cache directories. Keep secrets out of shell config.
- A plugin must be safe to disable. Stop timers, sockets, and child processes
  when they are no longer needed.
- Do not replace the lock screen, privilege agent, update trust path, or other
  security boundary from a community plugin.

## UI and resource rules

- Read the repository-root `DESIGN.md`; it is the stable visual and interaction
  contract for core shell surfaces and plugins.
- Prefer the native `qs.Common` and `qs.Widgets` APIs. `qs.Commons` and `qs.Ui`
  are supported compatibility APIs for portable Omarchy-style controls.
- Use public Theme/Style tokens and the highest-level shared primitive that
  matches the task. Do not hard-code a private color, spacing, typography, or
  motion system, and do not rebuild standard controls from rectangles.
- Keep visible strings and public documentation in English.
- Pointer hover and keyboard cursor must show the same state. Support visible
  keyboard focus, accessible names, and Escape in panels and overlays.
- Use shared motion tokens, honor Reduced Motion, and keep Wayland surface
  geometry stable while animating content.
- Check visible UI in `nbshell ui-gallery` and against dark/light themes, a
  narrow geometry, long content, and relevant empty/loading/error states.
- Avoid continuously repainted Canvas animations and aggressive polling.
- A bar widget should be quiet while it has nothing useful to report.
- Do not create a second notification server, tray host, or other exclusive
  desktop service.

### Design check

`nbshell plugin design-check .` reports design-contract findings without
blocking development. Add `--strict` for CI and store candidates. It checks for
hard-coded colors, fixed font/radius/spacing metrics, hard-coded animation
durations, missing shared imports, and incomplete panel/overlay lifecycle or
Escape behavior.

Specialized visualizations may suppress one intentional literal on the same
line:

```qml
color: "#ff00ff" // nbshell-design: allow-hardcoded-color
duration: 175 // nbshell-design: allow-hardcoded-duration
radius: 7 // nbshell-design: allow-fixed-metric
```

Suppressions are narrow exceptions, not permission to create a second design
system inside a plugin.

## Testing

At minimum:

```bash
nbshell plugin validate .
nbshell plugin design-check . --strict
bash -n scripts/*.sh
python -m py_compile scripts/*.py
```

Keep parsing and decision logic in testable JavaScript or small helper
programs. Test malformed input as well as the happy path. A plugin intended for
the curated store must also pass `tests/plugin-validation.sh` in an nbshell
checkout.

## Publishing

A public plugin repository should contain:

- `manifest.json` using schema v2;
- a README with setup, dependencies, controls, and removal instructions;
- an OSI-approved license;
- a preview image when the plugin has a visible UI;
- no vendored credentials or machine-specific state.

Store inclusion is a compatibility review, not a security guarantee. Plugin
authors remain responsible for their code and releases.
