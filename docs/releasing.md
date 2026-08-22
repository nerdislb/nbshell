# Releasing nbshell

nbshell uses Semantic Versioning. A beta tag communicates that the shell is
usable for daily testing while configuration and plugin contracts may still
change before version 1.0.

## Prepare a release

1. Update `VERSION` and move the relevant entries from `Unreleased` in
   `CHANGELOG.md` to a dated version section.
2. Run the complete local gate:

   ```bash
   ./tests/release-audit.sh
   ./tests/plugin-validation.sh
   ./tests/fresh-install.sh
   python3 ./tests/grid-layout.py
   python3 ./tests/lockscreen.py
   mkdocs build --strict
   ```

3. Install and test the candidate inside a real Niri session using the
   [beta checklist](beta-testing.md).
4. Push the commit and wait for the validation workflow.
5. Create and push the matching tag, for example:

   ```bash
   git tag -s v0.1.0-beta.1 -m "nbshell 0.1.0-beta.1"
   git push origin v0.1.0-beta.1
   ```

The release workflow rejects tags that do not match `VERSION`. It creates a
GitHub prerelease for versions containing a hyphen and attaches the built
manual as a ZIP archive. Do not tag a commit until its live desktop test has
passed.

## After publishing

- Verify the release archive and installation instructions from a clean user.
- Keep known limitations visible in the documentation.
- Triage regressions before adding large features to the beta branch.
