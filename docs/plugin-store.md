# nbshell plugin store

The nbshell store is a small, curated catalog for plugins known to use the
nbshell manifest and host APIs. It deliberately does not expose the Omarchy
marketplace: Omarchy plugins use a different schema, shell context, compositor,
and command interface.

The catalog is stored in `shell/Catalog/plugins.json` and versioned with the
shell. This makes a fresh installation useful without requiring a marketplace
account or trusting a mutable remote index.

## Catalog entries

Each entry contains:

```json
{
  "id": "io.github.alice.weather",
  "name": "Weather",
  "description": "Weather in the bar and a detailed forecast panel.",
  "author": "Alice",
  "license": "MIT",
  "category": "Information",
  "kinds": ["bar-widget", "panel"],
  "source": "community",
  "repository": "https://github.com/alice/nbshell-weather",
  "dependencies": {
    "commands": ["curl"],
    "packages": ["curl"]
  }
}
```

`source` is either `bundled` or `community`:

- Bundled plugins ship with nbshell. They may be enabled or disabled but are
  updated together with nbshell and cannot be removed from the manager.
- Community plugins are cloned from their public repository. Installation and
  execution are separate steps; a new checkout remains disabled for review.

## Review policy

A catalog submission must satisfy
[the plugin development rules](plugin-development.md) and provide a stable
public repository. Review checks:

- manifest validity and namespaced id;
- source, author, license, and dependency metadata;
- no automatic package installation, `sudo`, or install hook;
- no credentials or machine-specific data;
- commands use argument arrays for untrusted values;
- safe enable, disable, update, and removal behavior;
- reasonable idle resource use;
- current automated tests.

Review means the listed revision was compatible when checked. It does not turn
unsandboxed QML into sandboxed code and is not a security warranty.

## Updates and removal

Before an external update, nbshell fetches only Git metadata and displays the
incoming commits and file summary. The candidate tree is validated in a
temporary directory before a fast-forward update changes the installed
checkout.

Removing an external plugin also removes its runtime enable flag, bar
placement, and plugin settings. Bundled plugins are disabled instead of
deleted.

