# Hermes pilot boundary

This workspace is a deliberately restricted evaluation environment.

- Treat `~/Sync/brain` as read-only reference material when that directory
  exists.
- Do not create, edit, move, or delete files outside this workspace.
- Do not request or expose credentials, tokens, private keys, or `.env` files.
- The only approved delegation surface is the `nbshell-ai-broker` MCP server
  with its bounded advisory and transaction tools. `ask_codex`, `ask_claude`,
  and `ask_gemini` are text-only. `start_*_job` may implement a clearly scoped
  task only in the disposable Git clone created by nbshell; `review_agent_job`
  must use a provider other than the implementer. Never ask an agent to push,
  install, alter the source repository, access credentials, or change system
  configuration. Only the human-facing nbshell UI/CLI can apply, install, push,
  or reject a transaction. Send the minimum necessary context, never
  credentials, complete secret-bearing files, or the full Second Brain.
- For a substantial repository goal that has two or three genuinely
  independent work streams, prefer `start_supervised_team`. First decompose it
  into non-overlapping tasks, assign the best available provider to each, and
  provide only allowlisted test commands. The coordinator owns cross-review,
  bounded revisions, integration, and recovery. Use
  `supervised_team_status` to report progress. Never claim that the team result
  is installed or published while it is waiting for human approval.
- When confirmed work should become persistent knowledge, use
  `prepare_brain_proposal` with a complete Markdown note and an independent
  reviewer. You still cannot read or write the vault: only the named target is
  copied into an isolated proposal workspace. Use `brain_proposal_status`, and
  if review requests changes use `revise_brain_proposal`. Never target
  `00_Meta` or `05_Sources`, and never claim that a proposal was applied or
  pushed; those are human-only nbshell actions.
- Do not enable terminal, browser, messaging, gateway, cron, memory, plugins,
  additional MCP servers, general delegation, or additional skills without an
  explicit user decision and a separate security review.
- State clearly when a requested operation is unavailable in this pilot.

The purpose of the pilot is to evaluate conversation quality, context handling,
session continuity, and resource use before granting more capabilities.
