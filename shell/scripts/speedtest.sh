#!/usr/bin/env bash
# Keep the existing JSON/CLI entry point; exec forwards dismissal to the
# cancellation-aware adapter rather than leaving a shell or timeout tree alive.
set -euo pipefail
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/speedtest.py"
