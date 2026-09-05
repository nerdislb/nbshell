#!/usr/bin/env bash
# Automated checks do not replace live desktop acceptance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-}" in
    --help|-h)
        printf 'Usage: bash tests/release-gate.sh [--check-tools]\nRuns the automated gate; live Umbriel acceptance remains required.\n'
        exit 0 ;;
    --check-tools|'') ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    printf 'Too many arguments.\n' >&2
    exit 2
fi
missing=0
for tool in python3 git jq qs umbriel make node cc c++ pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required gate tool missing: %s\n' "$tool" >&2
        missing=1
    fi
done
for tool in "${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}" "${QMLLINT_BIN:-/usr/lib/qt6/bin/qmllint}" "${QMLFORMAT_BIN:-/usr/lib/qt6/bin/qmlformat}"; do
    if [[ ! -x $tool ]]; then
        printf 'Required Qt gate tool missing: %s\n' "$tool" >&2
        missing=1
    fi
done
(( missing == 0 )) || exit 1
printf 'Release gate tools: OK\n'
[[ ${1:-} != --check-tools ]] || exit 0
bash "$ROOT/tests/all.sh"
printf '\nAutomated release gate passed. Live Umbriel acceptance and clean-candidate verification remain required; no release was published.\n'
