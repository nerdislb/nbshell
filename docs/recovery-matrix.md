# Recovery matrix

nbshell protects **bounded deployment transactions**, not the whole computer.
A successful installation does not leave a selectable history of shell releases.
Configuration migration backups are a separate recovery mechanism, not system
snapshots. This document describes implemented behavior; the broader
[roadmap recovery model](roadmap.md#6-recovery-model) is not a support guarantee.

## Capabilities and boundaries

Paths below use the default XDG locations. Preserve the original user's `HOME`
and XDG overrides when inspecting or recovering a transaction; do not run the
user installer or migration commands as root.

| Domain | Actual entry point / evidence | What is protected | Failure and recovery boundary |
| --- | --- | --- | --- |
| Shell runtime and installer-owned payload | `./install.sh`; `bin/nbshell-install-recover`; transaction under `$XDG_CONFIG_HOME/.nbshell-install-rollback.v2.*` | Staged runtime, command, recorded integration files, managed plugins, themes and recorded user-unit states. Existing runtime names are exchanged with `mv --exchange -T`. | EXIT rollback and a separate user-systemd watchdog cover interrupted, uncommitted installs, including tested SIGKILL windows. Watchdog arming failure aborts before installed-state mutation. Failed recovery retains transaction backups. This requires intact metadata, working filesystem operations and, for unit restoration, a reachable user manager. No power-loss/fsync durability guarantee or general release downgrade command. |
| Shell configuration migration | `nbshell migrate status --json`; `nbshell migrate apply --dry-run --json`; `nbshell migrate apply` | Only `config.json`. Mutating legacy-to-v1 migration saves exact original bytes under `$XDG_STATE_HOME/nbshell/migration-backups/`, then records `pending`, atomically replaces config and records `applied`. | Invalid JSON/future schema/malformed ledger are errors, not resets. Backups survive a damaged new config, but are not automatically restored. Failed migrations block retry; pending migrations resume only when their consistency checks pass. Fresh/current baselines do not invent a backup. Not a backup of every settings edit. |
| Umbriel user configuration | `umbriel validate`; `umbriel msg config-reload`; installer path manifest | Installer records its changes to Umbriel includes and main config for that installer transaction. | Later theme/output/manual edits have their own behavior, not installer history. Config Schema v1 does not restore TOML. A runtime rollback does not downgrade the compositor binary. |
| Umbriel binary and portal deployment | `nbshell update umbriel`; `setup-umbriel.sh`; `shell/scripts/install-tree-transaction.py` | Both tested DESTDIR payloads are merged before the deployment helper overlays `/usr/local`; ordinary caught deployment failures attempt to restore replaced leaves and remove newly created ones. | Per-file replacement, **not an atomic whole-tree exchange**. No durable replay journal or SIGKILL/power-loss recovery protocol. Backups are deleted in `finally`, even if restoration itself fails: do not rely on them as retained recovery copies. Successful deployment deletes them too. No built-in previous-version selector. Running Umbriel is not restarted; validate the new build at next login. |
| Greeter / login fallback | `/etc/greetd/config.toml.nbshell-recovery`, when previously installed by `setup-greeter.sh` | An independent agreety configuration using a text login shell. | Not created by files-only install in `/etc`. Requires agreety, greetd, working PAM and TTY access; does not repair the bootloader or graphical compositor. Activating it is an explicit privileged operation. |
| External system snapshots | Operator checks for `snapper` or `timeshift` below | Only what the separately configured provider actually captured. | No integrated snapshot detection/status/restore contract is currently provided here. Executable presence does not prove configuration, usable snapshots, correct subvolume coverage or bootability. nbshell does not configure providers implicitly. |
| System packages, kernel, bootloader | Distribution/package-manager and boot-recovery tools | **Not protected by shell rollback.** | `./setup.sh` can install dependencies, but these are outside the files-only installer transaction. Package rollback and boot recovery require their own backups, compatible packages and recovery media. |
| User data, credentials and plugin-owned stores | User's own backup solution; [state inventory](persistent-state.md) | **nbshell does not back up user data.** | Tasks, notes, notification history, captures, credentials and plugin data are not Config Schema v1. Some installer paths are copied for a specific transaction; that is not ongoing data protection. |

## Diagnose from a TTY without Quickshell

Switch to a free TTY (normally `Ctrl+Alt+F2`) and log in as the affected user.
These commands do not require a running shell or Quickshell binary. The source
checkout is useful when the installed runtime or command is missing; adjust its
location if needed. Status can exit nonzero to report pending or invalid state.

<!-- recovery-contract: tty-diagnostics -->
```bash
cd ~/projects/nbshell
python3 shell/scripts/config-migrations.py status --json
python3 shell/scripts/config-migrations.py apply --dry-run --json
```
<!-- /recovery-contract -->

For the installed CLI, these equivalent read-only commands also work without
Quickshell (but require the installed migration runner):

<!-- recovery-contract: migration-cli -->
```bash
nbshell migrate status --json
nbshell migrate apply --dry-run --json
```
<!-- /recovery-contract -->

Inspect the service separately, where the user manager is available:

```bash
systemctl --user status nbshell.service
journalctl --user -u nbshell.service -b --no-pager
```

Never delete `.nbshell-install-rollback.*`, `.nbshell-rollback.*`, or migration
backups merely to silence an error. Preserve the error, metadata and backups
before repair. Logs and backups can contain private information; do not upload
them unredacted.

### Interrupted shell installation

Once Quickshell and installer prerequisites are available, rerun a **known-good,
reviewed checkout** with `./install.sh` from outside the shell service. It first
handles stale transactions under its install lock, then starts a new install.
Incomplete post-mutation metadata aborts recovery rather than guessing. A retry
hosted inside `nbshell.service` may queue recovery and exit nonzero; retry only
after that recovery has finished. Do not blindly pull a newer revision as a
substitute for choosing a known-good payload.

The low-level helper can restore files without Quickshell. Its positional API is:

```text
nbshell-install-recover RUNTIME ROLLBACK MODE TRANSACTION COMMAND STAGED
```

Use the transaction's own `recover` executable and exact `shell-path`,
`rollback-path`, `command-path`, and `staged-path` metadata, not reconstructed
names. This is a repair interface, **not** a public rollback subcommand.
Coordinate with the installer/watchdog using
`$XDG_STATE_HOME/nbshell/install.lock` (default
`~/.local/state/nbshell/install.lock`) before invoking it; never race an active
installation. Preserve transaction contents before manual intervention.

Modes are `restart`, `deferred`, `manual`, and `inactive`. `restart` manages the
shell service; `manual` invokes the recorded command with `start -d`; `inactive`
and `deferred` skip that explicit final shell launch. **Even inactive recovery
may start services while restoring recorded unit activity.** It is not a
promise of no process launches or recovery without systemd. Do not override a
recorded mode casually. If the user manager or dependencies cannot be restored,
keep the backups and resolve those prerequisites first.

A committed transaction is a cleanup boundary, not permission to roll back a
healthy completed installation. Non-deferred success removes rollback runtime
and transaction data. Deferred service-hosted success leaves cleanup to the
watchdog; it does not prove the new QML has actually run successfully. Restoring
a tree cannot repair a missing or incompatible Quickshell package.

### Configuration repair

Stop the shell, including manually launched instances, before any direct
migration or restore. Normal QML writes do not participate in the migration
lock. The public mutating CLI checks live config IPC, but IPC failure alone is
not proof that no writer remains.

Preserve both `config.json` and `config-migrations.json`. Select the exact
`backup` from the ledger/status, inspect its JSON and source checksum, and keep
it unchanged. When current config is malformed, `status --json` returns an error
instead of the migration list: inspect the saved ledger directly to locate the
backup. A manually restored legacy config plus an `applied` ledger is deliberately
rejected; restoring the JSON alone is not a complete migration-state repair.
Moving a ledger aside is an explicit operator decision after diagnosis, not a
routine reset. See [migration recovery ordering](persistent-state.md#recovery-and-downgrade-limits).

### Graphical login or lock failure

If the locker UI is missing, `systemctl --user restart nbshell-lock.service` can
restart authentication; it **cannot unlock** the session. If necessary use
`loginctl list-sessions`, identify the affected Wayland session, then explicitly
terminate that session as described in [troubleshooting](troubleshooting.md#recover-from-a-failed-screen-locker).
Termination closes its applications and can lose unsaved work.

If the graphical greeter cannot start and the independent fallback was already
installed, inspect it first, then explicitly activate it from the TTY:

```bash
sudo test -f /etc/greetd/config.toml.nbshell-recovery
sudo cp -a /etc/greetd/config.toml /etc/greetd/config.toml.before-recovery
sudo cp /etc/greetd/config.toml.nbshell-recovery /etc/greetd/config.toml
sudo systemctl restart greetd.service
```

Run the commands individually; stop if a prerequisite or copy fails. Do not
overwrite an existing `config.toml.before-recovery` backup—choose a new name.
Restarting greetd may terminate graphical sessions. The fallback provides a text
login, not a repaired Umbriel installation.

### External snapshot discovery (operator-only)

```bash
command -v snapper
command -v timeshift
```

These read-only presence checks do not create or configure snapshots. Consult
the provider's own documentation and inspect configured coverage before any
restore. No command here claims package, kernel, bootloader or user-data recovery.

## Verification and known gaps

Run offline coverage from the repository:

```bash
python3 tests/recovery-contracts.py
python3 tests/config-migrations.py
bash tests/fresh-install.sh
python3 tests/install-tree-transaction.py
python3 tests/umbriel-update.py
```

The new contracts execute the marked documentation commands with an isolated
HOME/XDG layout and a PATH without Quickshell. They exercise the actual recovery
helper on transaction fixtures, config corruption after migration, and overlay
rollback of new files and symlinks. System-service commands are test doubles;
no live desktop, package install, network request or root write is involved.
Existing fresh-install tests inject installer failures/SIGKILL and model service
health; they are not proof that arbitrary broken QML is detected. The installer
optionally runs `qmllint` on the entrypoint and checks service activity. A real
broken imported QML payload, deferred startup failure, and hardware/login
recovery still need independent integration verification.

Bounded follow-ups, not guarantees supplied by this document:

1. Retain Umbriel overlay backups when rollback fails; add a persisted manifest,
   locking and explicit interrupted-deployment recovery before claiming SIGKILL
   or power-loss coverage. Check consistency if checkout advancement fails after
   files were installed: that failure does not revert the deployment.
2. Cover the shell install's first-install config/ledger lifecycle together.
   The installer records newly created `config.json` for rollback, but the
   migration ledger is outside that path manifest. A reproduced late failed first
   install leaves an applied ledger without a config: migration status and direct
   apply reject that state. A full installer retry was verified to succeed by
   recreating the config before applying migrations; this is not evidence that
   the failed install restored the original migration-state absence.
3. Add a bounded runtime-readiness check for the new QML, including deferred
   installs, rather than equating an active service or optional lint with a
   healthy UI. Do not claim the roadmap's broken-QML criterion complete yet.
   SIGKILL assertions here come from offline service fixtures, not an actual
   killed desktop session. Runtime device/inode metadata distinguishes the old
   tree from the replacement; it does not authenticate or hash its contents.
4. Add a read-only recovery inventory with domain-specific availability and
   reasons; do not label all rows simply “protected” or advertise whole-system
   rollback. Snapshot integration should remain detection-only unless explicitly
   requested.

Implementation sources: [`install.sh`](../install.sh),
[`nbshell-install-recover`](../bin/nbshell-install-recover),
[`config-migrations.py`](../shell/scripts/config-migrations.py),
[`umbriel-update.py`](../shell/scripts/umbriel-update.py),
[`install-tree-transaction.py`](../shell/scripts/install-tree-transaction.py),
and [`setup-greeter.sh`](../setup-greeter.sh).
