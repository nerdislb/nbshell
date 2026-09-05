# Release gate

Run the automated gate from a source checkout:

```sh
bash tests/release-gate.sh
```

Use `bash tests/release-gate.sh --check-tools` to check prerequisites without
running tests. Missing required Qt tools or Umbriel fail the gate rather than
silently omitting QML or compositor integration. The gate installs no packages,
publishes nothing, and does not restart the active compositor. Individual tests
exercise installers in temporary environments.

## Automated coverage

The entry point delegates to `tests/all.sh`, which is the single suite inventory:

- shell/Python syntax and CLI/documentation consistency;
- configuration migration fixtures;
- plugin validation, strict design checks and bundled plugin smoke tests;
- QML, accessibility, motion, adaptive geometry and drag lifecycle tests;
- installation, update preservation and transactional rollback fixtures;
- bootstrap, archive verification and package/image contract fixtures;
- Umbriel capability and integration contracts;
- performance smoke tests;
- release metadata, license and privacy checks;
- diagnostic, tested-stack and recovery contracts.

Passing these checks means the automated source gate passed, not that an ISO was
booted, a physical suspend/resume cycle was tested, or a release is publishable.

## Real Wayland drag regression

Offscreen QML cannot establish delivery of modifiers to an unfocused layer.
Run the real Wayland test separately using a built Umbriel pointer test client:

```sh
python3 tests/wayland-widget-drag.py \
  --compositor /path/to/umbriel \
  --pointer-client /path/to/pointer-client
```

This starts an isolated headless compositor and exercises the production drag
handler, ordinary clicks, unmodified/Shift drags, Super drag, and retained
keyboard focus and typing. It never replaces the desktop compositor. A passing
candidate binary does not prove that the active desktop has loaded it.

## Required live acceptance

Record the exact candidate revision, local modifications, installed payload and
running compositor identity. Inspect the actual desktop in dark/light themes,
Reduced Motion and representative display geometries. Verify keyboard focus,
Escape, clipping, long/empty/error states and real pointer interaction. Preserve
and read back user configuration after reversible drag tests. Inspect the
service journal for the tested invocation. Screenshots and OCR alone are not a
visual sign-off.

Before publication, rerun the gate on the final clean candidate, verify the
release artifact and obtain the required live acceptance. Untracked files are
not covered by every Git-based release audit. Commits, tags, pushes and release
publication require separate authorization. Runtime/config recovery is not
whole-system recovery; use the recovery matrix for the supported boundary.
