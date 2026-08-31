## Process-isolated POSIX PTY lifecycle scenarios used by the test suite.

when defined(posix):
  import std/[os, posix, termios]

  import terminal_screen

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

  when defined(macosx):
    var PENDIN {.importc, header: "<termios.h>".}: Cflag

  type Pty = object
    master: cint
    slave: File

  proc openPty(): Pty =
    var slaveFd: cint
    if openpty(addr result.master, addr slaveFd, nil, nil, nil) != 0:
      raiseOSError(osLastError())
    if not open(result.slave, FileHandle(slaveFd), fmReadWrite):
      discard posix.close(result.master)
      discard posix.close(slaveFd)
      raise newException(IOError, "cannot wrap PTY slave file descriptor")

  proc close(pty: var Pty) =
    if not pty.slave.isNil:
      pty.slave.close()
    if pty.master >= 0:
      discard posix.close(pty.master)
      pty.master = -1

  proc comparableLocalFlags(mode: Termios): Cflag =
    when defined(macosx):
      # XNU may set this kernel-maintained flag while restoring canonical mode.
      mode.c_lflag and not PENDIN
    else:
      mode.c_lflag

  proc sameMode(left, right: Termios): bool =
    left.c_iflag == right.c_iflag and
      left.c_oflag == right.c_oflag and
      left.c_cflag == right.c_cflag and
      left.comparableLocalFlags == right.comparableLocalFlags and
      left.c_cc == right.c_cc

  proc eofScenario() =
    var pty = openPty()
    defer: pty.close()

    var options = defaultSessionOptions()
    options.rawMode = false
    options.hideCursor = false
    options.monitorResize = false
    options.ansiMode = ansiAlways

    let session = openSession(pty.slave, pty.slave, options)
    discard posix.close(pty.master)
    pty.master = -1
    let event = session.readEvent(timeoutMs = 500)
    session.close()
    if event.kind != eventEndOfInput:
      raise newException(IOError, "PTY hangup did not produce end-of-input")

  proc partialSetupScenario() =
    var pty = openPty()
    defer: pty.close()
    let slaveFd = cint(pty.slave.getFileHandle())
    let slaveNamePointer = posix.ttyname(slaveFd)
    if slaveNamePointer.isNil:
      raiseOSError(osLastError())
    let slaveName = $slaveNamePointer

    var original: Termios
    if tcGetAttr(slaveFd, addr original) != 0:
      raiseOSError(osLastError())

    var readOnlyOutput: File
    if not open(readOnlyOutput, slaveName, fmRead):
      raise newException(IOError, "cannot open read-only PTY output")
    defer: readOnlyOutput.close()

    var options = defaultSessionOptions()
    options.hideCursor = true
    options.monitorResize = false
    options.ansiMode = ansiAlways

    var setupFailed = false
    try:
      let session = openSession(pty.slave, readOnlyOutput, options)
      session.close()
    except CatchableError:
      setupFailed = true

    if not setupFailed:
      raise newException(IOError, "read-only PTY output did not fail setup")

    var restored: Termios
    if tcGetAttr(slaveFd, addr restored) != 0:
      raiseOSError(osLastError())
    if not sameMode(restored, original):
      raise newException(IOError,
        "terminal mode was not restored after partial setup failure")

  if paramCount() != 1:
    quit("expected one PTY lifecycle scenario", QuitFailure)

  case paramStr(1)
  of "eof":
    eofScenario()
  of "partial-setup":
    partialSetupScenario()
  else:
    quit("unknown PTY lifecycle scenario: " & paramStr(1), QuitFailure)
else:
  discard
