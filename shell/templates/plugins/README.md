# {{NAME}}

An nbshell plugin created with the canonical design-system scaffold.

## Develop

```sh
nbshell plugin validate .
nbshell plugin design-check . --strict
```

Visible plugins use `qs.Common` / `qs.Widgets` or the compatibility modules `qs.Commons` / `qs.Ui`. Keep colors, spacing, typography, motion, focus, and surfaces on shared semantic tokens.

## Install locally

```sh
nbshell plugin add .
nbshell plugin enable {{ID}}
```

Plugins run unsandboxed inside the long-running shell process. Review dependencies and commands before enabling them.
