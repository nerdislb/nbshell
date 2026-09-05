# Read-only doctor and shareable support report

```sh
nbshell doctor
nbshell doctor --json
nbshell doctor --json --check
# Explicitly save the shareable payload using your shell:
nbshell doctor --json > nbshell-support.json
```

Source-tree equivalent: `python3 shell/scripts/doctor.py [--json] [--check]`.
The command itself never writes reports or changes the session. It does not install,
restart, enable services, open capture dialogs, inspect journals, or read user
configuration or credentials. The output is suitable for sharing; review it before
posting as component versions and service availability still describe your setup.

## Machine-readable interface

`collect()` in `shell/scripts/doctor.py` returns a plain dictionary. The CLI emits
sorted, compact JSON with no timestamps. Identical observations yield identical
output. Schema version 1 contains:

- `reportType: "nbshell-support"`, `shareable: true`.
- `support`: an allowlisted projection of `stack-status.py --json`. States are
  `tested`, `supported`, `compatible-unverified`, `degraded`, `unsupported`, and
  `security-blocked`; unavailable or invalid evaluator output becomes `unknown`.
  Components are `nbshell`, `quickshell`, `qt`, `umbriel`, `portal`, and `platform`.
  Each contains `value`, `status`, `reason`, `available`, and `dirty`.
- `runtime.health`: core shell/compositor health, independent of stack support.
  Values are `healthy`, `unhealthy`, and `unknown`.
- `runtime.compositor`: required/optional capability counts and socket connectivity
  from `umbriel-contract.py status --json`. This checks the local executable's
  advertised capabilities and socket connectivity, **not the running compositor's
  build identity or successful execution of every capability**.
- `runtime.portal`: read-only D-Bus property readiness for Screenshot and ScreenCast,
  with activation disabled. `consentCaptureTested` is always false. A healthy result
  means the version and source-type properties respond, not that capture,
  source selection, permission persistence, or PipeWire streaming was exercised.
- `services`: fixed user-unit names with allowlisted `ActiveState` and probe result.
  Only `nbshell.service` affects core runtime health. Optional guards/audio units
  remain informative; missing optional tooling cannot itself fail core health.
- `remediation`: fixed English suggestions, never commands executed automatically.

Versions and support decisions come exclusively from the stack evaluator, never a
second doctor version detector. The shareable projection hides arbitrary version
suffixes/build metadata and unrecognized platform identities as `null`; this does
not change the evaluator's decision. Missing portal backend revision remains
unknown even when the portal responds. `supported` is not a complete `tested`
stack attestation; see [tested stack](tested-stack.md).

Probe states are `ok`, `failed`, `missing-tool`, `timeout`, `unavailable`, and
`invalid`. Raw stdout is parsed and projected, never embedded; stderr is discarded.
Every child has a timeout (3 seconds normally, 12 for the compositor adapter and
20 for the stack evaluator), a 64 KiB output cap, closed stdin, and an isolated
process group terminated on completion/timeout/overflow. No hostnames, private
paths, environment values, PIDs, window titles, or arbitrary diagnostic messages
are included. The inherited session environment is used only to reach the local
session; it is not reported.

## Exit status

Without `--check`, completed diagnosis exits **0** even when unhealthy; this makes
support collection usable offline. With `--check`, exit **0** requires supported
or tested stack status, healthy core runtime, and healthy portal property
readiness. Otherwise it exits **1**, including unknown/unverified support.
Argument errors exit **2**. `--check` is not a release certification gate or a
consent-capture test.

## Existing local system map

`shell/scripts/system-report.py` remains unchanged, including its schemaVersion 1
fields and Markdown/write behavior. That local map intentionally includes hostname,
paths, outputs, and configuration-derived information. **Do not treat it as the
shareable support payload.** Use doctor JSON for a public support report.

## Tests

```sh
python3 tests/doctor.py
```

Offline fixtures cover missing tools, malformed/foreign schemas, nonzero exits,
timeouts, redaction, optional-tool/core-health separation, capability failures,
D-Bus property validation, stack-state projection, deterministic JSON, and CLI exit
semantics. Tiny disposable Python children exercise actual output limits and
process/descendant timeouts without touching a live desktop.
