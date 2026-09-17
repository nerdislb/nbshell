# Shell code review — 2026-09-17

## Scope and assessment

Starting revision: `044ad04445a73c19d7277d8a759b86b56c812f83`, with a clean working
tree. This is a risk-based source and runtime review for the next beta, not a
line-by-line certification of every bundled application.

The core architecture is sound: persistent configuration is separate from
transient UI state; services own integration work; IPC is split by topic; large
windows have explicit lazy-loader ownership. Shared visual primitives and the
accepted Omarchy alignment remain unchanged, including the custom bar and extras.
The main maintenance weakness is integration verification: several tests still
asserted superseded source snippets or pins after a valid UI/upstream port.

Reviewed boundaries include project Git inspection, OpenClaw's bounded local
status projection, plugin staging/validation and rollback, configuration writes,
update artifact verification, lock readiness, and Hermes host/sandbox Git and
environment separation. Runtime inspection covers lazy surfaces, demand-driven
polling and native panel lifecycle. Existing behavioral suites exercise these
boundaries; their passing result is not a proof of all possible inputs.

## Confirmed findings and corrections

| Severity | Finding | Correction / evidence |
|---|---|---|
| P2 | The read-only Work Desk Git helper could execute a repository's clean/process filter while hashing a modified tracked file. Inherited `GIT_*` values could also redirect inspection. | A same-size file fixture executed a marker command before the fix and did not afterwards. Strip Git environment overrides, ignore global/system configuration, disable effective local/include filters, fsmonitor and hooks, and do not enter dirty submodule worktrees. |
| P2 | Git output was unbounded; a parent-only timeout did not establish descendant cleanup. | Cap each command at 1 MiB and two seconds, use owned process groups, and clean up on timeout, overflow and helper cancellation. Real descendant and queued-command tests pass. At most four inspections run concurrently over twelve paths. |
| P2 | The installer copied developer build output into the runtime and its rollback transaction. | Stage and validate a development-output-free plugin tree. Measured Mail source: 8,038,024,231 bytes; staged payload: 7,857,255 bytes. Source build output remains intact. Existing unmanaged plugins remain preserved. |
| P2 | Umbriel fixtures and stack metadata still described the previous binary, causing false incompatibility and six failed capability tests. | Recapture help from clean source/build `8268c605da26d92f2337d6c8381167357317a059`; verify identical build, installed and running executable hashes. All 25 capability and 23 stack-policy tests pass. |
| P2 | The complete gate omitted Work Desk Git tests and retained stale WhatsApp, headset, power-panel and wallpaper assertions. | Add the Git suite; derive the WhatsApp source pin from its catalog; test actual headset expression behavior; follow current component ownership and motion semantics. Do not restore retired UI to satisfy a text match. |
| P3 | Strict manual generation failed on the root design link; the release privacy audit confused prose/synthetic paths with private data and rejected a documented public TLS fixture. | Repair prose/link targets. Keep private-key detection active; exempt only the exact documented fixture path and SHA-256. Mutation and relocation must still fail the actual audit. |

Git summaries deliberately bypass content filters and ignore nested submodule
dirt. They are bounded dashboard diagnostics, not authoritative filter-aware
commit status; use normal project Git tools for that. This helper is not a
sandbox for concurrently hostile same-user repository administration. Third-party
QML plugins also remain explicitly unsandboxed.

## Performance observations

- Private Wayland lifecycle: 30 openings each of Settings and Modules, followed
  by 60 seconds settling. Mapping latency p95: 59.1 ms / 65.0 ms. This includes
  IPC/polling overhead and is **not** first-frame or physical display latency.
- The isolated software-rendered shell rose from 108.7 MiB PSS before use to
  132.7 MiB after the cycles; the last seven settling samples were 131.2–132.7 MiB.
  This short run does not establish absence of a long-term leak.
