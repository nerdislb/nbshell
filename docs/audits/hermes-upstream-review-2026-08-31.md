# Hermes upstream review — 2026-08-31

nbshell reviewed Hermes Agent commit
`936b970e281d5d28e930c5698f36bc4ebb54c7ba` as the next pilot runtime.
This is a reviewed pin, not evidence that the currently running Hermes process
has loaded it.

## Isolated verification

The target was checked out in the separate worktree
`~/.hermes/hermes-agent.next`; the active checkout and running TUI were not
replaced or restarted.

Verified against the target:

- locked `uv sync --extra all --locked` completed successfully;
- `hermes --version` reported Hermes Agent 0.20.6 and the expected revision;
- `hermes security audit --fail-on high` completed in a temporary private home;
- the audit reported no known vulnerabilities across 102 components;
- nbshell Hermes Hub, broker, transaction, supervised-team, Brain-proposal, and
  CLI contracts passed in the nbshell release matrix.

No provider credentials were copied into the temporary audit home and no
provider-backed advisory call was made as part of this verification.

## Activation boundary

The staged worktree may replace the active pilot only after the current Hermes
session has ended. Post-activation verification must read back the loaded
revision and rerun the nbshell Hermes contract tests. Upstream `main` changes
frequently; a later head is a new review candidate, not an automatic update.
