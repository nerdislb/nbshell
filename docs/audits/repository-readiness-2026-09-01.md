# Repository readiness audit — 2026-09-01

## Scope and evidence

Audit base: `198e8fd8c93aff4cc75636b47cb314e9149b978e` (`main`). The
review covered 756 tracked files: 295 QML, 92 shell, 68 Python, 64 JavaScript,
50 Markdown, 28 TOML, 25 JSON, and supporting assets/units.

A supervised multi-provider team (`20260901-152051-061bc1`) split security,
performance/maintainability, and installation/distribution work between Claude,
Codex, and Gemini with independent cross-provider review. The performance and
bootstrap lanes were approved. The security lane reached its automatic revision
limit after reviewers found additional archive-boundary cases; those findings
were reproduced and resolved centrally instead of treating the incomplete team
wrapper as approval.

The audit combined static searches, ShellCheck triage, tracked-history secret
patterns, Python advisory scans, live process measurements, short-lived child
sampling, focused security tests, the complete local release matrix, and an
installed optional-plugin environment audit.

## Fixed security findings

### High — unsandboxed plugin updates could merge silently

Git-managed third-party QML runs with the user's permissions. Previously,
`plugin update` fetched, validated the manifest, and fast-forwarded without
requiring the user to review the incoming code. Updates now show incoming
commits and file statistics and require a controlling-terminal confirmation or
an explicit `--yes`. A fixture proves that a noninteractive update leaves `HEAD`
and the checkout unchanged, while a deliberate `--yes` can merge the reviewed
commit.

### High — vulnerable MessagePack in optional Pit Wall live timing

A current `pip-audit` found `PYSEC-2026-3625` / CVE-2026-57585 in `msgpack
1.1.2`, hard-pinned by `signalrcore 1.0.2`. The live setup now selects
`msgpack >=1.2.1,<2`, installs the reviewed SignalR client without its stale
transitive pin, and runs the bridge self-test. The installed user environment
was upgraded from 1.1.2 to 1.2.2 and a direct audit reports no known
vulnerabilities.

### Medium — dynamic System Hub actions crossed a shell-string boundary

Arch News links and Herdr pane identifiers were interpolated into strings later
passed to `sh -c`. They now cross the QML boundary as argv arrays. Feed-provided
links are restricted to HTTPS on `archlinux.org` or its subdomains. Unit and QML
contract tests cover deceptive origins, userinfo, local files, HTTP, and shell
metacharacters.

### Medium — release updater archive resource limits were incomplete

The release updater already rejected traversal and links, but did not bound the
download, member count, individual members, expanded payload, or special entry
types. It now performs streaming header validation and extraction with limits of
50 MiB downloaded, 10,000 members, 25 MiB per file, and 100 MiB expanded data.
It requires exactly one installable source root. Tests cover traversal,
absolute paths, symlinks, hardlinks, FIFOs, oversized files, aggregate size,
member count, multiple roots, extra top-level files, valid extraction, and an
oversized mocked download.

### Medium — Shopping List exposed the draft during recipient lookup

The nbshell wrapper now receives the draft over stdin rather than `--message`,
keeping it out of the wrapper's process arguments during the potentially long
recipient lookup. `wacli` currently exposes only a `--message` interface, so the
shorter final send process still receives the message in argv; this remains an
explicit external limitation rather than a claimed complete fix.

## Code-quality fixes

- The documented `nbshell media` MPRIS branch was unreachable because the
  legacy music-window aliases captured `media` first. The alias no longer
  shadows the command, and a deterministic CLI contract prevents recurrence.
- Shopping, System Hub, plugin-update, bootstrap, and release-updater boundaries
  gained focused behavioral tests rather than relying only on source inspection.
- Greeter Python syntax validation uses `ast.parse` and no longer writes
  `__pycache__` into the reviewed tree.
- ShellCheck found the dead media branch and several existing informational
  warnings in literal test fixtures or established plugin scripts. The semantic
  branch bug and warnings in changed production scripts were fixed; intentional
  literal-fixture findings were not mass-rewritten.
- No tracked private key or credential pattern, world-writable file, or SUID
  payload was found.

