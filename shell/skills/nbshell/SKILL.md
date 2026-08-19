---
name: nbshell
description: Use when maintaining or customizing an nbshell desktop on Niri, including its bar, menus, themes, plugins, IPC, key bindings, and installation.
---

# nbshell system skill

nbshell is a Quickshell desktop shell for Niri on Arch Linux. It is not an
Omarchy or DankMaterialShell fork. Its public repository is normally checked
out under `~/projects/nbshell`; installed runtime files live under
`~/.config/quickshell/nbshell` and user state under `~/.config/nbshell`.

## Required workflow

1. Read the closest `AGENTS.md` and the user's Second Brain instructions.
2. Run `git status --short` before editing and preserve unrelated changes.
3. Edit the repository source, not the installed copy under
   `~/.config/quickshell/nbshell`.
4. Use `./install.sh` to deploy and validate source changes.
5. Keep public UI, CLI help, examples, and documentation in English.
6. Validate shell scripts with `bash -n`, Python with `python -m py_compile`,
   plugins with `tests/plugin-validation.sh`, and Niri with `niri validate`.
7. Never store API keys, stream keys, prompts, or credentials in Git.

## Stable interfaces

Prefer the public CLI over writing configuration directly:

```bash
nbshell --help
nbshell status
nbshell config
nbshell agent doctor
nbshell commands --json
nbshell plugins list
nbshell theme
```

Quickshell IPC is split by topic under `shell/Ipc/`. Volatile shared UI state
lives in `shell/Common/Runtime.qml`; persistent user configuration belongs in
`~/.config/nbshell/config.json` and is accessed through `Common/Config.qml`.

## Niri rules

Repository-owned bindings and window rules live in
`niri/nbshell-takeover.kdl`. `nbshell switch on` installs and includes the
runtime copy. Do not introduce Hyprland commands or assumptions. Niri's event
stream may stay open, but each command socket handles one request only; use
`niri msg action` for commands.

## Quickshell safety

- Do not anchor children managed by `Row` or `Column`.
- Avoid continuously repainted `Canvas` animations; they have caused memory
  growth. Prefer declarative items and GPU-composited properties.
- Keep only one bar popout open through `Runtime.activePopout`.
- Theme colors require contrast-aware `Theme.on`/`Theme.readable` handling.
- Third-party QML plugins execute unsandboxed. Review them before enabling.
- Never implement a custom lock or privilege agent casually; use established
  system components.

## AI integration

`nbshell agent` is the stable agent interface. Approval profiles are explicit:
`safe`, `balanced`, and `autonomous`. Do not silently change a user to
`autonomous`. Its Codex mapping intentionally uses the full bypass and is only
appropriate after an explicit user choice; never enable it as the shipped
default or add bypass/YOLO flags elsewhere. Local models are external services
such as Ollama; nbshell orchestrates them but does not embed an LLM or persist
conversations.

Missing agents may be installed only through the explicit `nbshell agent
install <id>` flow, which opens a terminal and asks for confirmation. Never
turn discovery or Agent Center refreshes into implicit package installation.
The `pair` workspace is an explicit two-agent layout, not an uncontrolled
swarm; agents still need separate responsibilities or worktrees for
overlapping edits.

## Recovery

If a source change breaks the shell, inspect logs with `nbshell log`, correct
the repository copy, and redeploy with `./install.sh`. Do not overwrite the
user's `~/.config/nbshell/config.json`; the installer intentionally preserves
it. Use Git to revert only changes owned by the current task.
