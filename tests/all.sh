#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

run() {
    printf '\n==> %s\n' "$*"
    "$@"
}

printf '==> shell syntax\n'
while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(git ls-files --cached --others --exclude-standard -z -- '*.sh')
bash -n bin/nbshell bin/nbshell-install-recover

printf '\n==> Python syntax\n'
while IFS= read -r -d '' source; do
    python3 -m py_compile "$source"
done < <(git ls-files --cached --others --exclude-standard -z -- '*.py')

run bash tests/plugin-validation.sh
run bash tests/plugin-smoke.sh
run python3 tests/lockscreen.py
run python3 tests/theme-contrast.py
run python3 tests/shell-update.py
run bash tests/bootstrap.sh
run bash iso/packages/tests/test-manifest-consistency.sh
run bash iso/packages/tests/test-repo-pipeline.sh
run bash iso/profile/tests/test_scripts.sh
run python3 iso/profile/tests/test_installer.py
run python3 tests/umbriel-capability-contract.py
run python3 tests/umbriel-contracts.py
run python3 tests/umbriel-update.py
run python3 tests/config-migrations.py
run python3 tests/stack-status.py
run python3 tests/doctor.py
run python3 tests/install-tree-transaction.py
run python3 tests/recovery-contracts.py
run python3 tests/phone_auth.py
run python3 tests/ai-local-stats.py
run python3 tests/hermes-hub.py
run python3 tests/hermes-broker.py
run python3 tests/hermes-jobs.py
run python3 tests/hermes-team.py
run python3 tests/hermes-brain.py
run bash tests/performance-smoke.sh
run bash tests/process-selection.sh
run bash tests/qml.sh
run python3 tests/runtime-loader-contracts.py
run bash tests/screensaver-renderer.sh
run bash tests/power-modes.sh
run bash tests/motion.sh
run bash tests/memory-guard.sh
run bash tests/system-report.sh
run bash tests/browser-theme.sh
run bash tests/hermes-theme.sh
run python3 tests/hermarchy-theme.py
run python3 tests/cli-consistency.py
run python3 tests/accessibility/test_atspi_probe.py
run bash tests/calendar-backend.sh
run bash tests/release-audit.sh
run python3 tests/release-gate.py

if command -v umbriel >/dev/null 2>&1; then
    run bash tests/greeter.sh
else
    printf '\n==> greeter integration skipped (umbriel unavailable)\n'
fi

if [ "$(id -u)" -eq 0 ]; then
    test_user=nbshell-ci
    if ! id "$test_user" >/dev/null 2>&1; then
        useradd --create-home "$test_user"
    fi
    run runuser -u "$test_user" -- tests/fresh-install.sh
else
    run bash tests/fresh-install.sh
fi

printf '\nAll available nbshell tests passed.\n'
