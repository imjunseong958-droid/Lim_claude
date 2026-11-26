## Rust

1. Run `cargo check -q` after each batch of changes and fix errors before going on.
2. While working, run only the relevant tests (`cargo test -q <filter>`). Leave the full suite to CI (Verification 2).
3. Run `cargo fmt` before committing. Fix clippy warnings your change introduced instead of adding `#[allow]`.
4. Put behavior tests in `tests/` against the public API or the built binary. Use `proptest` for property tests.
5. Make states that must never happen unrepresentable: enums for states and newtypes for validated values, instead of flags and runtime checks.
6. Do not add `#[ignore]` to get past a failing test.
