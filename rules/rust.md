## Rust

1. Run `cargo check -q` after meaningful batches of changes and fix errors before continuing.
2. Run relevant tests with `cargo test -q`. Run the full suite when shared behavior or a broad area is affected.
3. Before committing, run `cargo fmt` and `cargo clippy --all-targets -q`. Fix warnings your change introduced instead of silencing them with `#[allow]`.
4. Put behavior tests in `tests/` against the public API or the built binary. Use `proptest` for property tests.
5. Do not add `#[ignore]` to get past a failing test.
