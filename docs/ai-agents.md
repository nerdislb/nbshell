# AI agents and local models


Press `Mod+Shift+A` to open the default agent immediately in a focused floating
terminal. It starts in `~/projects/nbshell` when that checkout exists, so the
installed nbshell skill can guide customization. The full Agent Center remains
available through `AI & Agents`, a right-click on AI usage,
`Mod+Ctrl+Shift+A`, or the CLI:

```bash
nbshell agent center
nbshell agent doctor
nbshell agent list
nbshell agent default codex
nbshell agent quick
nbshell agent launch --project ~/projects/my-project
nbshell agent install copilot
nbshell agent hermes-provider claude
nbshell agent hermes-mode research
nbshell agent hermes-broker setup
nbshell agent hermes-job list
nbshell commands --json
```

Clicking the AI bar module opens a provider-focused dashboard for Codex, Claude,
and configured Antigravity usage. It combines subscription windows and reset
times with local seven-day and per-model token summaries. The local scanner
reads token metadata from installed CLI session logs but never renders or
exports prompt content. Switch providers with the tabs, arrow keys, mouse wheel,
or middle click; right click launches the configured default agent.

The Agent Center discovers supported tools instead of requiring all of them.
It currently recognizes Codex, Claude Code, Antigravity, OpenCode, Gemini CLI,
GitHub Copilot, Pi, and optional Hermes. Hermes has a restricted pilot and
separately selected research, workspace, and trusted modes, described below.
`safe`, `balanced`, and `autonomous` approval profiles map to each tool's native controls. The explicitly selected `autonomous` profile uses
Codex's full approval-and-sandbox bypass; fresh installations therefore
continue to start in the safer `balanced` profile.

The Hermes Hub keeps provider choice separate from permissions. Codex and
Claude run as native Hermes providers using their provider-owned CLI credential
stores. Gemini is clearly marked as an external bridge and opens the existing
Antigravity CLI in its sandbox, because Hermes cannot reuse Antigravity's Google
login. `restricted` exposes workspace-file operations, `research` adds
read-only web tools, and `workspace` adds the terminal while retaining Hermes'
manual approval policy. The shipped and migration-safe default remains
`codex` plus `restricted`. Recent Hermes sessions are listed by opaque ID,
timestamp, and token count; prompt text and generated titles stay out of the
shell status path.

`trusted` is the explicit daily-development mode. Unlike the pilot modes, a
normal Hermes launch starts directly in the user's home directory, matching
the other agents. An explicit project launch starts in that directory instead.
It enables files, web, terminal, code execution,
task planning, clarification, delegation, session search, skills, and the
nbshell provider broker. Normal edits, builds, tests, and multi-agent work can
therefore happen against the real project. Trusted is explicitly autonomous:
native Hermes receives `--yolo`, while the external Gemini lane receives its
equivalent permission bypass. Commands therefore do not stop for approval.
The write-safe root is Home for a normal launch or the selected directory for
an explicit project launch, while terminal tools can use required build tooling
and caches. Restricted remains the shipped default;
Trusted must be deliberately selected by the user. In Agent
Center, right-clicking a project launches Hermes there; left click retains the
default-agent behavior. Android Studio projects are discovered automatically.

The optional Hermes broker has two deliberately separate surfaces. Its
`ask_codex`, `ask_claude`, and `ask_gemini` tools exchange bounded advisory text
only. Calls are serialized, rate-limited, time-limited, output-limited, and
logged without prompt or response content. Codex and Claude run through
tool-minimal nested Hermes queries; Gemini runs inside a bubblewrap filesystem
boundary with only its minimum CLI authentication state mounted.

Transactional tools can start Codex, Claude, or Gemini on an implementation in
a disposable local Git clone. They never receive the real repository's Git
metadata, SSH keys, or system write access. A different provider must review
the resulting normalized commit before it becomes eligible for application.
Hermes may start transactions only for repositories below `~/projects`, and no
more than three jobs can run concurrently. Each sandbox sees only the selected
provider's read-only authentication state; provider runtime homes are separate.
Hermes and its MCP tools cannot apply, install, push, or reject a transaction:
those operations exist only in the human-facing Agent Center and
`nbshell agent hermes-job`, require an explicit confirmation, fail closed when
the source branch moved or is dirty, and retain an action audit. The Agent
Center shows job state, diff, review verdict, and separately armed Apply,
Install, Push, and Reject controls. Enable the broker explicitly with
`nbshell agent hermes-broker setup` and restart Hermes.

