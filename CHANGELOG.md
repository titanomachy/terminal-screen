# Changelog

This project follows Semantic Versioning.

## [v0.1.1] - 2026-09-02

### Fixed

- Preserve printable AltGr input and every event represented by a Windows
  Console key-repeat count.
- Enable processed output together with Windows virtual-terminal processing,
  while continuing to restore the exact inherited console mode on close.
- Make POSIX raw input ignore inherited character-translation and newline-echo
  flags without changing output post-processing, then restore the exact
  inherited termios state on close.

## [v0.1.0] - 2026-09-01

### Fixed

- Prevent `readEvent` from reading bytes beyond its returned event and losing
  them when a session closes, including redirected input and multi-event paste
  across sessions that borrow the same `File`.

### Added

- Add guarded, process-wide terminal sessions with transactional setup,
  idempotent cleanup, raw mode, cursor restoration, and explicit degraded
  behavior for redirected streams.
- Add normalized UTF-8, control-key, CSI, SS3, modifier, timeout, resize, and
  end-of-input events through live sessions and an injectable incremental
  decoder.
- Add terminal/console detection, capability reporting, and viewport geometry
  for POSIX and Windows.
- Add pure ANSI cursor command builders plus explicit stream-writing helpers for
  absolute and relative movement and visibility.
- Add POSIX termios/ioctl/poll and modern Windows Console API backends behind
  the same public API.
- Add deterministic unit tests, Linux PTY lifecycle tests, cross-platform CI,
  runnable examples, and generated API documentation.
- Add process-isolated POSIX PTY coverage for EOF and rollback when setup fails
  after raw mode has already changed the terminal.
- Add process-isolated Windows Console integration coverage for exact mode and
  cursor restoration after normal close, exceptions, and partial setup failure.
- Keep compiler caches, binaries, test executables, and generated documentation
  under `build/`.
- Document the `0.1.0` API, cleanup guarantees, limitations, and the contract
  required by TerminalPrompt.

### Compatibility

- Support Nim 2.0.0 and newer on Linux, macOS, and Windows.
