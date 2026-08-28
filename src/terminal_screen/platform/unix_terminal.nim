## POSIX terminal state, geometry, and byte input backend.

import std/[options, os, posix, termios]

import ../types
import ./common

type
  PlatformState* = object
    inputFd: cint
    originalMode: Termios
    rawEnabled: bool

proc errorText(operation: string): string =
  operation & ": " & osErrorMsg(osLastError())

proc isTerminalPlatform*(file: File): bool =
  posix.isatty(cint(file.getFileHandle())) != 0

proc tryTerminalSizePlatform*(file: File): Option[TerminalSize] =
  var size: IOctl_WinSize
  if ioctl(cint(file.getFileHandle()), TIOCGWINSZ, addr size) == 0 and
      size.ws_col > 0 and size.ws_row > 0:
    return some(TerminalSize(columns: int(size.ws_col), rows: int(size.ws_row)))
  none(TerminalSize)

proc startPlatform*(input, output: File; enableRaw, enableAnsi: bool): PlatformState =
  ## Captures and optionally changes the terminal input mode.
  discard output
  discard enableAnsi
  result.inputFd = cint(input.getFileHandle())
  if not enableRaw:
    return

  if tcGetAttr(result.inputFd, addr result.originalMode) != 0:
    raise newException(TerminalStateError, errorText("cannot read terminal mode"))

  var rawMode = result.originalMode
  rawMode.c_iflag = rawMode.c_iflag and not Cflag(
    BRKINT or ICRNL or INPCK or ISTRIP or IXON
  )
  rawMode.c_oflag = rawMode.c_oflag and not Cflag(OPOST)
  rawMode.c_cflag = (rawMode.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
  rawMode.c_lflag = rawMode.c_lflag and not Cflag(
    ECHO or ICANON or IEXTEN or ISIG
  )
  rawMode.c_cc[VMIN] = char(1)
  rawMode.c_cc[VTIME] = char(0)

  if tcSetAttr(result.inputFd, TCSANOW, addr rawMode) != 0:
    raise newException(TerminalStateError, errorText("cannot enable raw mode"))
  result.rawEnabled = true

proc restorePlatform*(state: var PlatformState) =
  ## Restores the exact termios snapshot captured by `startPlatform`.
  if state.rawEnabled:
    state.rawEnabled = false
    if tcSetAttr(state.inputFd, TCSANOW, addr state.originalMode) != 0:
      raise newException(TerminalStateError,
        errorText("cannot restore terminal mode"))

proc readPlatform*(state: var PlatformState; timeoutMs: int): PlatformRead =
  ## Waits for and reads a bounded chunk of terminal bytes.
  var descriptor = TPollfd(
    fd: state.inputFd,
    events: POLLIN,
    revents: 0
  )
  let ready = posix.poll(addr descriptor, Tnfds(1), cint(timeoutMs))
  if ready == 0:
    return timedOut()
  if ready < 0:
    if osLastError() == OSErrorCode(EINTR):
      return timedOut()
    raise newException(TerminalIOError, errorText("cannot poll terminal input"))

  var buffer = newString(64)
  let count = posix.read(state.inputFd, addr buffer[0], buffer.len)
  if count == 0:
    return inputEnded()
  if count < 0:
    if osLastError() == OSErrorCode(EINTR):
      return timedOut()
    raise newException(TerminalIOError, errorText("cannot read terminal input"))
  buffer.setLen(count)
  bytesRead(buffer)