## Performance results and fixes

Live baseline for the Quickshell main PID before deployment of these changes:

- RSS: 326,600 KiB; PSS: 222,589 KiB;
- private dirty memory: 148,960 KiB; swap: 0;
- 33 threads and 121 file descriptors;
- 30-second idle CPU sample: 0.20 CPU seconds, or 0.67% of one core;
- systemd restarts: 0.

The 1.6 GiB systemd cgroup value was not attributed to the shell: the shell
cgroup also contained the terminal, Hermes, broker, review workers, and isolated
agent sandboxes. Main-PID measurements were kept separate.

A ten-second direct-child sample found the active Hermes status helper five
times. Five benchmark runs averaged 0.327 CPU seconds each. At the previous
two-second active cadence that can average about 16.3% of one core while jobs or
teams are running. Active polling now uses five seconds, reducing structural
launch/CPU frequency by 60% (about 6.5% of one core at the measured helper cost),
while idle polling remains 30 seconds. Selected job/proposal detail helpers no
longer respawn after Agent Center closes.

The native lock clock now updates at 1 Hz when its smooth seconds ring is hidden,
instead of rebuilding time bindings at roughly 30 Hz. The smooth 33 ms cadence
is retained when the ring is enabled. Existing process, network, Pit Wall,
lazy-loader, motion, and memory guards remain green. No unbounded resident model
or cache was confirmed.

## Installation and distribution decision

The implemented public-beta path is a release bootstrap, not an ISO:

- `bootstrap.sh` selects beta/stable or an explicit version;
- it requires production asset URLs to use HTTPS;
- it downloads metadata, archive, and checksum with explicit size limits;
- it verifies SHA-256, rejects traversal, links, special files, oversized or
  multi-root archives, and cleans temporary state;
- it then starts the existing `setup.sh`, which installs Arch dependencies,
  builds and tests pinned Umbriel and its portal, deploys nbshell
  transactionally, installs the independent locker path, and applies the fresh
  greeter policy.

Seventeen deterministic bootstrap tests run locally and in CI. The bootstrap does
not require Python and never pipes network content into a shell.

An ISO was deliberately not implemented. At this stage it would turn nbshell
into a distribution with responsibility for firmware, kernels, boot modes,
partitioning, encryption, bootloaders, Secure Boot, destructive installation,
hardware matrices, image signing, recurring security rebuilds, and whole-system
support. Archiso remains a future option for a non-destructive demo/recovery
image after broader hardware testing. A split Arch package/repository is the
more appropriate later packaging step.

## Residual limitations

- Release archive and checksum are controlled by the same GitHub release. They
  detect corruption, not repository compromise. Independent signing or a
  verifiable build attestation remains future work.
- `wacli` still accepts the final message only through `--message`.
- Current Arch Quickshell 0.3.1 still lacks the upstream AT-SPI lifecycle fix;
  this is documented separately and was verified fixed in isolated upstream
  commit `916a0dd`.
- PipeWire can still emit upstream stale-node diagnostics. nbshell deduplicates
  visible output rows but does not hide the diagnostic source.
- ISO/live-media support is not part of the beta support promise.

## Verification

Passed locally:

- shell and Python syntax checks;
- release/privacy audit with 761 staged/tracked files;
- 17 bootstrap tests;
- fresh-install/update/rollback tests;
- plugin validation including update-consent and Pit Wall dependency contracts;
- 66 QML tests;
- motion, process identity, power, memory, performance, system report, browser,
  theme, Umbriel, updater, lock, phone-auth, Hermes, accessibility, greeter, and
  CLI suites;
- 91 bundled Mail QML tests plus its transport/provider/unit suites;
- strict MkDocs build;
- `pip-audit` for documentation, YouTube Music, Pit Wall requirements, and the
  installed Pit Wall environment: no known vulnerabilities after remediation;
- `git diff --check`.

Source changes were audited, tested, and installed on disk with source/runtime
hash equality for the changed shell and CLI payloads. The installer correctly
deferred the service restart because this audit runs inside `nbshell.service`;
loaded-live behavior still requires an external restart. Commit, push, release,
and publication remain separate user-authorized gates.
