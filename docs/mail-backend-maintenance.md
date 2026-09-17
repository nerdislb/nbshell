# Mail backend maintenance

## What nbshell owns

nbshell maintains a **backend-only rebuild** of its bundled Omamail source. This is not an upstream Omamail release and does not include upstream's standalone desktop apps. Preserve upstream authorship and licenses. Do not describe the whole vendored plugin as a one-line fork: nbshell already carries integration and presentation changes, and its bundled source implements API 5 while the previous downloaded backend provided API 4.

The initial rebuild is `0.10.4-nbshell.1`. Its additional dependency fix updates Rustls from 0.23.44 to 0.23.45 for [RUSTSEC-2026-0285](https://rustsec.org/advisories/RUSTSEC-2026-0285.html). No new mail feature is added for this rebuild. The complete source commit, source-file fingerprints, compiler version, architecture and binary hashes travel with each release. A version label alone is not provenance.

The maintainer is the nbshell repository owner. An agent can inspect, prepare and test changes; successful tests are evidence, not permission to silently widen the fork, enable paid services or change accounts. Public replies to upstream maintainers require explicit authorization.

## Small, regular maintenance loop

| When | Work | Outcome |
|---|---|---|
| Weekly | Inspect upstream releases, RustSec/OSV advisories for the locked Cargo graph, and changes to the release toolchain/actions. | A dated assessment: no action, candidate update, or security work. |
| Before each nbshell beta | Refresh advisory checks; verify the exact backend pin and both delivered architectures; run compatibility and installation/rollback gates. | Explicit PASS, BLOCK or NOT VERIFIED for the affected security boundary. |
| On a relevant security advisory | Check affected versions, enabled features and actual call paths promptly; prepare the smallest effective fix. | Patch/release priority based on reachability and impact, not merely scanner severity. |
| On a regression | Preserve the last working release and user data; diagnose with synthetic fixtures. | A new immutable corrective version, never silently replaced assets. |
| Monthly or at an upstream replacement candidate | Review whether our rebuild is still necessary. | Keep a justified patch or retire the extra delivery path. |

This is a maintenance policy, not a claim that monitoring is already scheduled. No autonomous dependency merging or publishing is enabled by this document. If a scheduled check is later enabled, it should report findings and never install or publish by itself.

Budget: use the existing public repository and standard GitHub-hosted Linux runners only. No larger runners, paid fallback routes, extra storage purchases or automatic top-ups. Build artifacts have one-day retention and no Rust build cache is uploaded. Stop at existing limits. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## Release sequence

1. Start a clean `release/mail-X.Y.Z-nbshell.N` branch. Increment `N` for every new rebuild; never reuse a published version. Keep the Cargo package and lockfile versions identical. The UI manifest and standalone base metadata are independent; only the backend is built here.
2. Review the diff from the previous release. Record why each extra change is needed. Keep the dependency update narrow; do not update the entire Cargo graph merely to clear an unrelated warning.
3. Push the reviewed build change. `.github/workflows/mail-backend.yml` builds locked static musl executables on native x86_64 and ARM64 standard runners. It runs Rust tests, native agent tests and the actual backend API contract, checks ELF architecture/static linkage and private build paths, and records source fingerprints. Both architectures must agree on source/API inputs.
4. CI publishes a uniquely named `mail-backend-X.Y.Z-nbshell.N` prerelease in `nerdislb/nbshell`, not a shell release. It refuses an existing tag/release, compares the downloaded public bytes to the build outputs, and executes the public API contract natively on both architectures. Failure does not update the plugin pin.
5. Only after those jobs pass, update `backend-version`, fold the existing API step into `releasedApiVersion`, and write `backend-release.json` with both **downloaded and verified** archive hashes. The consumer uses a fixed nbshell release origin; metadata cannot supply another URL. The source-anchored archive hash must agree with the remote sidecar before any candidate executable runs. There is no upstream/PATH/latest fallback for an nbshell rebuild.
6. Test the real installer in an isolated profile, including corrupt delivery and preservation of the previous executable. Run the production Quickshell bridge against the downloaded binary. Existing legacy AI jobs must finish or be cancelled by their owner before an upgrade; retain `check-upgrade.py`. Source-build legacy adoption is not automatically evidence for binaries built elsewhere.
7. Run the full shell release gate, merge the reviewed branch, install the candidate and verify the live runtime without changing configuration or account data. Publish the nbshell beta using the normal signed shell-archive workflow. Its trusted plugin hash pins are part of that archive.

Backend binaries remain separate assets: the shell source archive is already close to the updater's 50 MiB limit. Never append executables to it without reviewing the real consumer limits.

## Recovery and retirement

- Failed download, checksum, version or archive validation must preserve the installed executable. Never remove mail accounts, drafts, caches or keyring entries as a recovery shortcut.
- Existing tags and assets remain available for older plugin revisions. A bad published candidate gets a new version; do not overwrite or delete it to disguise the failure. Do not move the shell pin to it.
- A rollback to an older backend is allowed only after checking API/data compatibility and security. The vulnerable pre-fix binary is not our recommended security rollback. Prefer a new corrective build when a rollback would reintroduce a known issue.
- Return to upstream only when its **actual published binaries**, not just its source lockfile, contain the required fix and satisfy the current plugin contract. Verify both architectures, the update transition, and the existing QML feature guards. Keep old nbshell artifacts for reproducibility after the return.
- Open findings remain explicit: the current Hickory record-encoding advisory has no established application-level reproducer in the reviewed resolver use; it is a maintenance item, not a clean raw scan. Periodic review must revisit that assessment if dependencies, features or callers change.

See the [review report](audits/code-review-2026-09-17.md) and [shell release process](releasing.md).
