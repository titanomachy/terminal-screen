## Run: nim r --path:src examples/cursor_commands.nim
## A finite animation; the session restores cursor visibility on exit.
import std/[os, strutils]
import terminal_screen

if not stdout.isTerminal:
  quit("cursor_commands requires terminal output")

var options = defaultSessionOptions()
options.rawMode = false
options.hideCursor = true
options.monitorResize = false

withTerminalSession session, options:
  moveCursorTo(column = 1, row = 2)
  stdout.write("Cursor control / batched output")
  moveCursorTo(column = 1, row = 4)
  stdout.write("Updating row 6, starting at column 5:")
  for step in 0 .. 10:
    let bar = repeat('#', step * 3) & repeat('.', (10 - step) * 3)
    stdout.write(cursorPositionCode(column = 5, row = 6),
      "[", bar, "] ", align($(step * 10), 3), "%")
    stdout.flushFile()
    sleep(180)
  moveCursorTo(column = 1, row = 8)
  stdout.write("Done. The session restores the cursor.\r\n")
  stdout.flushFile()
  sleep(800)
