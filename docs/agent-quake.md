# Agent Quake

Agent Quake is nbshell's drop-down control surface for persistent coding-agent
sessions. Press `Mod+^` — Mod plus the physical `^/°` key beside `1` on a
German keyboard — or run:

```bash
nbshell quake
```

Press the same key or `Esc` to hide the console. Hiding it never stops an agent.

The left column lists detected sessions and their live lifecycle state. Select
one to inspect recent terminal output, send its next command with `Ctrl+Enter`,
or focus the full terminal. `+ NEW` starts Codex, Claude Code, or Antigravity in
a new Herdr tab for the selected project and optionally submits the first task.

Agent Quake deliberately does not implement a terminal emulator or store chat
history. Herdr owns persistent terminals, resume state, and agent-aware prompt
delivery; nbshell owns the themed overview and command workflow. This avoids
simulated keystrokes and keeps provider credentials and conversations outside
the shell configuration.

The selected nbshell approval profile still applies to newly started agents.
Fresh installations use `balanced`; `autonomous` must remain an explicit user
choice. Existing sessions retain the mode with which they were started.

Requirements:

- Herdr running with a reachable local session;
- at least one supported agent CLI installed;
- the nbshell Niri bindings enabled through `nbshell switch on`.

Agent Quake is also searchable from the main menu. The existing Agent Center
remains the place for default-agent, model-route, approval-profile, optional
installation, Ollama, and workspace-template configuration.
