# Persistent state and Config Schema v1

This document inventories persistent paths written by nbshell and defines the
first versioned contract for the shell's own settings. The inventory groups
files that share one writer, format, and lifecycle; a glob is not a claim that
every file always exists.

Support levels mean:

- **Core** — created or consumed by the supported Umbriel shell baseline;
- **Optional** — created only when the matching feature or integration is used;
- **Experimental** — no stable migration guarantee yet.

Runtime files under `$XDG_RUNTIME_DIR` and temporary transaction directories are
excluded because they do not survive a login or completed operation. User files
that nbshell only reads, such as `commands.json` and `theme-hook.sh`, are called
out as ownership boundaries rather than nbshell state.

## Inventory

`~` below means the current user's home. XDG environment overrides apply.

| Path | Owner / writer | Readers | Format and validation | Write, backup, and migration | Support |
| --- | --- | --- | --- | --- | --- |
| `$XDG_CONFIG_HOME/nbshell/config.json` | `Config.qml`, config IPC, plugin enable/remove helpers and migration runner; installer creates it on first install and runs migration on updates | shell services, CLI and helpers | Flat JSON object; Config Schema v1 requires integer `schemaVersion: 1`; the runner validates syntax, root type and version | QML and helpers use same-directory replacement; migration writes are fsynced and atomic. Every mutating migration has an immutable backup and ledger entry. This is the only state in the v1 migration domain. | Core |
| `$XDG_STATE_HOME/nbshell/config-migrations.json` | `config-migrations.py` | migration CLI and shell startup | Ledger v1 JSON; validates domain, migration IDs, checksums and `pending`, `applied`, or `failed` status | Locked, fsynced atomic replacement. It is metadata, not part of Config Schema v1. Corruption is reported and never reset silently. | Core |
| `$XDG_STATE_HOME/nbshell/migration-backups/*.json` and `config-migration.lock` | migration runner | migration runner and operator recovery | Byte-for-byte pre-migration config copies; advisory lock file | Backup is written and fsynced before `pending`, then before config replacement. Backups are retained; no automatic rollback or pruning. | Core |
| `$XDG_CONFIG_HOME/nbshell/themes/<name>/` | installer and theme installer | theme index, shell and export helpers | Theme directory (`colors.toml`, optional backgrounds and metadata); theme installer validates required files and names | Theme install stages before replacement; no shared schema or migration ledger | Core |
| `$XDG_CONFIG_HOME/nbshell/plugins/<name>/` | installer and plugin CLI | plugin registry/host | Plugin source plus `manifest.json`; plugin validator and strict design check | Installs stage before rename; managed updates use installer rollback. Plugin code and plugin-owned data are not Config Schema v1. | Core for bundled plugins; Optional for third-party plugins |
| `$XDG_CONFIG_HOME/nbshell/{agents.json,displays.json}` | agent and display helpers | matching helpers and shell services | Separate JSON documents with feature-specific validation | Helper-specific atomic replacement; no shared version or migration ledger yet | Optional |
| `$XDG_CONFIG_HOME/nbshell/{palette.sh,cava.conf,generated/hyprlock.conf,generated/orbital-lock.json,omazen-colors.toml,whatsapp-provider}` | theme, audio, lock and integration helpers | external tools and matching shell features | Generated shell, Cava, JSON, TOML or single-line text; producer validates inputs where applicable | Re-generated from source state; most helpers use temporary-file replacement. Recover by regenerating, not by treating these as Config Schema v1. | Optional |
| `$XDG_STATE_HOME/nbshell/{notifications.json,notifications-seen,usage.json,clipboard.json,clipboard-images/,todo.json,notes.json,shopping-list-draft.txt}` | shell services | same service and its UI | Service-specific JSON, text, or image files; readers reject malformed structural data where implemented | QML `FileView` stores are atomic where declared; no common backup or schema. `todoFile` and `notesFile` may redirect to user-selected paths. | Core or Optional according to enabled service |
| `~/Sync/nbshell/habits.json` or configured `habitsFile` | habits service and conflict merger | habits service | Service-specific JSON with structural checks | Atomic QML write; sync conflict helper replaces only after successful merge. The user-selected location remains user-owned. | Optional |
| `$XDG_STATE_HOME/nbshell/{ton-geraet,zen-pip.json,update-reboot.json,system-report.md,ollama.pid,aether-apply.lock}` | audio, PiP, update, report, agent and Aether helpers | matching helper/UI | Feature-specific text or JSON | Mixed helper-specific atomicity; generally regenerable, with no common backup or migration contract | Optional |
| `$XDG_STATE_HOME/nbshell/{nearby.json,cert.pem,key.pem}` | LocalSend helper | nearby sender | JSON identity plus PEM certificate/private key; aliases and fingerprints are checked | Direct writes with no migration or backup; security-sensitive identity is a separate future domain and never part of Config v1 | Optional |
| `$XDG_CONFIG_HOME/nbshell/screensaver.txt` | screensaver helper on first use | screensaver renderer | User-editable UTF-8 text | Non-atomic initial creation; preserved thereafter; no schema migration | Optional |
| `$XDG_CACHE_HOME/nbshell/{checkupdates-db,umbriel-sources/}` | update helpers | update helpers | Package database and clean Git checkouts | Cache/reclone recovery; explicitly not configuration | Optional |
| `$XDG_CONFIG_HOME/umbriel/nbshell.toml` | installer | Umbriel | TOML binding/rule include; `umbriel validate` | Transactional installer backup/rollback | Core |
| `$XDG_CONFIG_HOME/umbriel/nbshell-{colors,motion,overview}.toml` | theme export service | Umbriel | Generated TOML; validated as part of Umbriel configuration | Re-generated on theme/settings change; current QML writer has no independent history | Core |
| `$XDG_CONFIG_HOME/umbriel/nbshell-cursor.toml` | cursor helper | Umbriel | Generated TOML from constrained theme/size inputs | Temporary-file replacement; regenerate from shell settings | Core |
| `$XDG_CONFIG_HOME/umbriel/nbshell-outputs.toml` and `$XDG_CONFIG_HOME/nbshell/displays.json` | display helper | Umbriel and display UI | TOML plus JSON snapshot; output names and values are validated | Transactional live apply restores prior live and saved values on rejection; separate from shell config migration | Core |
| `$XDG_CONFIG_HOME/ghostty/themes/nbcolors` | theme export service | Ghostty | Generated Ghostty palette | Atomic QML write; regenerated from active theme | Optional |
| `$XDG_CONFIG_HOME/{aether/custom/nbshell/,brave-flags.conf,zen/**/chrome/{userChrome.css,nbshell-theme.css},systemd/user/app.slice.d/90-nbshell-memory-guard.conf}` and `$CODEX_HOME/hooks.json` | explicit integration setup commands | Aether, Brave, Zen, systemd and Codex | External-tool formats with marker or feature-specific validation | Writers preserve unrelated content where marker based and generally use temporary replacement. These files remain owned by their external subsystem, not Config Schema v1. | Optional |
| `$XDG_DATA_HOME/nbshell/`, `$XDG_CONFIG_HOME/quickshell/nbshell/`, `$XDG_BIN_HOME/nbshell`, and nbshell user units | transactional installer | CLI, Quickshell and systemd | Installed, versioned runtime payload | Installer stages, records a transaction, swaps, and rolls back on failure. This is deployment state, not user configuration. | Core |
| `$XDG_STATE_HOME/nbshell/hermes-{jobs,teams,brain}/`, `hermes-broker.jsonl`, and corresponding `$XDG_DATA_HOME/nbshell/hermes-*/` workspaces | Hermes managers and broker | Agent Center and broker | Independent JSON records, append-only JSONL audit, logs and Git workspaces | Manager-specific locking/replacement; potentially sensitive operational history; never folded into shell config | Experimental |
| `$XDG_CONFIG_HOME/omamail/`, Omamail caches, calendar copies and drafts | bundled Omamail plugin | Omamail plugin | Plugin-specific JSON, cache and calendar formats with plugin-local validation | Plugin-local stores and legacy migration; independent ownership and recovery | Optional |
| `$XDG_DATA_HOME/nbshell/pit-wall/` and other plugin-declared data roots | individual plugin setup/backend | that plugin | Plugin-defined runtime/data | Plugin lifecycle only; no shell migration guarantee | Optional / Experimental |
| `~/Pictures/Screenshots/`, `~/Videos/` and configured capture destinations | explicit capture action and capture tools | user applications | PNG, video and related media | Direct user-requested output; tool-specific failure behavior. These are user documents, never migration input. | Optional |

