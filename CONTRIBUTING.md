# Contributing

Contributions are welcome through focused issues and pull requests.

## Development

Use Nim 2.0.0 or newer. Nimble is the package manager and task runner. From the
package root run:

```sh
nimble check
nimble compilePackage
nimble test
nimble examples
nimble docs
```

All generated compiler and documentation output must remain under `build/`.
Do not commit `nimble.paths`, `nimble.develop`, or `nimbledeps`.

Keep platform-specific terminal operations behind the internal Unix and
Windows backends. Public behavior must be tested through injectable I/O where
possible; use PTY or console integration tests only for behavior that requires
a real terminal. Any code that changes raw mode, cursor visibility, or screen
state must restore it on normal return, cancellation, end-of-input, and raised
exceptions.

Buffered input is probed in `src/terminal_screen/platform/buffered_input.nim`
before either backend waits on OS input. Keep CRT buffer access isolated there:
use system-header fields or CRT accessors, never hard-coded `FILE` offsets.
Only drain bytes already buffered; new OS reads must still stop at one byte.
Verify transitions between standard `File` reads and sessions using both files
and private pipes, including a pipe whose writer remains open.

New public APIs need documentation comments and tests. Changes to normalized
input events or session lifecycle behavior also need a changelog entry because
TerminalPrompt and future TerminalWidgets will depend on those contracts.

By contributing, you agree that your contribution is licensed under the MIT
license in `LICENSE`. Do not submit code whose license is unknown or
incompatible; record incorporated third-party material in
`THIRD_PARTY_NOTICES.md`.
