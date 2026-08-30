## Windows console state, geometry, and normalized input backend.

import std/[options, os, unicode]
import windows/winlean

import ../types
import ./common

const
  EnableProcessedInput = 0x0001'i32
  EnableLineInput = 0x0002'i32
  EnableEchoInput = 0x0004'i32
  EnableWindowInput = 0x0008'i32
  EnableExtendedFlags = 0x0080'i32
  EnableQuickEditMode = 0x0040'i32
  EnableVirtualTerminalProcessing = 0x0004'i32

  KeyEventType = 0x0001'i16
  VkBack = 0x08'i16
  VkTab = 0x09'i16
  VkReturn = 0x0d'i16
  VkEscape = 0x1b'i16
  VkPrior = 0x21'i16
  VkNext = 0x22'i16
  VkEnd = 0x23'i16
  VkHome = 0x24'i16
  VkLeft = 0x25'i16
  VkUp = 0x26'i16
  VkRight = 0x27'i16
  VkDown = 0x28'i16
  VkInsert = 0x2d'i16
  VkDelete = 0x2e'i16

  RightAltPressed = 0x0001'i32
  LeftAltPressed = 0x0002'i32
  RightCtrlPressed = 0x0004'i32
  LeftCtrlPressed = 0x0008'i32
  ShiftPressed = 0x0010'i32

type
  Coord {.importc: "COORD", header: "<windows.h>".} = object
    x {.importc: "X".}: int16
    y {.importc: "Y".}: int16

  SmallRect {.importc: "SMALL_RECT", header: "<windows.h>".} = object
    left {.importc: "Left".}: int16
    top {.importc: "Top".}: int16
    right {.importc: "Right".}: int16
    bottom {.importc: "Bottom".}: int16

  ConsoleScreenBufferInfo {.importc: "CONSOLE_SCREEN_BUFFER_INFO",
      header: "<windows.h>".} = object
    size {.importc: "dwSize".}: Coord
    cursorPosition {.importc: "dwCursorPosition".}: Coord
    attributes {.importc: "wAttributes".}: int16
    window {.importc: "srWindow".}: SmallRect
    maximumWindowSize {.importc: "dwMaximumWindowSize".}: Coord

  PlatformState* = object
    inputHandle: Handle
    outputHandle: Handle
    originalInputMode: DWORD
    originalOutputMode: DWORD
    inputModeChanged: bool
    outputModeChanged: bool
    inputIsConsole: bool
    pendingHighSurrogate: uint16

proc getConsoleMode(handle: Handle; mode: ptr DWORD): WINBOOL {.
  stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}