The installer also stages greeter, locker, PAM and system service assets. Once
installed below `/usr/local` or `/etc`, those are root-owned deployment state
with their own transactional setup and recovery path. They are not user config.

## Ownership boundaries

The migration domain is named `nbshell-shell-config` and contains only
`config.json`. In particular:

- Umbriel owns compositor semantics. nbshell's `nbshell-*.toml` includes are
  validated and recovered as Umbriel configuration, not JSON shell settings.
- The plugin registry owns plugin discovery and manifests. A plugin's settings
  may currently occupy preserved keys inside `config.json`, but plugin files,
  caches, credentials and local migrations remain plugin-owned.
- `agents.json`, `displays.json`, notification history, task data, installer
  transactions and Hermes records are separate documents. Schema v1 does not
  claim or rewrite them.
- `commands.json` and `theme-hook.sh` are user-authored extension points. nbshell
  reads or executes them but must not migrate or replace them.
- Credentials and private provider configuration are never migration inputs,
  backups, status output or logs.

## Config Schema v1

The on-disk document is a UTF-8 JSON object. The one reserved schema member is:

```json
{
  "schemaVersion": 1
}
```

`schemaVersion` is required, must be an integer (a JSON boolean is not an
integer), and must equal `1`. All other existing members retain their current
key/value representation. Unknown members are valid and must survive migration
unchanged. This intentionally narrow contract versions the envelope before the
project freezes every individual setting: QML continues to provide defaults for
missing known settings and feature code remains responsible for validating its
own values.

