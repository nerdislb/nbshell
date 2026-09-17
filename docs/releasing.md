# Releasing nbshell

nbshell uses Semantic Versioning. A beta tag communicates that the shell is
usable for daily testing while configuration and plugin contracts may still
change before version 1.0.

## Prepare a release

For the separately delivered Mail executable, follow the [backend maintenance and release policy](mail-backend-maintenance.md). A source dependency fix is not a fix to the user's downloaded binary.

1. Update `VERSION` and move the relevant entries from `Unreleased` in
   `CHANGELOG.md` to a dated version section.
2. Run the complete local gate:

   ```bash
   bash tests/release-gate.sh
   mkdocs build --strict
   git diff --check
   git diff --check "$(git describe --tags --abbrev=0)"..HEAD
   ```

   Before a release, also run a current Python advisory scan in an isolated
   environment:

   ```bash
   uvx pip-audit -r requirements-docs.txt
   uvx pip-audit -r plugins/ytmusic/backend/requirements.txt
   uvx pip-audit -r plugins/pit-wall/backend/requirements.txt
   ```

   The AT-SPI unit suite validates the probe's privacy, serialization, and
   targeting behavior. It does not assert a traversable live nbshell tree;
   the supported Arch Quickshell 0.3.1 package still exports only an empty
   application root. The lifecycle cause is fixed upstream after `v0.3.1`, as
   documented in the accessibility probe guide. An isolated build confirms the
   correction; a containing packaged release must still be re-tested when it
   reaches the supported baseline.

3. Install and test the candidate inside a real Umbriel session, including the
   independent agreety/TTY recovery path, using the [beta checklist](beta-testing.md).
4. Push the commit and wait for the validation workflow.
5. Create and push the matching annotated tag. Sign it when a configured GPG
   key is available; otherwise use the same annotated form as the existing
   beta releases:

   ```bash
   version="$(cat VERSION)"
   git tag -a "v${version}" -m "nbshell ${version}"
   git push origin "v${version}"
   ```

   With a configured signing key, replace `-a` with `-s`. The release workflow
   validates the tag against `VERSION`, but currently does not require a
   cryptographic signature.

The release workflow rejects tags that do not match `VERSION`. It creates a
GitHub prerelease for versions containing a hyphen and attaches the built
manual, a versioned installation archive, that archive's SHA-256 checksum, and
a keyless Sigstore bundle. The dashboard updater pins GitHub's OIDC issuer and
the release workflow identity at the exact tag, then verifies the checksum. It
refuses installation when any asset or verification step is missing. Do not tag
a commit until its live desktop test has passed.

## After publishing

- Verify the release archive, checksum, dashboard update check, and installation
  instructions from a clean user.
- Keep known limitations visible in the documentation.
- Triage regressions before adding large features to the beta branch.
