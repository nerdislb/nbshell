# Native Polkit authentication

`nbshell polkit keep` enables the themed native agent at login with no time limit.
`nbshell polkit restore` restores hyprpolkitagent and its login activation.
`nbshell polkit status` shows registration, active requests and login selection.
For a temporary evaluation, `nbshell polkit trial` still runs for 15 minutes.

Native authentication is opt-in: installing nbshell only deploys the units.
The selection is made explicitly with `keep`; the helper checks the tested
runtime before switching agents. No PAM, Polkit rules, kernel settings or system
Quickshell binary are changed. Fingerprint, password and phone authentication
continue to follow the existing system PAM configuration.

The native process imports only the authentication UI and shared theme/widgets;
it does not load shell plugins. Polkit's actual requests provide the action,
identity choices, prompts, response visibility, supplementary messages and result.
Responses go directly to `AuthFlow.submit`, with no CLI/IPC transport or logging.
The input is cleared on submission, prompt/identity/flow changes and completion.
A delayed focus update handles the transition from fingerprint waiting to password
entry after the field becomes enabled. Escape and Cancel cancel the actual request.

## Startup and recovery

The permanent `nbshell-polkit.service` conflicts with hyprpolkitagent so they
cannot register simultaneously. The supervisor validates the runtime digest at
every start and treats unexpected clean exits as failures too. There is no restart
loop. A separate `nbshell-polkit-fallback.service` starts the established agent
on failure, including a kill of the entire native service cgroup. Recovery only
runs while the graphical session is active; normal stop/logout does not resurrect
an agent. The native login preference remains enabled after fallback so a later
explicit `keep` or next login can retry it.

The temporary trial retains its bounded `ExecStopPost` recovery. A forced kill of
that entire trial cgroup can kill its recovery command too. In either mode,
`nbshell polkit restore` is the explicit manual return to the established agent.

## Tested runtime requirement

The official Quickshell 0.3.1 Polkit implementation can replace an active request
when a second arrives, leaving the first unanswered. A private-bus regression
reproduces this without real PAM calls. A QML-only workaround cannot safely repair
the backend ownership problem.

Native authentication therefore requires a separately built runtime in
`~/.local/lib/nbshell/polkit-runtime/quickshell`, with a SHA256-checked `build.json`
that records `queueRegressionPassed: true`. It is not downloaded or built during
normal nbshell installation. `resources/polkit/build-runtime.sh` builds the pinned
0.3.1 source with `polkit-queue.patch` and limited optional modules; it never
installs system files. The main desktop continues to use the packaged Quickshell.

The patch serializes active requests, clears a completed flow before advancing,
and drains unsupported identities without stranding later requests. The dedicated
binary is part of the authentication stack and must be maintained alongside future
Quickshell/Qt updates; a failed runtime starts the established fallback.

## Verification

- `tests/polkit.sh`: eight UI flow checks using the real components and a synthetic
  flow, including password masking, duplicate-submit protection, cancellation,
  clearing, multi-step/retry and delayed password focus.
- `tests/polkit-backend.sh /absolute/path/to/quickshell`: twelve synthetic requests
  on a private D-Bus, with mocked PAM-session calls; validates queued/active cancel,
  unsupported identities and recovery to idle. The stock binary fails as the
  negative control.
- `tests/test_polkit_lifecycle.py`: runtime integrity, unexpected exit, logout guard,
  pending-request protection, registration rollback and failed disable handling.
- `tests/qml.sh`: shared QML regression suite.
- Optional render probes: `POLKIT_PREVIEW=/tmp/polkit.png tests/polkit.sh`, with
  `POLKIT_PREVIEW_LIGHT=1 POLKIT_PREVIEW_WIDTH=360` for a narrow light preview.
- Live trial: registration, process-crash recovery, actual PAM prompts and explicit
  user authentication. A synthetic test does not establish real authentication.
