# Tested stack manifest (schema v1)

`shell/Catalog/tested-stack.json` is the versioned support-policy input for
`shell/scripts/stack-status.py`. It travels with the shell Catalog and scripts,
not with user configuration. This component is read-only: it does not install,
restart, update, migrate, start a portal, or change support policy.

## Invocation and diagnostic integration

```sh
# Local payload/executable identification, not a running-session certification
python3 shell/scripts/stack-status.py --json

# Fully deterministic offline evaluation; no subprocess probes
python3 shell/scripts/stack-status.py --json \
  --observed tests/fixtures/stack/development-observed.json

# Focused offline tests
python3 tests/stack-status.py
```

For a diagnostic consumer with `shell/scripts` on its Python import path:

```python
from stack_status import DEFAULT_MANIFEST, evaluate, load_json, probe_stack
report = evaluate(load_json(DEFAULT_MANIFEST), probe_stack())
```

`evaluate(manifest, observed)` performs no I/O and mutates neither argument.
`load_json(path)` bounds input to 65,536 bytes and rejects duplicate object keys
and non-finite numbers. `validate_manifest()` rejects unsupported schemas and
malformed policies. Invalid direct API inputs raise `ValueError`.

The CLI accepts `--manifest FILE` for explicit policy evaluation. Neither
manifest nor observation files can define executable commands. Exit **0** means
that a valid report was produced, including `unsupported` or
`security-blocked`; consumers must inspect `status`. Exit **2** means invalid or
unreadable input, with `--json` producing a sanitized `stack-input-invalid`
error object. Argument-parser usage errors retain standard argparse behavior.
There are no timestamps, private paths, raw command output, stderr, environment
dumps, credentials, window titles, or workspace names in the result.

## Policy format and evidence

- `schemaVersion: 1` versions the policy structure. Unknown versions fail closed.
- `manifestVersion` is a positive integer; increment it for a support-policy
  change. It is independent of the JSON schema and nbshell release version.
- `nbshellVersion` mirrors repository `VERSION` (`0.1.0-beta.10` initially).
- `components` explicitly covers `nbshell`, `quickshell`, `qt`, `umbriel`,
  `portal`, and `platform`. Each has `kind`, `minimum`, `supported`,
  `incompatible`, `securityBlocked`, and explanatory `notes`.
- `minimum` is a strict SemVer lower bound, or **null** when not established.
  It is a rejection bound, **not** an open-ended supported range.
- `supported` is an exact allow-list. Unknown newer releases are not
  automatically supported. Build metadata is not stripped to gain support.
- `incompatible` and `securityBlocked` are exact deny-lists. For SemVer policies,
  build metadata does not evade a denied version; prereleases are distinct.
  An empty list means **no recorded entries**, not a vulnerability scan or a
  guarantee that all other versions work.
- `testedStacks` contains whole-stack exact pins and a nonempty `evidence`
  reference. All six component identities are mandatory. **The shipped list is
  empty:** the repository does not yet attest a complete release-tested stack.
- `releaseNotes` links relevant release and compatibility documentation.

Current evidence is deliberately narrow:

| Component | Recorded policy and source |
|---|---|
| nbshell | Exact payload version from `VERSION`; not proof of a clean checkout or release provenance |
| Quickshell | `0.3.1` supported by `docs/releasing.md`; no established minimum |
| Qt | No established minimum or supported range. `tests/accessibility/README.md` records `6.11.2` with Quickshell `0.3.1` for a scoped accessibility test, not release-stack certification |
| Umbriel | Reviewed full revision `e677dbbe2728ee65156bdbcc6775b0b36b388b64` from `setup-umbriel.sh` and the capability contract |
| Umbriel portal backend | Reviewed full revision `d996f0c2bd4e8c868c0a143f0c9ce060f3c47ed5` from `setup-umbriel.sh` |
| Platform | `linux:arch` support target from `docs/compatibility.md`; no hardware or rolling-distribution snapshot certification |

Quickshell's documented AT-SPI traversal limitation remains in
`docs/compatibility.md`. A supported component identity does not assert that
all features are functional. Functional diagnostics may report degradation
separately or supply `health: "degraded"` for the relevant component.

## Observation and result format

```json
{
  "schemaVersion": 1,
  "components": {
    "qt": {"value": "6.11.2", "available": true, "health": "unknown"},
    "umbriel": {"value": null, "available": true, "dirty": true},
    "portal": {"value": null, "available": null}
  }
}
```

