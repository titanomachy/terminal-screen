## Finite README capture driver. Uses a private PTY for scripted key input.
## Compile before capture: nim c scripts/record_demo.nim

when not (defined(linux) or defined(macosx)):
  {.error: "README recording requires Linux or macOS".}

import std/[atomics, monotimes, os, posix, strutils, termios, times]

var interrupted: Atomic[bool]

proc requestStop() {.noconv.} =
  interrupted.store(true, moRelaxed)

proc checkInterrupted() =
  if interrupted.load(moRelaxed):
    raise newException(IOError, "interrupted by Ctrl+C")

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

proc startDemo(binary: string; args: openArray[string] = [];
               inputFd: cint = STDIN_FILENO; outputFd: cint = STDOUT_FILENO;
               errorFd: cint = STDERR_FILENO;
               closeFds: openArray[cint] = []): Pid =
  let arguments = allocCStringArray(@[binary] & @args)
  defer: deallocCStringArray(arguments)
  result = fork()
  if result < 0:
    raiseOSError(osLastError())
  if result == 0:
    if dup2(inputFd, STDIN_FILENO) < 0 or
        dup2(outputFd, STDOUT_FILENO) < 0 or
        dup2(errorFd, STDERR_FILENO) < 0:
      exitnow(126)
    for fd in closeFds:
      if fd > STDERR_FILENO:
        discard posix.close(fd)
    discard execv(binary.cstring, arguments)
    exitnow(127)

proc stopDemo(child: var Pid) =
  if child > 0:
    discard posix.kill(child, SIGKILL)
    var status: cint
    while waitpid(child, status, 0) < 0 and errno == EINTR:
      discard
    child = -1

proc awaitDemo(child: var Pid; timeoutMs: int) =
  let started = getMonoTime()
  while (getMonoTime() - started).inMilliseconds < timeoutMs:
    checkInterrupted()
    var status: cint
    let waited = waitpid(child, status, WNOHANG)
    if waited > 0:
      child = -1
      if not WIFEXITED(status) or WEXITSTATUS(status) != 0:
        raise newException(IOError, "demo failed: wait status " & $status)
      return
    if waited < 0 and errno != EINTR:
      raiseOSError(osLastError())
    sleep(20)
  raise newException(IOError, "demo did not finish within its timeout")

proc resize(master: cint; columns: int) =
  var size = IOctl_WinSize(ws_row: 12, ws_col: cushort(columns))
  if ioctl(master, TIOCSWINSZ, addr size) != 0:
    raiseOSError(osLastError())

proc recordKeys(binary: string) =
  var master, slave: cint
  if openpty(addr master, addr slave, nil, nil, nil) != 0:
    raiseOSError(osLastError())
  var child: Pid = -1
  defer:
    stopDemo(child)
    discard posix.close(master)
    if slave >= 0:
      discard posix.close(slave)

  resize(master, 64)
  child = startDemo(binary, inputFd = slave, outputFd = slave,
    errorFd = slave, closeFds = [master, slave])
  discard posix.close(slave)
  slave = -1

  # Wait for the raw-mode prompt before sending any input.
  const schedule = [
    (500, "a", 0), (1000, "é", 0), (1500, "\e[A", 0),
    (2000, "\e[1;5D", 0), (2500, "\r", 0), (3000, "", 60),
    (3700, "\x03", 0)]
  let started = getMonoTime()
  var ready: MonoTime
  var hasPrompt = false
  var pending = ""
  var nextAction = 0
  var buffer: array[65536, char]

  while true:
    checkInterrupted()
    let now = getMonoTime()
    if (now - started).inMilliseconds >= 10000:
      raise newException(IOError, "key demo did not finish within 10 seconds")
    if hasPrompt and nextAction < schedule.len and
        (now - ready).inMilliseconds >= schedule[nextAction][0]:
      let (_, input, columns) = schedule[nextAction]
      if columns > 0:
        resize(master, columns)
      elif posix.write(master, input.cstring, input.len) != input.len:
        raise newException(IOError, "cannot send scripted key input")
      inc nextAction

    var descriptor = TPollfd(fd: master, events: POLLIN)
    let available = poll(addr descriptor, 1, 20)
    if available < 0:
      if errno == EINTR:
        continue
      raiseOSError(osLastError())
    if available == 0:
      continue
    let count = posix.read(master, addr buffer[0], buffer.len)
    if count < 0:
      if errno == EIO: # Linux reports PTY hangup as EIO; macOS returns EOF.
        break
      if errno == EINTR:
        continue
      raiseOSError(osLastError())
    if count == 0:
      break
    if stdout.writeBuffer(addr buffer[0], count) != count:
      raise newException(IOError, "cannot forward demo output")
    stdout.flushFile()
    if not hasPrompt:
      for index in 0 ..< count:
        pending.add(buffer[index])
      if "Press keys" in pending:
        ready = getMonoTime()
        hasPrompt = true
      elif pending.len > 32:
        pending = pending[^32 .. ^1]

  awaitDemo(child, 2000)

proc recordRedirected(binary: string) =
  var fds: array[2, cint]
  if pipe(fds) != 0:
    raiseOSError(osLastError())
  var child: Pid = -1
  defer:
    stopDemo(child)
    for fd in fds:
      if fd >= 0:
        discard posix.close(fd)
  # Queue input before forking so even an early child exit cannot cause SIGPIPE.
  const input = "Hi\n"
  if posix.write(fds[1], input.cstring, input.len) != input.len:
    raise newException(IOError, "cannot write redirected input")
  discard posix.close(fds[1])
  fds[1] = -1
  child = startDemo(binary, inputFd = fds[0], closeFds = [fds[0]])
  discard posix.close(fds[0])
  fds[0] = -1
  awaitDemo(child, 10000)

proc main() =
  if paramCount() == 1 and paramStr(1) in ["-h", "--help"]:
    echo "Usage: record_demo {keys|detect|cursor|decode|redirected} BINARY"
    return
  if paramCount() != 2 or
      paramStr(1) notin ["keys", "detect", "cursor", "decode", "redirected"]:
    raise newException(ValueError,
      "expected a demo mode and binary; use --help for usage")
  let mode = paramStr(1)
  let binary = absolutePath(paramStr(2))
  setControlCHook(requestStop)
  try:
    stdout.write("\e[?25l")
    stdout.flushFile()
    case mode
    of "keys": recordKeys(binary)
    of "redirected": recordRedirected(binary)
    else:
      let args = if mode == "decode": @["--demo"] else: @[]
      var child = startDemo(binary, args)
      defer: stopDemo(child)
      awaitDemo(child, 10000)
    # Hide the recording cursor after the application restores its own state.
    stdout.write("\e[?25l")
    stdout.flushFile()
    for step in 0 ..< 50:
      checkInterrupted()
      sleep(20)
  finally:
    stdout.write("\e[?25h")
    stdout.flushFile()
    when declared(unsetControlCHook):
      unsetControlCHook()

when isMainModule:
  try:
    main()
  except CatchableError as error:
    stderr.writeLine("record_demo: " & error.msg)
    quit(QuitFailure)