proc setConsoleMode(handle: Handle; mode: DWORD): WINBOOL {.
  stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

proc getConsoleScreenBufferInfo(handle: Handle;
    info: ptr ConsoleScreenBufferInfo): WINBOOL {.
  stdcall, dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}

proc getOsfhandle(fileDescriptor: cint): Handle {.
  importc: "_get_osfhandle", header: "<io.h>".}

proc osHandle(file: File): Handle =
  getOsfhandle(cint(file.getFileHandle()))

proc errorText(operation: string): string =
  operation & ": " & osErrorMsg(OSErrorCode(getLastError()))

proc isTerminalPlatform*(file: File): bool =
  var mode: DWORD
  getConsoleMode(file.osHandle(), addr mode) != 0

proc tryTerminalSizePlatform*(file: File): Option[TerminalSize] =
  var info: ConsoleScreenBufferInfo
  if getConsoleScreenBufferInfo(file.osHandle(), addr info) != 0:
    let columns = int(info.window.right - info.window.left + 1)
    let rows = int(info.window.bottom - info.window.top + 1)
    if columns > 0 and rows > 0:
      return some(TerminalSize(columns: columns, rows: rows))
  none(TerminalSize)

proc startPlatform*(input, output: File; enableRaw, enableAnsi: bool): PlatformState =
  result.inputHandle = input.osHandle()
  result.outputHandle = output.osHandle()
  result.inputIsConsole = getConsoleMode(
    result.inputHandle, addr result.originalInputMode) != 0

  if enableRaw:
    if not result.inputIsConsole:
      raise newException(TerminalStateError,
        "cannot enable raw mode on redirected Windows input")
    var mode = result.originalInputMode
    mode = mode and not DWORD(
      EnableProcessedInput or EnableLineInput or EnableEchoInput or
      EnableQuickEditMode
    )
    mode = mode or DWORD(EnableWindowInput or EnableExtendedFlags)
    if setConsoleMode(result.inputHandle, mode) == 0:
      raise newException(TerminalStateError,
        errorText("cannot enable Windows raw mode"))
    result.inputModeChanged = true

  if enableAnsi and getConsoleMode(
      result.outputHandle, addr result.originalOutputMode) != 0:
    let mode = result.originalOutputMode or
      DWORD(EnableVirtualTerminalProcessing)
    if setConsoleMode(result.outputHandle, mode) == 0:
      if result.inputModeChanged:
        discard setConsoleMode(result.inputHandle, result.originalInputMode)
        result.inputModeChanged = false
      raise newException(TerminalStateError,
        errorText("cannot enable Windows virtual terminal output"))
    result.outputModeChanged = true

proc restorePlatform*(state: var PlatformState) =
  var firstError = ""
  if state.outputModeChanged:
    state.outputModeChanged = false
    if setConsoleMode(state.outputHandle, state.originalOutputMode) == 0:
      firstError = errorText("cannot restore Windows output mode")
  if state.inputModeChanged:
    state.inputModeChanged = false
    if setConsoleMode(state.inputHandle, state.originalInputMode) == 0 and
        firstError.len == 0:
      firstError = errorText("cannot restore Windows input mode")
  if firstError.len > 0:
    raise newException(TerminalStateError, firstError)

proc modifiers(controlState: DWORD): set[Modifier] =
  if (controlState and ShiftPressed) != 0:
    result.incl(modifierShift)
  if (controlState and (LeftAltPressed or RightAltPressed)) != 0:
    result.incl(modifierAlt)
  if (controlState and (LeftCtrlPressed or RightCtrlPressed)) != 0:
    result.incl(modifierCtrl)

proc translateKey(state: var PlatformState;
                  record: KEY_EVENT_RECORD): Option[InputEvent] =
  let mods = modifiers(record.dwControlKeyState)
  let virtualKey = record.wVirtualKeyCode
  let character = uint16(record.uChar)

  if character == 3'u16:
    return some(keyInput(keyCtrlC, modifiers = mods + {modifierCtrl}))
  if character == 4'u16:
    return some(keyInput(keyCtrlD, modifiers = mods + {modifierCtrl}))

  let key = case virtualKey
    of VkBack: keyBackspace
    of VkTab:
      if modifierShift in mods: keyBacktab else: keyTab
    of VkReturn: keyEnter
    of VkEscape: keyEscape
    of VkPrior: keyPageUp
    of VkNext: keyPageDown
    of VkEnd: keyEnd
    of VkHome: keyHome
    of VkLeft: keyArrowLeft
    of VkUp: keyArrowUp
    of VkRight: keyArrowRight
    of VkDown: keyArrowDown
    of VkInsert: keyInsert
    of VkDelete: keyDelete
    else: keyUnknown

  if key != keyUnknown:
    return some(keyInput(key, modifiers = mods))
  if character == uint16(ord(' ')):
    return some(keyInput(keySpace, text = " ", modifiers = mods))
  if character in 1'u16 .. 26'u16:
    return some(keyInput(
      keyText,
      text = $char(ord('a') + int(character) - 1),
      modifiers = mods + {modifierCtrl}
    ))
  if character in 0xd800'u16 .. 0xdbff'u16:
    state.pendingHighSurrogate = character
    return none(InputEvent)
  if character in 0xdc00'u16 .. 0xdfff'u16 and
      state.pendingHighSurrogate != 0'u16:
    let high = int32(state.pendingHighSurrogate) - 0xd800'i32
    let low = int32(character) - 0xdc00'i32
    state.pendingHighSurrogate = 0'u16
    return some(keyInput(
      keyText,
      text = $Rune(0x10000'i32 + (high shl 10) + low),
      modifiers = mods
    ))
  state.pendingHighSurrogate = 0'u16
  if character != 0'u16:
    return some(keyInput(
      keyText,
      text = $Rune(int32(character)),
      modifiers = mods
    ))
  some(keyInput(keyUnknown, modifiers = mods))

proc readPlatform*(state: var PlatformState; timeoutMs: int): PlatformRead =
  let waitTime = if timeoutMs < 0: INFINITE else: int32(timeoutMs)
  let waitResult = waitForSingleObject(state.inputHandle, waitTime)
  if waitResult == WAIT_TIMEOUT:
    return timedOut()
  if waitResult != WAIT_OBJECT_0:
    raise newException(TerminalIOError,
      errorText("cannot wait for Windows terminal input"))

  if state.inputIsConsole:
    while true:
      var record: KEY_EVENT_RECORD
      var count: cint
      if readConsoleInput(state.inputHandle, addr record, 1, addr count) == 0:
        raise newException(TerminalIOError,
          errorText("cannot read Windows console input"))
      if count == 0:
        return timedOut()
      if record.eventType == KeyEventType and record.bKeyDown != 0:
        let event = state.translateKey(record)
        if event.isSome:
          return eventRead(event.get())
        continue
      return timedOut()

  # A decoder belongs to one session, so reading ahead here would make closing
  # that session discard bytes which belong to a later consumer of the File.
  var buffer = newString(1)
  var count: int32
  if readFile(state.inputHandle, addr buffer[0], int32(buffer.len),
      addr count, nil) == 0:
    raise newException(TerminalIOError,
      errorText("cannot read redirected Windows input"))
  if count == 0:
    return inputEnded()
  buffer.setLen(count)
  bytesRead(buffer)
