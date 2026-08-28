## Terminal detection, capabilities, and geometry.

import std/[options, os]

import ./types

when defined(windows):
  import ./platform/windows_terminal
elif defined(posix):
  import ./platform/unix_terminal
else:
  {.error: "TerminalScreen supports POSIX and Windows targets".}

proc isTerminal*(file: File): bool =
  ## Returns whether `file` is attached to a terminal/console.
  isTerminalPlatform(file)

proc ansiEnabled(output: File; mode: AnsiMode): bool =
  case mode
  of ansiAlways:
    true
  of ansiNever:
    false
  of ansiAuto:
    output.isTerminal and getEnv("TERM", "") != "dumb"

proc detectCapabilities*(input: File = stdin; output: File = stdout;
                         ansiMode = ansiAuto): TerminalCapabilities =
  ## Detects the basic capabilities needed by an interactive consumer.
  let inputTty = input.isTerminal
  let outputTty = output.isTerminal
  TerminalCapabilities(
    inputIsTerminal: inputTty,
    outputIsTerminal: outputTty,
    supportsAnsi: ansiEnabled(output, ansiMode),
    supportsRawMode: inputTty,
    supportsResizeEvents: outputTty
  )

proc tryTerminalSize*(output: File = stdout): Option[TerminalSize] =
  ## Returns the current viewport dimensions, or `none` when unavailable.
  tryTerminalSizePlatform(output)

proc terminalSize*(output: File = stdout): TerminalSize =
  ## Returns the current viewport dimensions.
  ##
  ## Raises `TerminalUnavailableError` when `output` has no terminal geometry.
  let size = output.tryTerminalSize()
  if size.isNone:
    raise newException(TerminalUnavailableError,
      "terminal dimensions are unavailable for this output stream")
  size.get()