For larger goals, Hermes can start a supervised team with up to three
non-overlapping tasks. Codex, Claude, and Gemini work in parallel transaction
clones; another provider reviews every result, and a rejected review triggers
at most two bounded revisions. Approved commits meet only in a disposable
integration clone, where allowlisted checks run without network, home-directory
access, or provider credentials. Integration conflicts are repaired there,
never in the source checkout. The Agent Center shows overall progress, elapsed
time, provider, attempt, and check state, and supports pause, reboot-safe
resume, cancel, and final approval. Even a completed team stops at
`AWAITING_APPROVAL`: Apply, Install, and Push are separate, double-confirmed
human actions. Only one team and at most three transaction workers run at once;
runtime and revision depth are bounded.

Confirmed knowledge can follow a separate reviewed Second Brain proposal path.
Hermes submits either an `append` section for an existing note or a complete
`create` note below `01_Projects`, `02_Knowledge`, `03_Daily`, or `04_Inbox`.
Neither Hermes nor the independent reviewer receives vault access: the review
workspace contains only the proposed Markdown. `00_Meta`, `05_Sources`,
non-Markdown files, replacements, traversal, symlinks, and credential-like
content are rejected. A review may request two bounded revisions. The Agent
Center then shows the target, verdict, and exact proposal diff. Apply verifies
that the target has not changed, commits only that note while preserving other
working-tree changes, and Push remains a separate double-confirmed human
action. The MCP tools can prepare, revise, and inspect proposals, but cannot
apply, commit, reject, or push them.

Model profiles route a default launch without changing individual agent
commands. `local` and `private` route through OpenCode, while `fast` and
`strong` default to Codex and Claude. Advanced users can set a concrete
OpenCode model in `~/.config/nbshell/agents.json`, for example:

```json
{
  "modelProfiles": {
    "local": { "agent": "opencode", "model": "ollama/qwen3.5:4b" }
  }
}
```

Ollama is optional and can be controlled after installation with
`nbshell agent ollama start|stop`. nbshell does not store provider credentials
or conversation history. The installer links one bundled nbshell system skill
into the standard Agent Skills locations used by Claude Code, Codex, and Pi,
plus the shared directory discovered by Gemini CLI and OpenCode. Check discovery with
`nbshell agent skills`; invoke it as `/nbshell` in Claude Code, `$nbshell` in
Codex, or through the respective agent's skills picker. Agents may also load it
automatically when a task matches its description.

To expose an Ollama model to OpenCode, add a local provider to
`~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": { "baseURL": "http://127.0.0.1:11434/v1" },
      "models": {
        "qwen3.5:4b": { "name": "Qwen 3.5 4B (local)" }
      }
    }
  }
}
```

Then run `ollama pull qwen3.5:4b` and verify the route with
`opencode models ollama`. Local models still need enough context for reliable
tool use; 16K to 32K is a practical starting range.

The `DEV`, `REVIEW`, and `PAIR` buttons in Agent Center create a new Herdr tab
for the selected project. From an existing Herdr pane, the same layouts are
available as `nbshell agent workspace dev|review|pair`. `DEV` creates an editor,
agent, and terminal layout. `REVIEW` adds a read-only review-agent pane. `PAIR`
adds a deliberately started second agent: the configured default remains the
lead and OpenCode uses the local route when available. The AI bar keeps a compact status icon; detailed sessions and subscription
limits belong in the Work Desk and provider views. Finished background agents and sessions
waiting for input create an actionable notification; its `Open session` action
focuses the matching Herdr pane. Codex uses its native lifecycle hook for
immediate completion and permission notifications, while other Herdr-supported
agents use the shared session watcher.

Missing agents show `INSTALL…` in the Agent Center. Selecting it opens a
terminal that displays the exact package command and asks for confirmation;
merely opening the panel never downloads or executes anything.

`nbshell commands --json` exposes the documented CLI as a versioned JSON
catalog so agents and scripts can discover supported commands without parsing
the shell source.


See [Work Desk](work-dashboard.md) for the optional desktop session overview.