Invalid JSON, a non-object root, a missing version after migration, a malformed
version, and a version newer than the running shell are errors. The runner and
QML reader report them. Neither replaces invalid data with defaults.

### Supported path

With no config and no migration history, the runner creates the minimal Schema
v1 object and records a fresh baseline without inventing a legacy backup.
The only mutating migration in this slice is
`0001-config-schema-v1`: an unversioned top-level JSON object becomes Schema v1
by adding `schemaVersion: 1`. Existing and unknown members are copied unchanged.
A Schema v1 document without a ledger is accepted as a current baseline and the
migration is recorded as applied without rewriting or backing up the config.

Migration IDs are zero-padded, monotone and immutable. Their implementation
semantic contract checksum is recorded in the ledger; an applied or pending ID
with another checksum is rejected. The existing v1 checksum is retained for
compatibility. It identifies the reviewed transformation contract, not a hash
of Python source; released transforms must remain immutable during code review.

### Runner ordering and status

`nbshell start` runs the installed migration runner before Quickshell. Operators
can use:

```sh
nbshell migrate status
nbshell migrate status --json
nbshell migrate apply --dry-run --json
nbshell migrate apply
```

A mutating run takes `$XDG_STATE_HOME/nbshell/config-migration.lock`, then:

1. parses and validates config and ledger;
2. writes and fsyncs an immutable backup;
3. atomically records `pending` in the ledger;
4. computes and validates the migrated document;
5. fsyncs a same-directory temporary file and atomically replaces config;
6. atomically records `applied`.

A controlled transformation failure records `failed`, leaves config unchanged,
and is not retried automatically. An interruption before replacement leaves
`pending`, the original and its backup intact; the next start resumes. An
interruption after replacement but before the final ledger write also leaves
`pending`; the next start compares the current document with the deterministic result
of its verified backup before completing the ledger without rewriting config. Concurrent runners serialize on the same lock.

QML and plugin helpers use the shared migration lock through `config-write.py`.
Startup and installer paths migrate before starting a new QML writer, duplicate
starts skip migration when live config IPC is available, and the migration CLI
still refuses a mutating apply while the main shell is live. `status` and
`--dry-run` are read-only. Their unlocked snapshots can show an intermediate
pending state during a concurrent write; they are not commit acknowledgements.

The runner uses an ordered registry of immutable transformations, with one
backup and durable pending/applied entry per step. A release must supply a
contiguous path to its supported schema. This release still ships only the
necessary v1 transformation; multi-step ordering and interruption are exercised
with isolated v2/v3 fixtures. Non-finite numbers are rejected as invalid JSON.

### Recovery and downgrade limits

If startup validation or migration fails, `nbshell start` opens a separate
recovery window. It loads no main-shell services or plugins. It preserves the
files and offers **Retry startup** after manual correction, or an explicit
candidate restoration. **Preview current file** lets you preserve a manually
corrected configuration while explicitly rebuilding a failed or corrupt history;
it goes through the same preview and confirmation as any other candidate.
A running shell retains its last readable settings,
rejects settings writes while config is invalid, and offers recovery in Settings.

```sh
nbshell config repair                  # open the recovery window
nbshell config repair inspect          # status, pending token and backup paths
nbshell config repair preview /absolute/path/to/saved-config.json
nbshell config repair apply TOKEN_FROM_PREVIEW
```

Preview validates the complete candidate, applies supported pure migrations to
its in-memory copy, and saves a private immutable repair record. It does not
replace config or history. Restoration replaces the entire configuration with
that reviewed candidate and rebuilds migration history as an explicit baseline.
Settings absent from the candidate are therefore lost from the active file;
review the selected saved copy before restoring it. There is no automatic reset
or guess at correcting malformed JSON.

The repair record at `$XDG_STATE_HOME/nbshell/config-repairs/<token>.json` retains
`beforeConfig` and `beforeLedger` as base64-encoded exact original bytes, or null
if absent. It also stores the reviewed candidate and resulting history. Records
are private (0600) and are not pruned. They can contain sensitive settings, so
keep them private. Migration backups remain separately available as JSON files.

Apply holds the shared lock and refuses changes made since preview. A durable
`repair-pending.json` journal protects the two replacements. If interrupted,
`inspect` returns the token: apply that same token again to resume. Both files
must match their recorded before or after bytes; unexpected edits stop recovery.
Migration and normal config writers refuse to run while a repair is pending.
The originals stay in the repair record even when the original ledger was corrupt.
As with other writers, editors that ignore the advisory lock can still race the
last check and replacement; stop editing during restoration.

A failed migration is not retried automatically, and malformed history is never
silently discarded. Restore a reviewed, supported candidate explicitly or inspect
the exact backup and ledger before further migration work. Downgrade is not
automatic: future schemas and unknown migration IDs stop normal startup.
Restoring shell configuration does not roll back Umbriel, plugins, tasks,
notifications, agents or installer state; use each subsystem's recovery path.
