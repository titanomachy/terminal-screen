# Changelog

This project follows Semantic Versioning.

## [Unreleased]

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
- Keep compiler caches, binaries, test executables, and generated documentation
  under `build/`.
- Document the `0.1.0` API, cleanup guarantees, limitations, and the contract
  required by TerminalPrompt.

### Compatibility

- Support Nim 2.0.0 and newer on Linux, macOS, and Windows.
