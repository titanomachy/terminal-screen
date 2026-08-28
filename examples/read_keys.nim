import terminal_screen

let capabilities = detectCapabilities()
if not capabilities.inputIsTerminal or not capabilities.outputIsTerminal:
  quit("read_keys requires an interactive terminal")

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
      stdout.write($event.keyEvent.key)
      if event.keyEvent.text.len > 0:
        stdout.write(": ", event.keyEvent.text)
      stdout.write("\r\n")
      stdout.flushFile()
    of eventResize:
      stdout.write("resized to ", event.size.columns, "x", event.size.rows,
        "\r\n")
      stdout.flushFile()
    of eventEndOfInput:
      break
    of eventTimeout:
      discard
