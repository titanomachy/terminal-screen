## Run: printf 'Hi\n' | nim r --path:src examples/redirected_input.nim
import terminal_screen

var options = defaultSessionOptions()
options.requireTerminal = false

echo "Redirected input / normalized events"
withTerminalSession session, options:
  while true:
    let event = session.readEvent()
    case event.kind
    of eventKey:
      echo event.keyEvent.key, " text=", event.keyEvent.text
    of eventEndOfInput:
      echo "eventEndOfInput"
      break
    of eventResize, eventTimeout:
      discard
echo "Session closed; borrowed streams stay open."
