import terminal_screen

if not stdout.isTerminal:
  quit("cursor_commands requires terminal output")

var options = defaultSessionOptions()
options.rawMode = false
options.hideCursor = true
options.monitorResize = false

withTerminalSession session, options:
  moveCursorTo(column = 5, row = 3, output = stdout)
  stdout.write("TerminalScreen cursor example\r\n")
  stdout.flushFile()
