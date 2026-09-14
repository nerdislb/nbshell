# Fork reviews in Updates

Open the bar updater and choose **Fork**. **Refresh** checks the upstream
repositories without installing, fetching into, or modifying a source checkout.
The existing three-day source-audit timer uses the same helper and saved results.
Refresh needs network access, but no model call, token, or paid service.

Select a source to see its reviewed upstream baseline, target revision, commit
titles and a link to the full comparison. Commit titles are not a compatibility
assessment: a local port may already contain a change. **BASE CURRENT** means
upstream matches the catalog baseline, not that the installed binary was audited.
Unreachable sources and failed comparisons are explicitly marked as failed.

- **Approve port** queues a reviewed integration of that exact baseline/target.
  It does not merge, build, install, restart or grant blanket update permission.
- **Defer** keeps the revision visible without counting it as pending attention.
- **Reset decision** withdraws the decision while this revision is available.
- A changed upstream revision, repository or baseline requires a new decision.
- Reference-only sources cannot be approved for installation.

The approved queue is available to a human or agent for a separate, staged port
with local patches preserved and appropriate tests/review. There is deliberately
no generic automatic executor for heterogeneous forks. OpenClaw can read the
same queue; it is not required to use this UI.

## Shared interface

```sh
nbshell upstream-audit --json          # Network refresh, saved atomically
nbshell upstream-audit --cached --json # Saved results, no network
nbshell upstream-audit --decision approved --source SOURCE_ID --token REVISION_TOKEN --json
```

Decisions accept `approved`, `deferred` or `pending`. The token comes from the
snapshot and binds source ID, upstream URL, baseline and target. A stale token
is rejected. Actions and concurrent refresh commits share a file lock; network
checks have a separate non-blocking lock. Network calls have bounded timeouts,
response sizes and four workers. The helper never reads provider credentials.

Catalog: `shell/Catalog/external-sources.json`. Optional `upstreamRepository`
and `upstreamBase` distinguish a fork origin from its true upstream baseline.
Flea uses the peeled v0.2.1 commit, not the annotated tag object. Video Trimmer
checks omacom-io/omacut while retaining its own fork identity in the catalog.

State: `$XDG_STATE_HOME/nbshell/fork-updates` (default `~/.local/state`). Snapshot,
decisions and notification fingerprints are private, atomically replaced JSON.
The UI watches changes; it does not poll the network in the background. Existing
source-audit desktop notifications are deduplicated by revision/error.

Verification: `python -m unittest discover -s tests -p test_fork_updates.py`,
`bash tests/qml.sh`, plus a running Quickshell check of both updater tabs.
