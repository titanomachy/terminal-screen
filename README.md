# TerminalScreen

TerminalScreen is a dependency-free, pure-Nim foundation for safe interactive
terminal applications. Version 0.1.0 provides guarded raw-mode sessions,
normalized key input, cursor control, terminal detection, viewport geometry,
resize events, timeouts, EOF handling, and Unix/Windows backends.

It is the low-level terminal layer for TerminalPrompt and future interactive
packages in the Nim Terminal Suite. Styling and cell-width-aware text belong in
[TerminalStyle](https://github.com/titanomachy/terminal-style); layout, prompt
policy, and widget state deliberately remain outside this package.

## Requirements

- Nim 2.0.0 or newer
- Linux, macOS, or Windows
- A VT/ANSI-capable terminal for cursor commands

TerminalScreen uses only the Nim standard library and operating-system APIs.

## Reading keys safely

`withTerminalSession` restores the exact saved OS input mode and shows a cursor
hidden by the session after normal return or an exception:

```nim
import terminal_screen

var options = defaultSessionOptions()
options.hideCursor = true

withTerminalSession session, options:
  stdout.write("Press keys; Escape or Ctrl+C exits.\r\n")
  stdout.flushFile()

  while true:
    let event = session.readEvent()
    case event.kind
    of eventKey:
      if event.keyEvent.key in {keyEscape, keyCtrlC}:
        break
      if event.keyEvent.key == keyText:
        stdout.write("text: ", event.keyEvent.text, "\r\n")
        stdout.flushFile()
    of eventResize:
      stdout.write("size: ", event.size.columns, "x", event.size.rows, "\r\n")
      stdout.flushFile()
    of eventEndOfInput:
      break
    of eventTimeout:
      discard
```

Raw mode disables terminal-generated `SIGINT`, so keyboard `Ctrl+C` is returned
as `keyCtrlC` and the application can leave its session normally. A lone Escape
is distinguished from an escape-sequence prefix with a short configurable
timeout.

## Detection and geometry

Check capabilities before choosing an interactive or line-oriented interface:

```nim
import std/options
import terminal_screen

let capabilities = detectCapabilities()
if capabilities.inputIsTerminal and capabilities.outputIsTerminal:
  let size = tryTerminalSize()
  if size.isSome:
    echo size.get().columns, " columns x ", size.get().rows, " rows"
else:
  echo "Input or output is redirected; use a non-interactive fallback."
```

Strict sessions reject redirected streams by default. Set
`requireTerminal = false` to use normalized EOF/input behavior with redirected
files or pipes; raw mode, automatic cursor hiding, and resize monitoring then
degrade according to detected capabilities.

## Cursor control

Coordinates are one-based, matching ANSI terminal protocols:

```nim
import terminal_screen

if stdout.isTerminal:
  var options = defaultSessionOptions()
  options.rawMode = false
  options.hideCursor = true
  options.monitorResize = false

  withTerminalSession session, options:
    moveCursorTo(column = 10, row = 4, output = stdout)
    stdout.write("Hello")
    stdout.flushFile()
```

Pure command builders such as `cursorPositionCode`, `cursorUpCode`, and
`cursorColumnCode` are available for batching and deterministic tests. Opening
a session also enables VT output on supported Windows consoles and restores its
previous console mode afterward.

## Incremental decoding

`InputDecoder` can be fed scripted or fragmented bytes without a live terminal.
This is the test seam intended for TerminalPrompt:

```nim
import std/options
import terminal_screen

var decoder = initInputDecoder()
decoder.feed("é\e[A")

while true:
  let event = decoder.nextEvent()
  if event.isNone:
    break
  # Produces keyText("é"), then keyArrowUp.
  discard event.get()
```

The decoder handles UTF-8 text, Enter, Escape, arrows, Home/End, Insert/Delete,
Page Up/Down, Tab/Backtab, Backspace, Space, Ctrl+C, Ctrl+D, common xterm
modifiers, SS3 navigation, unknown sequences, and EOF.

## Session and cleanup guarantees

- A session captures terminal modes before changing them and restores the exact
  snapshot in reverse order.
- Setup is transactional and `close` is idempotent.
- One session may own process-wide terminal state at a time; nested opens raise
  `SessionActiveError`.
- The session borrows its `File` streams. Keep them open until cleanup finishes.
- Resize events are detected through bounded geometry polling in 0.1.0, avoiding
  unsafe allocation or cleanup inside a signal handler.

Cleanup runs for normal return, decoded Ctrl+C cancellation, EOF, and Nim
exceptions when `withTerminalSession` is used. No application can restore a
terminal after `SIGKILL`, power loss, or another uncatchable process failure.
On Unix, `reset` or `tput reset` is an emergency recovery measure—not the normal
shutdown design.

## Development

Nimble manages the package and all generated output stays under `build/`:

```sh
nimble check
nimble compilePackage
nimble test
nimble examples
nimble docs
nimble releaseCheck
```

Runnable examples are in `examples/`. Generated API documentation is written to
`build/docs/terminal_screen.html`.
