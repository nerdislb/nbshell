# Contributing to nbshell

Thank you for your interest. nbshell is still under active development. Small,
focused pull requests are the easiest to review.

## Before opening a pull request

1. For larger changes, describe the problem in an issue first.
2. Do not change a personal `config.json` or commit credentials.
3. Check shell scripts with `bash -n` and Umbriel configuration with
   `umbriel validate`.
4. Run focused tests for the changed area. At minimum, keep the shared gates
   green:

   ```bash
   ./tests/plugin-validation.sh
   ./tests/bootstrap.sh
   ./tests/qml.sh
   ./tests/motion.sh
   ./tests/performance-smoke.sh
   ./tests/release-audit.sh
   find shell -type f -name '*.py' -exec python3 -m py_compile {} +
   ```

   Release candidates use the complete matrix in
   [docs/releasing.md](docs/releasing.md), including fresh-install, compositor,
   accessibility, Umbriel, Hermes, and documentation checks.

5. Briefly explain what changes for users and how you tested it.

AI-assisted contributions are welcome. Please review generated code yourself
and mention substantial AI assistance in the pull request.
