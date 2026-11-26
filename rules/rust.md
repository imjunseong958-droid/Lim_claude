## Rust

1. Run `cargo check -q` after meaningful batches of changes and fix errors before continuing.
2. While working, run only the relevant tests (`cargo test -q <filter>`). The commit gate runs the full suite on `git commit`.
3. Before committing, run `cargo fmt`, and `cargo clippy --all-targets -q` unless `.claude/verify.sh` already runs it. Fix warnings your change introduced instead of silencing them with `#[allow]`.
4. Put behavior tests in `tests/` against the public API or the built binary. Use `proptest` for property tests.
5. Do not add `#[ignore]` to get past a failing test.
