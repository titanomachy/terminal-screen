import std/[options, os, tempfiles, unittest]

import terminal_screen

proc decoded(data: string; finishInput = true): seq[InputEvent] =
  var decoder = initInputDecoder()
  decoder.feed(data)
  if finishInput:
    decoder.finish()
  while true:
    let event = decoder.nextEvent(flushEscape = finishInput)
    if event.isNone:
      break
    result.add(event.get())

proc nonTerminalOptions(): SessionOptions =
  result = defaultSessionOptions()
  result.rawMode = false
  result.hideCursor = false
  result.requireTerminal = false
  result.monitorResize = false
  result.ansiMode = ansiNever

suite "public types":
  test "terminal dimensions are validated":
    check terminalSize(80, 24) == TerminalSize(columns: 80, rows: 24)
    expect ValueError:
      discard terminalSize(0, 24)
    expect ValueError:
      discard terminalSize(80, -1)

  test "default sessions are safe and interactive":
    let options = defaultSessionOptions()
    check options.rawMode
    check options.requireTerminal
    check options.monitorResize
    check not options.hideCursor
    check options.ansiMode == ansiAuto
    check options.escapeTimeoutMs > 0
    check options.resizePollMs > 0

suite "input decoder":
  test "decodes UTF-8 text without splitting code points":
    let events = decoded("Aé🙂")
    check events.len == 4
    check events[0].keyEvent.key == keyText
    check events[0].keyEvent.text == "A"
    check events[1].keyEvent.text == "é"
    check events[2].keyEvent.text == "🙂"
    check events[3].kind == eventEndOfInput

  test "waits for fragmented UTF-8":
    var decoder = initInputDecoder()
    decoder.feed("\xc3")
    check decoder.nextEvent().isNone
    decoder.feed("\xa9")
    let event = decoder.nextEvent()
    check event.isSome
    check event.get().keyEvent.text == "é"

  test "normalizes control and editing keys":
    let events = decoded("\r\t\x7f\x03\x04 ")
    check events[0].keyEvent.key == keyEnter
    check events[1].keyEvent.key == keyTab
    check events[2].keyEvent.key == keyBackspace
    check events[3].keyEvent.key == keyCtrlC
    check events[3].keyEvent.modifiers == {modifierCtrl}
    check events[4].keyEvent.key == keyCtrlD
    check events[5].keyEvent.key == keySpace
    check events[5].keyEvent.text == " "

  test "normalizes common CSI and SS3 navigation":
    let events = decoded(
      "\e[A\e[B\e[C\e[D\e[H\e[F" &
      "\e[2~\e[3~\e[5~\e[6~\eOA\eOF"
    )
    check events[0].keyEvent.key == keyArrowUp
    check events[1].keyEvent.key == keyArrowDown
    check events[2].keyEvent.key == keyArrowRight
    check events[3].keyEvent.key == keyArrowLeft
    check events[4].keyEvent.key == keyHome
    check events[5].keyEvent.key == keyEnd
    check events[6].keyEvent.key == keyInsert
    check events[7].keyEvent.key == keyDelete
    check events[8].keyEvent.key == keyPageUp
    check events[9].keyEvent.key == keyPageDown
    check events[10].keyEvent.key == keyArrowUp
    check events[11].keyEvent.key == keyEnd

  test "decodes modifiers, backtab, and Alt text":
    let events = decoded("\e[1;6A\e[3;3~\e[Z\ex")
    check events[0].keyEvent.key == keyArrowUp
    check events[0].keyEvent.modifiers == {modifierShift, modifierCtrl}
    check events[1].keyEvent.key == keyDelete
    check events[1].keyEvent.modifiers == {modifierAlt}
    check events[2].keyEvent.key == keyBacktab
    check events[2].keyEvent.modifiers == {modifierShift}
    check events[3].keyEvent.key == keyText
    check events[3].keyEvent.text == "x"
    check events[3].keyEvent.modifiers == {modifierAlt}

  test "distinguishes a lone Escape after an explicit flush":
    var decoder = initInputDecoder()
    decoder.feed("\e")
    check decoder.hasPendingEscape
    check decoder.nextEvent().isNone
    let event = decoder.nextEvent(flushEscape = true)
    check event.isSome
    check event.get().keyEvent.key == keyEscape

  test "preserves invalid and unknown input":
    let events = decoded("\xff\e[99~")
    check events[0].keyEvent.key == keyUnknown
    check events[0].keyEvent.sequence == "\xff"
    check events[1].keyEvent.key == keyUnknown
    check events[1].keyEvent.sequence == "\e[99~"

  test "emits end-of-input exactly once":
    var decoder = initInputDecoder()
    decoder.finish()
    check decoder.nextEvent().get().kind == eventEndOfInput
    check decoder.nextEvent().isNone
    expect ValueError:
      decoder.feed("late")