- Installed pre-deployment desktop, 60-second observation: 0.233% of one CPU
  core, 249.6–252.5 MiB PSS. Active modules and graphics stack differ from the
  private fixture; these are not comparable A/B benchmark numbers.
- Work Desk native checks pass in dark 1280×900 and light 420×600 with Reduced
  Motion: long/empty data, pointer and keyboard toggles, focus scrolling, Escape
  and shared polling demand. Screenshots were inspected.

## Dependency security and release boundary

The three required Python advisory scans (manual, YouTube Music, Pit Wall)
reported no known vulnerabilities. An additional exact-version OSV scan of all
296 Cargo registry packages found the following:

| Dependency | Advisory assessment |
|---|---|
| `quick-xml 0.38.4` | RUSTSEC-2026-0194 / 0195: the shipped direct caller uses plain `Reader`, not `NsReader`, and `attributes().with_checks(false)`. The specified affected paths are not used here. |
| `hickory-proto 0.25.2` | RUSTSEC-2026-0118 requires DNSSEC validation; the resolved feature graph does not enable DNSSEC. RUSTSEC-2026-0119 concerns encoding large record sets; the reviewed clients issue resolver queries, not an authoritative DNS service. No application-level reproducer was established; retain this upstream dependency-maintenance item rather than claiming a clean raw scan. |
| `rustls 0.23.44` | [RUSTSEC-2026-0285](https://rustsec.org/advisories/RUSTSEC-2026-0285.html) is relevant to the TLS client. The source lockfile is updated to fixed `0.23.45`. This does **not** update the separately downloaded pinned Mail binary. |

The Rustls advisory describes accepting handshake messages at an incorrect
encryption level, not an established network-attacker authentication bypass.
Nevertheless, the currently pinned upstream Mail 0.10.4 binary cannot be claimed
fixed by changing our source lockfile. Upstream 0.10.5 still locks Rustls 0.23.44.
This initial blocker is resolved by the separately published
[nbshell backend rebuild 0.10.4-nbshell.1](https://github.com/nerdislb/nbshell/releases/tag/mail-backend-0.10.4-nbshell.1).
Both static Linux architectures passed native Rust/agent/API checks, followed
by public-download API and real-installer verification. The shell now pins
those verified archive hashes and API 5, already implemented by the bundled
source. The actual downloaded x86_64 binary also passes the production
Quickshell process test and 22 synthetic native-agent checks locally. The
legacy-adoption case uses the supported historical runtime/bin layout; the
installed-plugin legacy-job guard is retained, not bypassed.

Security verdict: **PASS for the corrected Mail binary delivery boundary**
after the public-asset checks above; the Git and installer fixes have local
regression evidence. No claim of blanket shell or third-party security
certification is made. The independent-review and hardware/real-account limits
below still apply. The [maintenance plan](../mail-backend-maintenance.md)
records the remaining dependency follow-up and release/rollback rules.

Independent-provider review was attempted within existing subscriptions:
Claude Fable returned quota exhaustion; Claude Sonnet timed out; Gemini
3.8 Flash High returned a provider filter block; Gemini 3.1 Pro High returned
empty partial output on timeout. None counts as a completed independent review.
No paid fallback, extra credits or authentication changes were enabled.

## Verification limits and follow-up architecture

Keep one release-suite inventory in `tests/all.sh`, and favor behavioral tests
over literal source snippets where behavior can be exercised. Keep helper
resource bounds close to their implementation; avoid a large generic framework
or global UI rewrite without a demonstrated need.

The initial complete gate failed on the stale contracts described above.
After correction, the complete local gate and GitHub Validate passed on
1750e54; the backend-delivery follow-up repeats the affected tests and complete
CI before merging. Final shell-tag signature and archive checks remain a
separate step from the completed backend publication checks. No new two-hour soak,
physical suspend/display matrix, second-machine login/onboarding, real-account
Mail/Gaming acceptance or complete AT-SPI certification is claimed.
