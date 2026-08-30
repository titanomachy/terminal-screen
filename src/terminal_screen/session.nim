## Guarded terminal sessions and normalized event reading.

import std/[atomics, monotimes, options, times]

import ./[cursor, decoder, terminal, types]
import ./platform/common

when defined(windows):
  import ./platform/windows_terminal
elif defined(posix):
  import ./platform/unix_terminal
else:
  {.error: "TerminalScreen supports POSIX and Windows targets".}

type
  TerminalSession* = ref object
    ## An active, process-wide terminal session.
    ##
    ## Sessions borrow their input and output `File` values. Keep those files
    ## open until `close` returns. Use `withTerminalSession` whenever possible
    ## so restoration runs on normal return and exceptions.
    input: File
    output: File
    options: SessionOptions
    detectedCapabilities: TerminalCapabilities
    platform: PlatformState
    decoder: InputDecoder
    lastSize: Option[TerminalSize]
    inputEnded: bool
    cursorHidden: bool
    closed: bool

var activeSession: AtomicFlag

proc validate(options: SessionOptions) =
  if options.escapeTimeoutMs < 0:
    raise newException(ValueError, "escapeTimeoutMs cannot be negative")
  if options.resizePollMs <= 0:
    raise newException(ValueError, "resizePollMs must be greater than zero")

proc openSession*(input: File = stdin; output: File = stdout;
                  options = defaultSessionOptions()): TerminalSession =
  ## Opens one terminal session and applies the requested modes transactionally.
  ##
  ## Only one session may be active in a process. When `requireTerminal` is
  ## false, redirected streams are accepted and unsupported raw/resize/cursor
  ## features degrade safely.
  options.validate()
  if activeSession.testAndSet(moAcquire):
    raise newException(SessionActiveError,
      "a TerminalScreen session is already active in this process")

  result = TerminalSession(
    input: input,
    output: output,
    options: options,
    decoder: initInputDecoder()
  )

  try:
    result.detectedCapabilities = detectCapabilities(
      input, output, options.ansiMode)
    if options.requireTerminal and
        (not result.detectedCapabilities.inputIsTerminal or
         not result.detectedCapabilities.outputIsTerminal):
      raise newException(TerminalUnavailableError,
        "interactive terminal input and output are required")

    result.platform = startPlatform(
      input,
      output,
      options.rawMode and result.detectedCapabilities.supportsRawMode,
      result.detectedCapabilities.supportsAnsi
    )

    if options.hideCursor and result.detectedCapabilities.supportsAnsi:
      result.cursorHidden = true
      output.hideCursor(flush = true)

    if options.monitorResize and
        result.detectedCapabilities.supportsResizeEvents:
      result.lastSize = output.tryTerminalSize()
  except:
    if result.cursorHidden:
      result.cursorHidden = false
      try:
        output.showCursor(flush = true)
      except CatchableError:
        discard
    try:
      restorePlatform(result.platform)
    except CatchableError:
      discard
    result.closed = true
    activeSession.clear(moRelease)
    raise

proc isOpen*(session: TerminalSession): bool =
  ## Returns whether `session` still owns terminal state.
  not session.isNil and not session.closed

proc capabilities*(session: TerminalSession): TerminalCapabilities =
  ## Returns the capabilities captured when `session` opened.
  if session.isNil:
    raise newException(ValueError, "session cannot be nil")
  session.detectedCapabilities

proc close*(session: TerminalSession) =
  ## Restores state owned by `session`; repeated calls are safe.
  ##
  ## Restoration continues after an individual cursor or platform error. The
  ## first failure is raised only after all remaining cleanup has been tried.
  if session.isNil or session.closed:
    return

  session.closed = true
  var firstError = ""
  if session.cursorHidden:
    session.cursorHidden = false
    try:
      session.output.showCursor(flush = true)
    except CatchableError as error:
      firstError = "cannot restore cursor visibility: " & error.msg

  try:
    restorePlatform(session.platform)
  except CatchableError as error:
    if firstError.len == 0:
      firstError = error.msg

  activeSession.clear(moRelease)
  if firstError.len > 0:
    raise newException(TerminalStateError, firstError)

