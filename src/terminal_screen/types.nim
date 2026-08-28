## Shared public types for TerminalScreen.

type
  TerminalError* = object of CatchableError
    ## Base error raised by TerminalScreen operations.

  TerminalUnavailableError* = object of TerminalError
    ## Raised when an operation requires a terminal but receives a pipe or file.

  TerminalStateError* = object of TerminalError
    ## Raised when a terminal mode cannot be entered or restored.

  TerminalIOError* = object of TerminalError
    ## Raised when terminal input, output, or geometry access fails.

  SessionActiveError* = object of TerminalError
    ## Raised when a second process-wide terminal session is opened.

  TerminalSize* = object
    ## Terminal viewport dimensions in character cells.
    columns*: int
    rows*: int

  Modifier* = enum
    ## Keyboard modifiers reported by a terminal input protocol.
    modifierShift
    modifierAlt
    modifierCtrl

  Key* = enum
    ## Normalized keys understood by TerminalPrompt and other consumers.
    keyUnknown
    keyText
    keySpace
    keyEnter
    keyEscape
    keyTab
    keyBacktab
    keyBackspace
    keyDelete
    keyInsert
    keyHome
    keyEnd
    keyArrowUp
    keyArrowDown
    keyArrowLeft
    keyArrowRight
    keyPageUp
    keyPageDown
    keyCtrlC
    keyCtrlD

  KeyEvent* = object
    ## A normalized keyboard event.
    ##
    ## `text` contains valid UTF-8 for `keyText` and `keySpace`. `sequence`
    ## preserves the consumed bytes for unknown input so callers can diagnose
    ## or deliberately ignore unsupported protocols.
    key*: Key
    text*: string
    sequence*: string
    modifiers*: set[Modifier]

  InputEventKind* = enum
    ## Kinds returned by a terminal session or incremental decoder.
    eventKey
    eventResize
    eventEndOfInput
    eventTimeout

  InputEvent* = object
    ## A normalized terminal input event.
    case kind*: InputEventKind
    of eventKey:
      keyEvent*: KeyEvent
    of eventResize:
      size*: TerminalSize
    of eventEndOfInput, eventTimeout:
      discard

  AnsiMode* = enum
    ## Controls whether a session may emit ANSI/VT control sequences.
    ansiAuto
    ansiAlways
    ansiNever

  TerminalCapabilities* = object
    ## Basic properties detected for an input/output stream pair.
    inputIsTerminal*: bool
    outputIsTerminal*: bool
    supportsAnsi*: bool
    supportsRawMode*: bool
    supportsResizeEvents*: bool

  SessionOptions* = object
    ## Configuration used by `openSession`.
    rawMode*: bool
    hideCursor*: bool
    requireTerminal*: bool
    monitorResize*: bool
    ansiMode*: AnsiMode
    escapeTimeoutMs*: int
    resizePollMs*: int

proc terminalSize*(columns, rows: int): TerminalSize =
  ## Constructs validated terminal dimensions.
  if columns <= 0 or rows <= 0:
    raise newException(ValueError,
      "terminal dimensions must both be greater than zero")
  TerminalSize(columns: columns, rows: rows)

proc keyInput*(key: Key; text = ""; modifiers: set[Modifier] = {};
               sequence = ""): InputEvent =
  ## Constructs a normalized key event.
  InputEvent(
    kind: eventKey,
    keyEvent: KeyEvent(
      key: key,
      text: text,
      sequence: sequence,
      modifiers: modifiers
    )
  )

proc resizeInput*(size: TerminalSize): InputEvent =
  ## Constructs a resize event.
  InputEvent(kind: eventResize, size: size)

proc endOfInput*(): InputEvent =
  ## Constructs an end-of-input event.
  InputEvent(kind: eventEndOfInput)

proc timeoutInput*(): InputEvent =
  ## Constructs an input timeout event.
  InputEvent(kind: eventTimeout)

proc defaultSessionOptions*(): SessionOptions =
  ## Returns the safe interactive defaults used by `openSession`.
  SessionOptions(
    rawMode: true,
    hideCursor: false,
    requireTerminal: true,
    monitorResize: true,
    ansiMode: ansiAuto,
    escapeTimeoutMs: 30,
    resizePollMs: 50
  )
