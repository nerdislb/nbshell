# OpenClaw in the AI bar

The AI bar combines active OpenClaw runs and Herdr activity in one quiet icon:
green while agents work, red when any provider quota reaches 90%, otherwise
dimmed. Red takes precedence. There are no agent counts or session-status lists
in the bar or hover.

Hover shows provider quotas, percentages and reset times. Clicking always opens
the grouped **AI Limits & Quotas** dashboard, with collapsible provider cards
and separate **Limits** / **Token usage** tabs. Right-click still launches the
default agent; middle-click refreshes usage. The previous `aiBarMode` and
`aiPinnedLimits` settings are ignored by this widget.

The monitor shares the bar's three-second polling schedule. It is optional:
without `~/.openclaw/openclaw.json`, no Node process or Gateway request is made.
`OPENCLAW_STATE_DIR` can select another local state directory. Nothing starts
OpenClaw, changes its configuration, imports conversations, or sends messages.

## Supported connection

Validated with OpenClaw 2026.9.4 and Node 26. The adapter uses Gateway protocol v4,
requests only `operator.read`, and reads paginated `sessions.list` results.
`hasActiveRun` is the activity source; the persisted `status` can still say
`running` after a turn has finished and must not be used as a live indicator.

The endpoint is always `127.0.0.1` on the configured Gateway port. Supported
credentials are a local token/password string or the built-in default team
SecretRef store. The latter reads only the named, undeleted secret from
`state/openclaw.sqlite`, in read-only mode. Credentials remain in the short-lived
helper and never enter QML, command-line arguments, logs, or monitor output.

This adapter intentionally does not execute custom SecretRef providers. Remote
Gateways, TLS, JSON5-only configuration syntax, environment placeholders and
other secret stores are unsupported and produce an unavailable status. Requests
have a deadline; results exceeding 1,000 sessions or missing live-status fields
are rejected instead of presenting an incomplete idle result. A waiting turn
still counts as active when OpenClaw reports `hasActiveRun`; only Herdr currently
contributes to the separate input-waiting count.

Run the isolated tests with `python3 tests/test_openclaw_monitor.py`, and inspect
the metadata-only local snapshot with `python3 shell/scripts/openclaw-status.py`.

Protocol reference: <https://docs.openclaw.ai/gateway/protocol>.