proc checkResize(session: TerminalSession): Option[InputEvent] =
  if not session.options.monitorResize or
      not session.detectedCapabilities.supportsResizeEvents:
    return none(InputEvent)
  let current = session.output.tryTerminalSize()
  if current.isSome and (session.lastSize.isNone or
      current.get() != session.lastSize.get()):
    session.lastSize = current
    return some(resizeInput(current.get()))
  none(InputEvent)

proc elapsedMilliseconds(started: MonoTime): int =
  int((getMonoTime() - started).inMilliseconds)

proc readEvent*(session: TerminalSession; timeoutMs = -1): InputEvent =
  ## Reads one normalized terminal event.
  ##
  ## Byte-stream backends do not read ahead past the returned event. Closing a
  ## session therefore leaves later input on its borrowed `File` available to a
  ## subsequent session or another consumer.
  ##
  ## `timeoutMs = -1` waits indefinitely. A non-negative timeout returns
  ## `eventTimeout` when no input or resize is available. A lone Escape is
  ## resolved after `SessionOptions.escapeTimeoutMs`.
  if not session.isOpen:
    raise newException(TerminalStateError, "cannot read from a closed session")
  if timeoutMs < -1:
    raise newException(ValueError, "timeoutMs must be -1 or non-negative")

  let started = getMonoTime()
  var polled = false
  while true:
    let decoded = session.decoder.nextEvent()
    if decoded.isSome:
      return decoded.get()
    if session.inputEnded:
      return endOfInput()

    let resized = session.checkResize()
    if resized.isSome:
      return resized.get()

    let elapsed = elapsedMilliseconds(started)
    if timeoutMs >= 0 and elapsed >= timeoutMs and polled and
        not session.decoder.hasPendingInput:
      return timeoutInput()

    var waitMs: int
    if session.decoder.hasPendingEscape:
      waitMs = session.options.escapeTimeoutMs
    elif session.options.monitorResize and
        session.detectedCapabilities.supportsResizeEvents:
      waitMs = session.options.resizePollMs
    else:
      waitMs = -1

    if timeoutMs >= 0:
      let remaining = max(0, timeoutMs - elapsed)
      if waitMs < 0 or waitMs > remaining:
        waitMs = remaining

    let platformRead = readPlatform(session.platform, waitMs)
    polled = true
    case platformRead.kind
    of platformBytes:
      session.decoder.feed(platformRead.data)
    of platformEvent:
      return platformRead.event
    of platformEndOfInput:
      session.inputEnded = true
      session.decoder.finish()
    of platformTimeout:
      if session.decoder.hasPendingEscape:
        let escaped = session.decoder.nextEvent(flushEscape = true)
        if escaped.isSome:
          return escaped.get()
      if timeoutMs >= 0 and elapsedMilliseconds(started) >= timeoutMs:
        return timeoutInput()

template withTerminalSession*(sessionName: untyped; options: SessionOptions;
                              body: untyped): untyped =
  ## Runs `body` inside a default-stream terminal session.
  block:
    let sessionName {.inject.} = openSession(options = options)
    try:
      body
    finally:
      sessionName.close()

template withTerminalSession*(sessionName: untyped; body: untyped): untyped =
  ## Runs `body` with default streams and session options.
  withTerminalSession(sessionName, defaultSessionOptions()):
    body

template withTerminalSession*(sessionName: untyped; input, output: File;
                              options: SessionOptions; body: untyped): untyped =
  ## Runs `body` with explicit borrowed streams and session options.
  block:
    let sessionName {.inject.} = openSession(input, output, options)
    try:
      body
    finally:
      sessionName.close()
