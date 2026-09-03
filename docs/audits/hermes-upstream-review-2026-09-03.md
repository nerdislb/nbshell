# Hermes upstream review — 2026-09-03

nbshell reviewed Hermes Agent commit
`77adb80d52c70e7ff8186276d977c0fdca320311` as the next pilot runtime.
This advances the reviewed source marker; it does not replace or restart the
currently running Hermes process.

## Compatibility and security

The range from the previous reviewed commit
`936b970e281d5d28e930c5698f36bc4ebb54c7ba` includes Hermes Agent 0.21.0,
CLI and toolset routing changes, stricter unattended tool guardrails, opt-in
shared metrics, and the GitSpawn command-execution fix in
`f6234d00c5d59450adea1d7edd30ad3859375c79`.

nbshell's explicit `--tui`, `--in`, `--toolsets`, provider, model, and approval
arguments remain supported. The broker keeps its own stable MCP tool names, so
upstream deferred-core-tool aliases do not change the nbshell broker contract.
Shared-metrics sending remains opt-in and is not enabled by nbshell.

## Isolated verification

The target was checked out under `/tmp` and verified without replacing the
active checkout:

- `uv sync --extra all --locked` completed successfully;
- `hermes --version` reported Hermes Agent 0.21.0 and revision `77adb80d`;
- `hermes security audit --fail-on high` reported no known vulnerabilities
  across 102 components in a temporary private home;
- 84 focused upstream tests for CLI flag propagation, MCP startup, tool search,
  and tool guardrails passed;
- nbshell Hermes Hub, broker, transaction, supervised-team, and Brain-proposal
  contracts passed.

No provider credentials were copied into the temporary audit home and no
provider-backed request was required for these checks.

## Activation boundary

A later activation still requires ending the current Hermes session first.
After activation, read back the loaded revision and rerun the nbshell Hermes
contract tests. A later upstream head is a new review candidate rather than an
automatic update.
