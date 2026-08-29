# Security Code Review (2026-08-28)

## Scope and transaction base

This patch was reviewed against clean `main` at `5a944dd`. The bounded scope is
the installer runtime swap, its independent recovery helper, and the lock-before-
suspend guard. No installation, service restart, publication, or Second Brain
operation was performed while producing this review.

The installer transaction is based in `$CONFIG_HOME/quickshell`, so its live,
staged, and rollback directories are on one filesystem. It atomically reserves
both unique transaction names with `mktemp -d`, then registers `EXIT` cleanup
before copying, validating, or arming recovery. Runtime switches use `mv -T`.
An old runtime becomes a completed backup only when the reserved rollback path
contains its validated `shell.qml`; an empty reservation is never recoverable.

On pre-swap failure both reservations are removed. After the first rename,
cleanup restores a genuine backup even when failure is injected immediately
after `mv` returns. A fresh install removes its unused rollback reservation.
Successful replacement removes the old backup after the new runtime is ready,
except for the deliberately deferred service-restart recovery window. Recovery
rejects and removes empty reservations, validates `shell.qml`, and restores the
directory directly at `nbshell` without creating a nested path.

The non-native fallback locker is polled for the complete 1.5-second guard
interval. Any delayed exit during that interval prevents suspend.

## Deterministic coverage

`tests/fresh-install.sh` covers fresh-install reservation cleanup, pre-swap
failure cleanup, failure immediately after the first rename, a genuinely
occupied destination containing `shell.qml`, rejection/removal of an empty
reservation, flat recovery without nested `nbshell`, and absence of unexpected
transaction reservations in its isolated XDG state. `tests/lockscreen.py`
covers a delayed fallback-locker crash before the 1.5-second deadline.

## Verification run

- `bash -n install.sh bin/nbshell-install-recover`
- `shellcheck install.sh bin/nbshell-install-recover` when available
- `bash tests/fresh-install.sh`
- `python3 tests/lockscreen.py`
