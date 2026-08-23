# Agent Console

Agent Console is nbshell's drop-down control surface for persistent coding-agent
sessions. Press the layout-independent `Mod+F12` shortcut or run:

```bash
nbshell quake
```

Press the same key or `Esc` to hide the console. Hiding it never stops an agent.

The left column lists detected sessions and their lifecycle state. Select
one to inspect recent terminal output, send its next command with `Ctrl+Enter`,
or focus the full terminal. `+ NEW` starts Codex, Claude Code, or Antigravity in
a new nbshell session for the selected project and optionally submits the first
task.

Agent Console deliberately does not implement a terminal emulator or store chat
history. New sessions use an isolated `nbshell-agents` tmux server: tmux keeps
the PTYs alive while the dropdown and shell are closed, captures their rendered
terminal screen, and accepts literal prompts through a temporary tmux buffer.
nbshell owns session metadata, projects, commands, status inference, and the
themed workflow. Provider credentials and conversations stay outside the shell
configuration.

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
