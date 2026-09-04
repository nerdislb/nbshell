# Umbriel capability contract

nbshell supports Umbriel through capability contract version 1. This contract
formalizes the narrow compositor surface that the shell already uses. It is not
a generic compositor abstraction and it does not make another compositor a
supported replacement for Umbriel.

The machine-readable source is
`shell/Catalog/umbriel-capabilities.json`. Its `referenceRevision` identifies the
Umbriel revision against which the contract is tested; it is not a complete
stack-support manifest.

## Discovery and status

Inspect the installed compositor without reading window titles, workspace names,
or user configuration:

```bash
nbshell compositor capabilities
nbshell compositor capabilities --json
nbshell compositor status --json
```

Discovery runs only `umbriel --help`, `umbriel msg --help`, and
`umbriel --version`. Runtime readiness is reported separately by opening and
closing the Umbriel socket without sending a request. It does not inspect
compositor state.

JSON output contains:

- `schemaVersion` for the status document;
- `contractVersion` and `backend` for contract identity;
- `referenceRevision` for the tested Umbriel contract revision;
- `status`: `ready`, `degraded`, `offline`, `incompatible`, or `unavailable`;
- `compatible`, which is true only for the tested revision with every required
  capability present;
- runtime binary, version, detected revision, reference-revision match, socket
  path, and socket availability;
- every capability with its kind, requirement level, availability, and
  explicit fallback;
- `missingRequired`, `missingOptional`, and structured `errors`.

`offline` means the executable satisfies the contract but no compositor socket
is available. `degraded` means the session is online and all required
capabilities exist, but at least one optional capability is absent.
`incompatible` means a required query, event, or action is missing, or the
executable is not the tested reference revision.

The status command reports current compatibility. It does not promise downgrade
compatibility and does not replace the future tested-stack manifest.
Umbriel does not expose the running server's revision, so the executable revision
and socket readiness are independent checks; `ready` cannot prove that an
already-running process came from that executable.

## Wire semantics

The pinned Umbriel protocol uses newline-delimited JSON over
`$XDG_RUNTIME_DIR/umbriel-$WAYLAND_DISPLAY.sock`; `UMBRIEL_SOCKET` overrides the
path. One-shot success replies use `{"ok": ...}` and failures use
`{"err": "..."}`. The Umbriel CLI's `--json` mode prints only the value inside
`ok`. Requests are limited to 65,536 bytes and one one-shot request is handled
per connection.

The `windows` query and event data are arrays of objects containing `id`,
`workspace`, `active`, `app_id`, `title`, `floating`, `focused`, `urgent`,
`xwayland`, `x`, `y`, `w`, and `h` fields. The `workspaces` query and event data
are arrays containing `id`, `name`, `index`, `output`, `active`, `focused`, and
`layout`. Subscription lines use `{"event": "<name>", "data": ...}`. Initial
snapshots are emitted in Umbriel's fixed event-table order, and
`keyboard_layout` can be absent until a keyboard exists. nbshell therefore
treats each event as a full replacement snapshot rather than a delta.

Umbriel does not expose a wire-protocol version or a machine-readable capability
command at the pinned revision. Contract discovery is consequently anchored to
the full revision and the CLI surfaces advertised by that build.

## Stable actions

The public action boundary accepts only names declared in the contract:

```bash
nbshell compositor action workspace.focus 2
nbshell compositor action workspace.layout.set dwindle
nbshell compositor action window.focus <window-id>
nbshell compositor action window.close <window-id>
```

Contract v1 defines these stable action names:

- `workspace.focus`
- `workspace.layout.set`
- `window.focus`
- `window.focus-warp`
- `window.close`
- `window.move-to-workspace`
- `window.floating.toggle`
- `window.width.set`
- `session.quit`
- `config.reload`
- `output.dpms.off`
- `output.dpms.on`

Arguments are validated before execution. Layouts are limited to `scrolling`,
`dwindle`, `master`, and `toggle`; window widths are fractions from 0.1 through
1.0. The implementation invokes Umbriel with an argument array and
never through a shell. Arbitrary commands and Umbriel's `spawn` action are not
part of the contract.

With `--json`, a successful action returns `ok`, `contractVersion`, the requested
and effective capability names, and whether a fallback was used. Failure
returns a non-zero exit status and an `error` object with stable `code`,
`message`, and, where applicable, `capability` fields. A failed action is never
reported as successful.

Stable error codes are `binary-not-found`, `probe-failed`, `probe-timeout`,
`missing-required-capability`, `unknown-action`, `unsupported-action`,
`invalid-argument`, `ipc-unavailable`, `action-failed`, `action-timeout`,
`revision-mismatch`, `contract-unreadable`, and `contract-invalid`. Umbriel's
diagnostic text may appear as `detail`, but consumers must branch on `code`
rather than matching that text.

## Queries, events, and fallback

The shell requires the `windows` and `workspaces` snapshot queries and matching
event families. It consumes Umbriel's event stream directly, replacing each
local snapshot with the newest event. It does not poll those families.

The `keyboard_layout` event is optional; its fallback is an empty layout label.
Output discovery is intentionally outside this contract because the pinned
Umbriel revision does not provide JSON output discovery; the display workflow
continues to own its existing `wlr-randr` integration. `window.focus-warp` may
fall back to `window.focus`. All other missing actions are unavailable rather
than silently translated to a different operation.

If the event socket disconnects, the QML service marks the compositor offline
and clears its cached window, workspace, focus, and keyboard-layout state. It
does not present stale compositor state as current. It retries the subscription
after a bounded delay so a compositor restart does not require restarting the
shell.

## Ownership and evolution

Umbriel owns the wire protocol, compositor state, and the actions themselves.
nbshell owns the stable names, validation, status envelope, fallback policy,
and mapping in `umbriel-capabilities.json`.

Contract versions increase only for an incompatible nbshell-facing change.
Adding an optional capability does not require a new version. Removing or
renaming a stable action, changing argument meaning, or changing a documented
status/error field requires a new contract version and parallel compatibility
handling. There is no automatic downgrade or translation to another
compositor.

`setup-umbriel.sh` checks the clean source revision, compares captured help bytes
with the newly built pinned binary, and runs the contract tests before
installation continues. Repository tests use captured help output and failure
fixtures so discovery, validation, mapping, and error behavior are repeatable
without a running compositor.
