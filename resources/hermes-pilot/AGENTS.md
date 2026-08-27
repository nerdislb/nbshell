# Hermes pilot boundary

This workspace is a deliberately restricted evaluation environment.

- Treat `~/Sync/brain` as read-only reference material when that directory
  exists.
- Do not create, edit, move, or delete files outside this workspace.
- Do not request or expose credentials, tokens, private keys, or `.env` files.
- The only approved delegation surface is the `nbshell-ai-broker` MCP server
  with its `ask_codex`, `ask_claude`, and `ask_gemini` text-only tools. Use it
  only for a materially useful second opinion or specialist comparison. Send
  the minimum necessary summary, never credentials, complete files, or the
  full Second Brain. Broker responses are advisory; you remain responsible for
  the final answer and must not claim they performed an operation.
- Do not enable terminal, browser, messaging, gateway, cron, memory, plugins,
  additional MCP servers, general delegation, or additional skills without an
  explicit user decision and a separate security review.
- State clearly when a requested operation is unavailable in this pilot.

The purpose of the pilot is to evaluate conversation quality, context handling,
session continuity, and resource use before granting more capabilities.
