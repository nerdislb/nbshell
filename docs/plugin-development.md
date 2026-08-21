# Developing nbshell plugins

nbshell plugins are QML components loaded into the long-running shell process.
They can add a bar widget, a floating panel, an overlay, or a background
service without changing nbshell itself.

Creativity is welcome. The compatibility and safety rules below are not
optional: plugin code runs unsandboxed with everything the current user can
access.

## Start from the example

Copy `plugins/beispiel` into a separate repository and give it a globally
unique, namespaced id such as `io.github.alice.weather`.

Validate the directory before loading it:

```bash
nbshell plugin validate /path/to/plugin
nbshell plugin add /path/to/plugin
nbshell plugin enable io.github.alice.weather
```

Newly cloned third-party plugins remain disabled until the user explicitly
enables them.

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

- Use `qs.Common` and `qs.Widgets` components or the public nbshell
  theme tokens. Do not hard-code a private color palette.
- Keep visible strings and public documentation in English.
- Support keyboard focus and Escape in panels and overlays.
- Avoid continuously repainted Canvas animations and aggressive polling.
- A bar widget should be quiet while it has nothing useful to report.
- Do not create a second notification server, tray host, or other exclusive
  desktop service.

## Testing

At minimum:

```bash
nbshell plugin validate .
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
