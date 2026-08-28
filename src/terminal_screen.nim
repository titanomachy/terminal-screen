## Safe, low-level terminal sessions, input events, cursor control, and geometry.
##
## Use `withTerminalSession` for exception-safe raw-mode restoration, then read
## normalized keys, resize notifications, timeouts, and end-of-input through
## `readEvent`.
##
## .. code-block:: nim
##
##   import terminal_screen
##
##   var options = defaultSessionOptions()
##   options.hideCursor = true
##
##   withTerminalSession session, options:
##     while true:
##       let event = session.readEvent()
##       if event.kind == eventKey and event.keyEvent.key in
##           {keyEscape, keyCtrlC}:
##         break

import terminal_screen/[cursor, decoder, session, terminal, types]

export cursor, decoder, session, terminal, types
