# Quality Code Review (2026-08-28)

**Audit Target:** `eaaf694` (clean HEAD)  
**Auditor:** Antigravity / Gemini Pair Programming Assistant  
**Date:** 2026-08-28  
**Scope:** Bounded CLI Help & Catalog Consistency, Documentation Alignment, Deterministic Interface Tests

---

## 1. Executive Summary

Following failures in two larger, unbounded agent jobs, this audit was conducted under strict scope constraints. The investigation focused exclusively on:
1. `bin/nbshell` user-facing help and machine-readable catalog (`commands --json`) consistency.
2. README and documentation CLI command consistency (including supported Hermes Hub modes).
3. Deterministic unit tests that validate those CLI interfaces and prevent regressions.

**Boundary Verification:**
No modifications were made to installer scripts, setup scripts, authentication broker, greeter frontend, lockscreen generation, IPC contracts, Bar/Widgets, QML services, integrations, plugins, security brokers, themes, or runtime behavior. No modifications were made to the Second Brain.

---

## 2. Findings & Identified Inconsistencies

### 2.1 Stale / Incomplete Hermes CLI Documentation
* **Omission of `trusted` Mode in CLI Help:**
  * In `shell/scripts/agents.py`, `HERMES_TOOLSETS` implements four modes: `restricted`, `research`, `workspace`, and `trusted`.
  * `README.md` explicitly documents `trusted` as the daily development mode with direct home directory access and full toolset capabilities.
  * In `bin/nbshell` (line 485), the help output was stale and only enumerated `[restricted|research|workspace]`.
* **Missing Hermes Team and Brain Proposal Commands in Help:**
  * `shell/scripts/agents.py` defines `hermes-team <list|pause|resume|cancel|apply|install|push|reject>` and `hermes-brain <list|apply|push|reject>`.
  * Both features are tested and documented in `README.md` and `docs/features.md`, but neither was listed in `bin/nbshell` user-facing help text.

### 2.2 CLI Help vs. Machine-Readable Catalog (`commands --json`) Desynchronization
* **Silent Dropping of Commands from `commands --json`:**
  * The `commands --json` extractor previously parsed `usage()` with a greedy single-line regex (`^  (nbshell\s+\S+(?:\s+\S+)*)\s{2,}(.+)$`).
  * As a result, over 40 valid commands were dropped from the JSON catalog when:
    * Commands had summaries wrapped onto continuation lines (e.g. `agent list`, `agent model`, `agent hermes-*`, `pip status|apply...`, `browser-theme`, `auth approve-next`).
    * Commands lacked a summary on the command line (e.g. `restart`, `edge top|bottom|toggle`, `theme remove`, `widget updates reset`, `audio status`, `notify clear`, `wallpaper list`, `status`, `switch status`, `cursor`).
    * Single spaces existed between command arguments and summaries (e.g. `open|close|toggle hold...`, `compositor status show...`, `habits inc <n> [x] increase...`, `set <key> <value> set a value...`).

### 2.3 Documentation Formatting Issues
* **Broken Inline Code Formatting:**
  * In `docs/getting-started.md` (lines 217–219), `` `nbshell switch\noff` `` was split across a newline inside backticks, causing broken formatting and command parsing.

---

## 3. Implemented Corrections

1. **`bin/nbshell` CLI Help (`usage()`):**
   * Corrected `nbshell agent hermes-mode` to `[restricted|research|workspace|trusted]`.
   * Added `nbshell agent hermes-team` and `nbshell agent hermes-brain` entries with descriptive summaries.
   * Provided clear, user-facing summaries for every command, ensuring proper alignment (2+ spaces).
   * Fixed single-space separators and added missing descriptions across lifecycle, bar, themes, widgets, audio, display, agent, gaming, grid, compositor, notes, habits, plugins, and system settings commands.

2. **`bin/nbshell` Machine-Readable Catalog (`commands --json`):**
   * Upgraded the embedded Python parser in `bin/nbshell` to support both single-line and continuation-line multiline summaries.
   * Ensured every documented CLI command is captured in `commands --json` without omission (expanding catalog coverage from 116 partial commands to 180 fully documented commands).
   * Preserved schema compatibility (`schemaVersion: 1`).

3. **Documentation Alignment:**
   * Corrected `docs/getting-started.md` to prevent line-broken inline code formatting.

4. **Deterministic Unit Testing (`tests/cli-consistency.py`):**
   * Implemented `tests/cli-consistency.py` to deterministically validate:
     * Exit codes for `nbshell --help`, `-h`, `help`, and no-arg invocation.
     * Version output format matching `VERSION`.
     * `commands --json` schema, command count, non-empty summaries, and special summary overrides.
     * Presence of all required subcommands (including Hermes modes, teams, brain, lifecycle, audio, agents, displays, etc.).
     * Consistency of all `nbshell` commands referenced across documentation markdown files.
   * Added `tests/cli-consistency.py` to `CONTRIBUTING.md`, `docs/releasing.md`, and `.github/workflows/validate.yml`.

---

## 4. Test & Verification Matrix

All tests were executed locally within the workspace:

| Test Suite | Command | Result |
| :--- | :--- | :--- |
| **CLI Help & Catalog Consistency** | `python3 tests/cli-consistency.py` | **PASSED** (180 commands verified) |
| **Shell Syntax Check** | `bash -n bin/nbshell bin/nbshell-install-recover` | **PASSED** |
| **Release Metadata & Privacy Audit** | `bash tests/release-audit.sh` | **PASSED** |
| **Hermes Hub Contracts** | `python3 tests/hermes-hub.py` | **PASSED** |
| **Hermes Broker Safety Contracts** | `python3 tests/hermes-broker.py` | **PASSED** |
| **Hermes Transaction Contracts** | `python3 tests/hermes-jobs.py` | **PASSED** |
| **Hermes Supervised Team Contracts** | `python3 tests/hermes-team.py` | **PASSED** |
| **Hermes Brain Proposal Contracts** | `python3 tests/hermes-brain.py` | **PASSED** |
| **Compositor Backend Contracts** | `python3 tests/compositor-backends.py` | **PASSED** |
| **Grid Layout Policy** | `python3 tests/grid-layout.py` | **PASSED** |
| **Lockscreen Generation** | `python3 tests/lockscreen.py` | **PASSED** |
| **System Report Contracts** | `bash tests/system-report.sh` | **PASSED** |
| **Browser Theme Contracts** | `bash tests/browser-theme.sh` | **PASSED** |
| **Plugin Validation** | `bash tests/plugin-validation.sh` | **PASSED** |

---

## 5. Conclusion

The code-quality audit is complete. All identified help inconsistencies, catalog omission bugs, and documentation formatting errors have been corrected and sealed with a deterministic test suite (`tests/cli-consistency.py`). All existing test suites continue to pass with zero regressions.
