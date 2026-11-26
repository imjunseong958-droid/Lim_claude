#!/bin/sh
# Copy this to <repo>/.claude/verify.sh, make it executable, and keep only the checks for that repo.
# The commit-gate hook runs it before `git commit`. Agents are told not to run it again themselves.
# Keep it fast: build, lint, and the tests that matter. Exit non-zero on failure.
# Commit changes to this file yourself. The hook blocks Claude from committing them.
set -e

# Rust
# cargo fmt --check
# cargo clippy --all-targets -q -- -D warnings   # drop -D warnings if the repo already has warnings
# cargo test -q

# Node
# npm run lint
# npm test --silent

# Python
# ruff check .
# python3 -m pytest -q

# Go
# go vet ./...
# go test ./...

# Delete the two lines below once you have enabled the checks above.
echo ".claude/verify.sh has no checks enabled yet. Edit it." >&2
exit 1