Missing component entries mean unknown. `available` is boolean or null;
`dirty` is boolean (default false); `health` is `ok`, `unknown` (default), or
`degraded`. `value` is a strict three-part SemVer for version components, a
**full lowercase 40-character commit hash** for revisions, or `os:distribution`
for the platform. Prefixes, package-release suffixes, leading `v`, uppercase
hashes, and malformed identities are not silently normalized. Unresolved or
malformed values produce a null result identity and remain unverified. Other
unknown observation fields fail validation rather than silently ignoring a
misspelled check. A caller supplying observations is responsible for their
provenance; this is an evaluator, not cryptographic attestation.

Result schema v1 contains `manifestVersion`, `nbshellVersion`, `status`,
`testedStack` (matched zero-based manifest index or null), and all six
`components`. Each component has `value`, `available`, `dirty`, `health`,
`status`, and a stable `reason` code. Aggregate severity, from highest to lowest:

1. `security-blocked`: recorded security deny-list identity.
2. `unsupported`: known incompatibility, below the established minimum, or a
   known non-Linux platform.
3. `degraded`: component explicitly missing or a supplied functional check failed.
4. `compatible-unverified`: unknown/unresolved identity, development build, or
   identity outside the recorded baseline. **This means not disproven, not
   verified compatible.** Missing evidence does not assert a broken component.
5. `supported`: exact documented component baseline, with no detected failure.
6. `tested`: every identity matches one recorded complete tested stack, with no
   dirty build, missing component, failed check, or blocking policy.

A stack cannot become tested by mixing versions from different attestations.
Tested status records historical compatibility, not current session liveness;
`health: "unknown"` stays visible even for historically tested identities.

## Probe boundaries and unknowns

The live probe calls only `quickshell --version`,
`/usr/lib/qt6/bin/qtpaths --qt-version`, and `umbriel --version`, with argv
arrays, closed stdin, discarded stderr, a minimal environment, at most two
seconds and 4,096 bytes per process. Timeout and overflow kill the isolated
process group, including descendants holding the stdout pipe. The evaluator
never executes a command obtained from input JSON. Live probes still trust the
locally resolved executables; this is not an executable-integrity audit.

The probe reads only bounded payload `VERSION` and `/etc/os-release` identity
fields. It does not source OS metadata or inspect source checkout state. Qt
introspection uses the Arch baseline path; a missing `qtpaths` means Qt identity
is unknown, **not** that Qt is absent. The queried Qt installation is not proof
of the library loaded by an already-running Quickshell process.

The portal is explicitly unknown: the backend has no established safe revision
query. In particular, `xdg-desktop-portal 1.22.1` is the **broker package**, not
the Umbriel backend revision. The probe never starts a portal to discover its
version, follows a source checkout as installed evidence, or infers a revision
from a binary's filename. Diagnostics with stronger verified deployment
metadata can supply the backend's full revision through the observation API.

Likewise, a short Umbriel revision such as the locally observed
`9b6472f5e408` cannot establish a full revision or clean source provenance.
It remains `compatible-unverified`; a local uncommitted candidate must not be
published as a tested release. `--version` identifies an executable, not the
already-running compositor server. Use the separate Umbriel capability and
session checks to establish runtime readiness.

## Fixtures and release maintenance

`baseline-observed.json` is a **synthetic combination** of documented supported
pins and the scoped Qt observation; it is not a captured complete certified
stack. `development-observed.json` models the locally observed abbreviated
candidate identity with explicit dirty/unknown metadata; the dirty flag is a
scenario assumption, not inferred by `--version`. `unknown-observed.json`
exercises absent evidence. Unit tests add synthetic attestations and security
policies in memory only; these never enter the shipping manifest.

For release preparation, update `VERSION` and the manifest identity together,
review installer/contract pins, increment `manifestVersion` when policy changes,
and attach an actual release test record before adding a `testedStacks` entry.
That record should identify clean artifacts, full compositor/backend revisions,
Qt/Quickshell versions, platform/hardware scope, tests run, and known limitations.
Do not convert locally installed versions into minimums or supported ranges.
The focused tests detect drift against `VERSION`, `setup-umbriel.sh`, and the
Umbriel capability reference revision.
