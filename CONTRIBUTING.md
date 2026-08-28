# Contributing to nbshell

Thank you for your interest. nbshell is still under active development. Small,
focused pull requests are the easiest to review.

## Before opening a pull request

1. For larger changes, describe the problem in an issue first.
2. Do not change a personal `config.json` or commit credentials.
3. Check shell scripts with `bash -n` and the niri file with `niri validate`.
4. Run the included tests:

   ```bash
   ./tests/plugin-validation.sh
   ./tests/fresh-install.sh
   ./tests/release-audit.sh
   python3 ./tests/grid-layout.py
   python3 ./tests/hermes-hub.py
   python3 ./tests/hermes-broker.py
   python3 ./tests/hermes-jobs.py
   python3 ./tests/hermes-team.py
   python3 ./tests/hermes-brain.py
   python3 ./tests/cli-consistency.py
   find shell -type f -name '*.py' -exec python3 -m py_compile {} +
   ```

5. Briefly explain what changes for users and how you tested it.

AI-assisted contributions are welcome. Please review generated code yourself
and mention substantial AI assistance in the pull request.
