## Process-isolated Windows Console lifecycle scenarios used by the test suite.

when defined(windows):
  import std/[os, tempfiles]
  import windows/winlean

  import terminal_screen

  const
    EnableProcessedInput = 0x0001'i32
    EnableLineInput = 0x0002'i32
    EnableEchoInput = 0x0004'i32
    EnableWindowInput = 0x0008'i32
    EnableQuickEditMode = 0x0040'i32
    EnableExtendedFlags = 0x0080'i32
    EnableProcessedOutput = 0x0001'i32
    EnableVirtualTerminalProcessing = 0x0004'i32

    KeyEventType = 0x0001'i16
    VkC = 0x43'i16
    VkLeft = 0x25'i16
    VkQ = 0x51'i16
    RightAltPressed = 0x0001'i32
    LeftCtrlPressed = 0x0008'i32

  type
    ConsoleCursorInfo {.importc: "CONSOLE_CURSOR_INFO",
        header: "<windows.h>".} = object
      size {.importc: "dwSize".}: DWORD
      visible {.importc: "bVisible".}: WINBOOL

    IsolatedConsole = object
      input: File
      output: File
      attached: bool

  proc allocConsole(): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "AllocConsole".}

  proc freeConsole(): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "FreeConsole".}

  proc getConsoleMode(handle: Handle; mode: ptr DWORD): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}

  proc setConsoleMode(handle: Handle; mode: DWORD): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

  proc getConsoleCursorInfo(handle: Handle;
      info: ptr ConsoleCursorInfo): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetConsoleCursorInfo".}

  proc setConsoleCursorInfo(handle: Handle;
      info: ptr ConsoleCursorInfo): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleCursorInfo".}

  proc writeConsoleInput(handle: Handle; record: pointer; count: cint;
      written: ptr cint): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "WriteConsoleInputW".}

  proc getOsfhandle(fileDescriptor: cint): Handle {.
    importc: "_get_osfhandle", header: "<io.h>".}

  proc openOsfhandle(handle: int; flags: cint): cint {.
    importc: "_open_osfhandle", header: "<io.h>".}

  proc closeDescriptor(descriptor: cint): cint {.
    importc: "_close", header: "<io.h>".}

  proc osHandle(file: File): Handle =
    getOsfhandle(cint(file.getFileHandle()))

  proc fail(message: string) =
    raise newException(IOError, message)

  proc checkApi(success: WINBOOL; operation: string) =
    if success == 0:
      fail(operation & ": " & osErrorMsg(OSErrorCode(getLastError())))

  proc checkValue(condition: bool; message: string) =
    if not condition:
      fail(message)

  proc close(console: var IsolatedConsole) =
    if not console.input.isNil:
      console.input.close()
    if not console.output.isNil:
      console.output.close()
    if console.attached:
      discard freeConsole()
      console.attached = false

  proc openIsolatedConsole(): IsolatedConsole =
    # A child may inherit its caller's console. Detach first so these tests
    # cannot change the developer terminal or the CI runner's console state.
    discard freeConsole()
    checkApi(allocConsole(), "cannot allocate an isolated Windows console")
    result.attached = true
    try:
      if not open(result.input, "CONIN$", fmReadWrite):
        fail("cannot open isolated Windows console input")
      if not open(result.output, "CONOUT$", fmReadWrite):
        fail("cannot open isolated Windows console output")
    except:
      result.close()
      raise

  proc consoleMode(file: File): DWORD =
    checkApi(getConsoleMode(file.osHandle(), addr result),
      "cannot read Windows console mode")

  proc cursorInfo(file: File): ConsoleCursorInfo =
    checkApi(getConsoleCursorInfo(file.osHandle(), addr result),
      "cannot read Windows cursor visibility")

  proc prepareBaseline(console: IsolatedConsole): tuple[
      inputMode, outputMode: DWORD] =
    result.inputMode = console.input.consoleMode() or DWORD(
      EnableProcessedInput or EnableLineInput or EnableEchoInput or
      EnableQuickEditMode or EnableExtendedFlags
    )
    result.outputMode = console.output.consoleMode() and not DWORD(
      EnableProcessedOutput or EnableVirtualTerminalProcessing)
    checkApi(setConsoleMode(console.input.osHandle(), result.inputMode),
      "cannot establish the Windows input-mode baseline")
    checkApi(setConsoleMode(console.output.osHandle(), result.outputMode),
      "cannot establish the Windows output-mode baseline")

    var cursor = console.output.cursorInfo()
    cursor.visible = 1
    checkApi(setConsoleCursorInfo(console.output.osHandle(), addr cursor),
      "cannot establish the visible-cursor baseline")

  proc sessionOptions(): SessionOptions =
    result = defaultSessionOptions()
    result.hideCursor = true
    result.monitorResize = false
    result.ansiMode = ansiAlways

  proc checkSessionState(console: IsolatedConsole; baselineInput,
      baselineOutput: DWORD) =
    let expectedInput =
      (baselineInput and not DWORD(
        EnableProcessedInput or EnableLineInput or EnableEchoInput or
        EnableQuickEditMode
      )) or DWORD(EnableWindowInput or EnableExtendedFlags)
    checkValue(console.input.consoleMode() == expectedInput,
      "Windows raw input mode was not enabled exactly")
    checkValue(console.output.consoleMode() ==
        (baselineOutput or DWORD(
          EnableProcessedOutput or EnableVirtualTerminalProcessing)),
      "Windows virtual-terminal output mode was not enabled exactly")
    checkValue(console.output.cursorInfo().visible == 0,
      "the Windows console cursor was not hidden")

  proc checkRestoredState(console: IsolatedConsole; baselineInput,
      baselineOutput: DWORD) =
    checkValue(console.input.consoleMode() == baselineInput,
      "the exact Windows input mode was not restored")
    checkValue(console.output.consoleMode() == baselineOutput,
      "the exact Windows output mode was not restored")
    checkValue(console.output.cursorInfo().visible != 0,
      "the Windows console cursor was not restored")

  proc writeCtrlC(console: IsolatedConsole) =
    var record = KEY_EVENT_RECORD(
      eventType: KeyEventType,
      bKeyDown: 1,
      wRepeatCount: 1,
      wVirtualKeyCode: VkC,
      uChar: 3,
      dwControlKeyState: DWORD(LeftCtrlPressed)
    )
    var written: cint
    checkApi(writeConsoleInput(console.input.osHandle(), addr record, 1,
      addr written), "cannot inject Ctrl+C into the Windows console")
    checkValue(written == 1, "Windows did not accept the Ctrl+C input record")

  proc writeKey(console: IsolatedConsole; virtualKey, character: int16;
                controlState: DWORD = 0; repeatCount: int16 = 1) =
    var record = KEY_EVENT_RECORD(
      eventType: KeyEventType,
      bKeyDown: 1,
      wRepeatCount: repeatCount,
      wVirtualKeyCode: virtualKey,
      uChar: character,
      dwControlKeyState: controlState
    )
    var written: cint
    checkApi(writeConsoleInput(console.input.osHandle(), addr record, 1,
      addr written), "cannot inject a key into the Windows console")
    checkValue(written == 1, "Windows did not accept the key input record")

  proc normalCleanupScenario() =
    var console = openIsolatedConsole()
    defer: console.close()
    let baseline = console.prepareBaseline()

    let session = openSession(
      console.input, console.output, sessionOptions())
    try:
      console.checkSessionState(baseline.inputMode, baseline.outputMode)
      console.writeCtrlC()
      let event = session.readEvent(timeoutMs = 500)
      checkValue(event.kind == eventKey and event.keyEvent.key == keyCtrlC,
        "a real Windows Ctrl+C record was not normalized")
    finally:
      session.close()
    session.close()
    console.checkRestoredState(baseline.inputMode, baseline.outputMode)

  proc exceptionCleanupScenario() =
    var console = openIsolatedConsole()
    defer: console.close()
    let baseline = console.prepareBaseline()

    var caught = false
    try:
      withTerminalSession session, console.input, console.output,
          sessionOptions():
        console.checkSessionState(baseline.inputMode, baseline.outputMode)
        raise newException(ValueError, "injected Windows console failure")
    except ValueError:
      caught = true
    checkValue(caught, "the injected Windows console exception was not raised")
    console.checkRestoredState(baseline.inputMode, baseline.outputMode)

  proc partialSetupScenario() =
    var console = openIsolatedConsole()
    defer: console.close()
    let baseline = console.prepareBaseline()

    var readOnlyOutput: File
    if not open(readOnlyOutput, "CONOUT$", fmRead):
      fail("cannot open read-only Windows console output")
    defer: readOnlyOutput.close()

    var setupFailed = false
    try:
      discard openSession(
        console.input, readOnlyOutput, sessionOptions())
    except CatchableError:
      setupFailed = true
    checkValue(setupFailed,
      "read-only Windows console output did not fail cursor setup")
    console.checkRestoredState(baseline.inputMode, baseline.outputMode)

    # Rollback must release process-wide ownership as well as restoring modes.
    let reopened = openSession(
      console.input, console.output, sessionOptions())
    reopened.close()

  proc nativeInputScenario() =
    var console = openIsolatedConsole()
    defer: console.close()
    let baseline = console.prepareBaseline()

    let session = openSession(
      console.input, console.output, sessionOptions())
    try:
      console.writeKey(VkQ, int16(ord('@')),
        DWORD(RightAltPressed or LeftCtrlPressed))
      let altGr = session.readEvent(timeoutMs = 500)
      checkValue(altGr.kind == eventKey and
          altGr.keyEvent.key == keyText and altGr.keyEvent.text == "@" and
          altGr.keyEvent.modifiers == {},
        "Windows AltGr text was not normalized as printable input")

      console.writeKey(VkLeft, 0, repeatCount = 3)
      for _ in 0 ..< 3:
        let repeated = session.readEvent(timeoutMs = 500)
        checkValue(repeated.kind == eventKey and
            repeated.keyEvent.key == keyArrowLeft,
          "a repeated Windows key record did not emit every event")
    finally:
      session.close()
    console.checkRestoredState(baseline.inputMode, baseline.outputMode)

  proc pipeEofScenario(buffered = false) =
    # Private pipe and file: never modify the inherited console or streams.
    var reader, writer: Handle
    var attributes = SECURITY_ATTRIBUTES(nLength: int32(sizeof(SECURITY_ATTRIBUTES)))
    checkApi(createPipe(reader, writer, attributes, 0),
      "cannot create a Windows pipe")
    defer:
      if reader != 0:
        discard closeHandle(reader)
      if writer != 0:
        discard closeHandle(writer)

    let descriptor = openOsfhandle(int(reader), 0x8000) # _O_BINARY | _O_RDONLY
    checkValue(descriptor >= 0, "cannot wrap the Windows pipe handle")
    reader = 0 # The CRT descriptor owns this handle now.
    var input: File
    if not open(input, FileHandle(descriptor), fmRead):
      discard closeDescriptor(descriptor)
      fail("cannot wrap the Windows pipe descriptor")
    defer: input.close()

    let output = createTempFile("terminal_screen_pipe_", ".txt")
    defer:
      output.cfile.close()
      removeFile(output.path)
    let bytes = if buffered: "header\né\e[Ax" else: "é\e[A"
    var written: int32
    checkApi(writeFile(writer, unsafeAddr bytes[0], int32(bytes.len),
      addr written, nil), "cannot write to the Windows pipe")
    checkValue(written == int32(bytes.len), "Windows pipe write was incomplete")
    if buffered:
      checkValue(input.readLine() == "header", "Windows pipe header was not read")
      var available: int32
      checkValue(peekNamedPipe(input.osHandle(), lpTotalBytesAvail = addr available),
        "cannot check buffered Windows pipe input")
      checkValue(available == 0, "the pipe still has bytes outside its File buffer")
    else:
      checkApi(closeHandle(writer), "cannot close the Windows pipe writer")
      writer = 0

    var options = defaultSessionOptions()
    options.requireTerminal = false
    options.ansiMode = ansiNever
    options.monitorResize = false
    let session = openSession(input, output.cfile, options)
    defer: session.close()
    let text = session.readEvent(timeoutMs = 500)
    checkValue(text.kind == eventKey and text.keyEvent.text == "é",
      "Windows piped UTF-8 text was not decoded")
    let arrow = session.readEvent(timeoutMs = 500)
    checkValue(arrow.kind == eventKey and arrow.keyEvent.key == keyArrowUp,
      "Windows piped navigation was not decoded")
    if buffered:
      session.close()
      checkValue(input.readChar() == 'x',
        "the session consumed later buffered Windows pipe input")
      checkApi(closeHandle(writer), "cannot close the Windows pipe writer")
      writer = 0
      let reopened = openSession(input, output.cfile, options)
      defer: reopened.close()
      checkValue(reopened.readEvent(timeoutMs = 500).kind == eventEndOfInput,
        "a reopened buffered Windows pipe did not report EOF")
      return
    checkValue(session.readEvent(timeoutMs = 500).kind == eventEndOfInput,
      "a closed Windows pipe did not report EOF")
    checkValue(session.readEvent(timeoutMs = 0).kind == eventEndOfInput,
      "a subsequent read after Windows pipe EOF raised or timed out")
    session.close()
    checkValue(input.getFileHandle() == FileHandle(descriptor),
      "the session closed its borrowed pipe")

  if paramCount() != 1:
    quit("expected one Windows console lifecycle scenario", QuitFailure)

  case paramStr(1)
  of "normal-cleanup":
    normalCleanupScenario()
  of "exception-cleanup":
    exceptionCleanupScenario()
  of "partial-setup":
    partialSetupScenario()
  of "native-input":
    nativeInputScenario()
  of "pipe-eof":
    pipeEofScenario()
  of "buffered-pipe":
    pipeEofScenario(buffered = true)
  else:
    quit("unknown Windows console lifecycle scenario: " & paramStr(1),
      QuitFailure)
else:
  discard
