# Agent Console

Agent Console is nbshell's drop-down control surface for persistent coding-agent
sessions. Press the layout-independent `Mod+F1` shortcut or run:

```bash
nbshell quake
```

Press the same key or `Esc` to hide the console. Hiding it never stops an agent.

The left column lists detected sessions and their lifecycle state. Select
one to inspect recent terminal output, send its next command with `Ctrl+Enter`,
or focus the full terminal. `+ NEW` starts Codex, Claude Code, or Antigravity in
a new nbshell session for the selected project and optionally submits the first
task.

Output deliberately uses one simple path. Selecting a session or opening the
console reads an immediate plain-text `capture-pane` snapshot; while visible,
the selected pane is refreshed every 2.5 seconds. Closing the console stops the
timer. There is no persistent control-mode client, ANSI terminal renderer, or
second writer competing for the displayed output. Use `FOCUS` whenever the
full interactive and colored terminal interface is needed.

Agent Console deliberately does not implement a terminal emulator or store chat
history. New sessions use an isolated `nbshell-agents` tmux server: tmux keeps
the PTYs alive while the dropdown and shell are closed, captures their rendered
terminal screen, and accepts literal prompts through a temporary tmux buffer.
nbshell owns session metadata, projects, commands, status inference, and the
themed workflow. Provider credentials and conversations stay outside the shell
configuration.

The tmux server is owned by a separate on-demand
`nbshell-agent-host.service`, not by the visual shell service. Agent processes
therefore keep running while nbshell is installed, restarted, or temporarily
stopped. The host ends with the graphical user session or through an explicit
stop; it is never restarted merely to refresh the UI.

When an agent finishes, the AI symbol in the bar pulses softly in cyan. If an
agent needs a decision or permission, it pulses in yellow instead. Native Codex
hooks forward both events directly to the shell, while shared session polling
covers the waiting states reported by other backends. Opening Agent Console,
including by clicking the pulsing symbol, acknowledges the event.

Existing Herdr sessions are listed with a `herdr` backend badge and continue to
use Herdr until they are finished. New sessions use the `nbshell` backend as
soon as tmux is installed. They can be opened in a full terminal through
`FOCUS`, but normal work no longer requires the Herdr interface.

If the isolated tmux server is stopped or the computer restarts, its metadata
remains visible as `STOPPED`. Select `RESTORE` to continue the most recent
conversation for that agent and project through the provider's native resume
command. This is deliberately visible rather than silently starting paid or
autonomous agents during login.

The selected nbshell approval profile still applies to newly started agents.
Fresh installations use `balanced`; `autonomous` must remain an explicit user
choice. Existing sessions retain the mode with which they were started.

Requirements:

- tmux, installed automatically by the standard nbshell setup;
- at least one supported agent CLI installed;
- the nbshell Niri bindings enabled through `nbshell switch on`.

Agent Console is also searchable from the main menu. The existing Agent Center
remains the place for default-agent, model-route, approval-profile, optional
installation, Ollama, and workspace-template configuration.
