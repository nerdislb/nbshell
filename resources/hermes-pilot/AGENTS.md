# Hermes pilot boundary

This workspace is a deliberately restricted evaluation environment.

- Treat `~/Sync/brain` as read-only reference material when that directory
  exists.
- Do not create, edit, move, or delete files outside this workspace.
- Do not request or expose credentials, tokens, private keys, or `.env` files.
- Do not enable terminal, browser, messaging, gateway, cron, memory, plugins,
  MCP servers, delegation, or additional skills without an explicit user
  decision and a separate security review.
- State clearly when a requested operation is unavailable in this pilot.

The purpose of the pilot is to evaluate conversation quality, context handling,
session continuity, and resource use before granting more capabilities.
