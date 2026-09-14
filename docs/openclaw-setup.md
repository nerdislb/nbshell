# OpenClaw: install from nbshell

Choose **Menu > AI & Agents > Install / Open OpenClaw**, or run:

```bash
nbshell openclaw install
```

One click starts the setup. OpenClaw's own onboarding consent and ChatGPT/Codex
device-code sign-in still require user interaction in the terminal/browser.
This is not a silent, zero-prompt account installation.

## Fresh-machine defaults

- Official OpenClaw **2026.9.4**, under `~/.local/share/openclaw`, with the official
local installer's private Node runtime. No system Node replacement or shell-rc edits.
- Native OpenAI subscription OAuth, main model **openai/gpt-6-astra**, no model
  fallback routes. Account access is required; no API key or paid overage is enabled.
- Loopback-only Gateway at port 18789, fresh token authentication, Tailscale off.
- Default separate `~/.openclaw/workspace`, a systemd user Gateway service,
  health check, Apps shortcut and browser dashboard.
- The existing nbshell AI bar detects the local installation automatically.
- No import from Herdr, Hermes, Codex homes, other computers or Second Brain.
  Their configuration/authentication stays unchanged. The Brain is not copied
  or restructured. Existing subscriptions still share their provider quotas.

Prerequisites: a regular user on glibc Linux, working systemd user session,
`bash`, `curl`, `git`, `tar`, `xz`. Missing prerequisites are reported, not
installed through hidden privilege escalation. The official installer and
OpenClaw packages are downloaded only after the explicit menu/CLI action.

## Existing installations and retries

With an existing `~/.openclaw/openclaw.json`, the shortcut only validates the
configuration and opens the dashboard. It does not rerun onboarding, change
models, replace services or upgrade the installation. An existing Gateway unit
without config, leftover OpenClaw state/credentials without config, a busy port,
or custom OpenClaw path overrides stops fresh setup.
Concurrent nbshell setup attempts are serialized.

If onboarding fails after writing its config, a private pending marker makes the
next click report incomplete setup without overwriting that configuration. Finish with the installed CLI's
`openclaw configure`, then `openclaw gateway install` and `openclaw gateway health`.
The local-prefix CLI is at `~/.local/share/openclaw/bin/openclaw` if it is not on PATH.
After verifying recovery, remove only
`~/.local/state/nbshell/openclaw-setup/pending-setup` to re-enable the menu's open
path (or use `nbshell openclaw open` directly). Respect XDG state overrides.

The downloaded official installer is checked against the SHA-256 reviewed for
this checkpoint before execution. If upstream replaces that script, setup stops
and needs a reviewed nbshell update; it never executes a mismatching download.
Fresh setup uses the private CLI even when a different OpenClaw is on PATH.
Provider credentials, agent-home overrides and Node options are not inherited.
The installer uses an OpenClaw-private npm cache/config path, not another tool's npm setup.

Other commands:

```bash
nbshell openclaw open
nbshell openclaw status
```

`status` reports installation/config presence without reading credentials or
contacting model providers. Install/onboarding output is shown in the user's
terminal, not saved by this adapter; do not share login codes or dashboard tokens.

## Scope and acceptance

This provisions the same core local Gateway / subscription / Astra arrangement
as the reference computer. It does not copy conversations, personalized memory,
private skills, companion AppImages or the separate experimental dashboard theme.
Those are not part of this installer checkpoint.

The adapter is exercised with isolated command-contract tests; the running
reference Gateway must not be reinstalled for a test. Fresh-machine download,
interactive OAuth, service start and UI handoff require acceptance on a separate
machine. A passing mocked test is not a claim that these live steps completed.

Sources: [official local installer](https://docs.openclaw.ai/install/installer),
[onboarding](https://docs.openclaw.ai/start/wizard),
[OpenAI subscription setup](https://docs.openclaw.ai/providers/openai/setup).
