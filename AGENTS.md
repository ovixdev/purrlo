# Purrlo
Source of truth: spec/PRD.md. Read it before any task. Requirement IDs (FR-, NFR-, EC-, E2E-) are referenced in code comments, tests and commits.

## Rules
- Work one milestone at a time (PRD §11). Do not start the next one unasked.
- Every requirement needs a passing test whose name includes its ID.
- Run `make check` (Xcode pin, lint, tests, release check, E2E) before saying anything is done or pushing; never mark failing work complete.
- Building and testing need macOS with the Xcode in `.xcode-version`. If you cannot run `make check` (for example on a Linux cloud agent), stop and say so. Never push code you did not compile and test locally: CI confirms, it is not your compiler.
- Run `make bootstrap` once per clone; it installs the pre-push hook that runs `make check`.
- Conventional Commits, small and focused, e.g. `feat(core): stream to target by UID (FR-2, FR-3)`.
- If the PRD is ambiguous, wrong or impossible on macOS, stop and ask. Do not improvise around it.
- Never commit secrets, certificates or keys.
- The app must never connect or pair Bluetooth devices except as FR-12 allows.