suite "cursor commands":
  test "builds one-based absolute and relative commands":
    check cursorPositionCode(12, 3) == "\e[3;12H"
    check cursorUpCode() == "\e[1A"
    check cursorDownCode(2) == "\e[2B"
    check cursorForwardCode(4) == "\e[4C"
    check cursorBackwardCode(5) == "\e[5D"
    check cursorColumnCode(9) == "\e[9G"

  test "rejects invalid cursor coordinates and counts":
    expect ValueError:
      discard cursorPositionCode(0, 1)
    expect ValueError:
      discard cursorPositionCode(1, 0)
    expect ValueError:
      discard cursorUpCode(0)

  test "writes cursor commands to an injected output":
    let temporary = createTempFile("terminal_screen_cursor_", ".txt")
    let output = temporary.cfile
    defer:
      output.close()
      removeFile(temporary.path)
    output.hideCursor()
    moveCursorTo(7, 2, output)
    output.showCursor(flush = true)
    check readFile(temporary.path) ==
      HideCursorCode & "\e[2;7H" & ShowCursorCode

suite "terminal detection and non-terminal sessions":
  test "reports redirected files without invented geometry":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    let capabilities = detectCapabilities(
      inputTemp.cfile, outputTemp.cfile, ansiAuto)
    check not capabilities.inputIsTerminal
    check not capabilities.outputIsTerminal
    check not capabilities.supportsAnsi
    check not capabilities.supportsRawMode
    check outputTemp.cfile.tryTerminalSize().isNone
    expect TerminalUnavailableError:
      discard outputTemp.cfile.terminalSize()

  test "strict sessions reject redirected streams":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    expect TerminalUnavailableError:
      discard openSession(inputTemp.cfile, outputTemp.cfile)

  test "degraded sessions expose EOF and idempotent cleanup":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    let session = openSession(
      inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    check session.isOpen
    check session.readEvent(timeoutMs = 50).kind == eventEndOfInput
    check session.readEvent(timeoutMs = 0).kind == eventEndOfInput
    session.close()
    session.close()
    check not session.isOpen
    expect TerminalStateError:
      discard session.readEvent(timeoutMs = 0)

  test "a zero timeout still performs one non-blocking read":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    inputTemp.cfile.write("x")
    inputTemp.cfile.flushFile()
    inputTemp.cfile.setFilePos(0)
    let session = openSession(
      inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    defer: session.close()
    let event = session.readEvent(timeoutMs = 0)
    check event.kind == eventKey
    check event.keyEvent.text == "x"

  test "nested sessions are rejected and ownership is released":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    let first = openSession(
      inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    expect SessionActiveError:
      discard openSession(
        inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    first.close()
    let second = openSession(
      inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    second.close()

  test "withTerminalSession closes after an exception":
    let inputTemp = createTempFile("terminal_screen_input_", ".txt")
    let outputTemp = createTempFile("terminal_screen_output_", ".txt")
    defer:
      inputTemp.cfile.close()
      outputTemp.cfile.close()
      removeFile(inputTemp.path)
      removeFile(outputTemp.path)
    expect ValueError:
      withTerminalSession session, inputTemp.cfile, outputTemp.cfile,
          nonTerminalOptions():
        check session.isOpen
        raise newException(ValueError, "injected failure")
    let reopened = openSession(
      inputTemp.cfile, outputTemp.cfile, nonTerminalOptions())
    reopened.close()

when defined(posix):
  import std/[posix, termios]

  when defined(linux):
    {.passL: "-lutil".}

  when defined(macosx):
    proc openpty(master, slave: ptr cint; name: cstring;
                 settings: ptr Termios; size: pointer): cint {.
      importc, header: "<util.h>".}
  else:
    proc openpty(master, slave: ptr cint; name: cstring;
                 settings: ptr Termios; size: pointer): cint {.
      importc, header: "<pty.h>".}

  var TIOCSWINSZ {.importc, header: "<sys/ioctl.h>".}: culong

  type Pty = object
    master: cint
    slave: File

  proc openPty(columns = 80; rows = 24): Pty =
    var slaveFd: cint
    if openpty(addr result.master, addr slaveFd, nil, nil, nil) != 0:
      raiseOSError(osLastError())
    var size = IOctl_WinSize(
      ws_row: cushort(rows),
      ws_col: cushort(columns)
    )
    if ioctl(slaveFd, TIOCSWINSZ, addr size) != 0:
      discard posix.close(result.master)
      discard posix.close(slaveFd)
      raiseOSError(osLastError())
    if not open(result.slave, FileHandle(slaveFd), fmReadWrite):
      discard posix.close(result.master)
      discard posix.close(slaveFd)
      raise newException(IOError, "cannot wrap PTY slave file descriptor")

  proc close(pty: var Pty) =
    pty.slave.close()
    discard posix.close(pty.master)

  proc ptyOptions(): SessionOptions =
    result = defaultSessionOptions()
    result.hideCursor = false
    result.ansiMode = ansiAlways

  suite "POSIX PTY integration":
    test "a session owns matching cursor visibility commands":
      var pty = openPty()
      defer: pty.close()
      var options = ptyOptions()
      options.hideCursor = true
      let session = openSession(pty.slave, pty.slave, options)
      var hidden = newString(HideCursorCode.len)
      check posix.read(pty.master, addr hidden[0], hidden.len) == hidden.len
      check hidden == HideCursorCode
      session.close()
      var shown = newString(ShowCursorCode.len)
      check posix.read(pty.master, addr shown[0], shown.len) == shown.len
      check shown == ShowCursorCode

    test "raw mode is active only while the session owns it":
      var pty = openPty()
      defer: pty.close()
      let slaveFd = cint(pty.slave.getFileHandle())
      var original: Termios
      check tcGetAttr(slaveFd, addr original) == 0

      let session = openSession(pty.slave, pty.slave, ptyOptions())
      var raw: Termios
      check tcGetAttr(slaveFd, addr raw) == 0
      check (raw.c_lflag and ICANON) == 0
      check (raw.c_lflag and ECHO) == 0
      session.close()

      var restored: Termios
      check tcGetAttr(slaveFd, addr restored) == 0
      check restored.c_iflag == original.c_iflag
      check restored.c_oflag == original.c_oflag
      check restored.c_cflag == original.c_cflag
      check restored.c_lflag == original.c_lflag
      check restored.c_cc == original.c_cc

    test "reads real PTY bytes as normalized events":
      var pty = openPty()
      defer: pty.close()
      let session = openSession(pty.slave, pty.slave, ptyOptions())
      defer: session.close()
      let bytes = "é\e[A\x03"
      check posix.write(pty.master, unsafeAddr bytes[0], bytes.len) == bytes.len
      check session.readEvent(timeoutMs = 200).keyEvent.text == "é"
      check session.readEvent(timeoutMs = 200).keyEvent.key == keyArrowUp
      check session.readEvent(timeoutMs = 200).keyEvent.key == keyCtrlC

    test "reports a changed PTY viewport":
      var pty = openPty()
      defer: pty.close()
      let session = openSession(pty.slave, pty.slave, ptyOptions())
      defer: session.close()
      var changed = IOctl_WinSize(ws_row: 40, ws_col: 100)
      check ioctl(cint(pty.slave.getFileHandle()), TIOCSWINSZ, addr changed) == 0
      let event = session.readEvent(timeoutMs = 200)
      check event.kind == eventResize
      check event.size == TerminalSize(columns: 100, rows: 40)

    test "the session template restores termios after exceptions":
      var pty = openPty()
      defer: pty.close()
      let slaveFd = cint(pty.slave.getFileHandle())
      var original: Termios
      check tcGetAttr(slaveFd, addr original) == 0

      expect ValueError:
        withTerminalSession session, pty.slave, pty.slave, ptyOptions():
          check session.isOpen
          raise newException(ValueError, "injected PTY failure")

      var restored: Termios
      check tcGetAttr(slaveFd, addr restored) == 0
      check restored.c_iflag == original.c_iflag
      check restored.c_oflag == original.c_oflag
      check restored.c_cflag == original.c_cflag
      check restored.c_lflag == original.c_lflag
