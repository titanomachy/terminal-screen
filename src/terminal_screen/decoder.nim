## Incremental, platform-neutral terminal input decoding.

import std/[options, strutils]

import ./types

type
  InputDecoder* = object
    ## Incremental decoder for UTF-8, control bytes, and ANSI key sequences.
    buffer: string
    finished: bool
    eofEmitted: bool

proc initInputDecoder*(): InputDecoder =
  ## Creates an empty input decoder.
  InputDecoder()

proc feed*(decoder: var InputDecoder; data: openArray[char]) =
  ## Adds bytes to `decoder`.
  ##
  ## Feeding data after `finish` is a programming error.
  if decoder.finished:
    raise newException(ValueError, "cannot feed a finished input decoder")
  for value in data:
    decoder.buffer.add(value)

proc finish*(decoder: var InputDecoder) =
  ## Marks the byte stream as ended.
  decoder.finished = true

proc hasPendingInput*(decoder: InputDecoder): bool =
  ## Returns whether undecoded bytes remain buffered.
  decoder.buffer.len > 0

proc hasPendingEscape*(decoder: InputDecoder): bool =
  ## Returns whether the decoder is waiting on an Escape-prefixed sequence.
  decoder.buffer.len > 0 and decoder.buffer[0] == '\e'

proc utf8Length(first: uint8): int =
  if first <= 0x7f'u8: 1
  elif first in 0xc2'u8 .. 0xdf'u8: 2
  elif first in 0xe0'u8 .. 0xef'u8: 3
  elif first in 0xf0'u8 .. 0xf4'u8: 4
  else: 0

proc validContinuation(buffer: string; length: int): bool =
  if buffer.len < length:
    return false
  for index in 1 ..< length:
    if (uint8(buffer[index]) and 0xc0'u8) != 0x80'u8:
      return false
  if length == 3:
    let first = uint8(buffer[0])
    let second = uint8(buffer[1])
    if first == 0xe0'u8 and second < 0xa0'u8: return false
    if first == 0xed'u8 and second >= 0xa0'u8: return false
  elif length == 4:
    let first = uint8(buffer[0])
    let second = uint8(buffer[1])
    if first == 0xf0'u8 and second < 0x90'u8: return false
    if first == 0xf4'u8 and second >= 0x90'u8: return false
  true

proc consume(decoder: var InputDecoder; count: int): string =
  result = decoder.buffer[0 ..< count]
  decoder.buffer.delete(0 ..< count)

proc modifiersFromParameter(value: int): set[Modifier] =
  let flags = value - 1
  if (flags and 1) != 0: result.incl(modifierShift)
  if (flags and 2) != 0: result.incl(modifierAlt)
  if (flags and 4) != 0: result.incl(modifierCtrl)

proc parseParameters(body: string): seq[int] =
  if body.len == 0:
    return @[]
  for part in body.split(';'):
    if part.len == 0:
      result.add(0)
    else:
      try:
        result.add(parseInt(part))
      except ValueError:
        return @[]

proc decodeCsi(sequence: string): InputEvent =
  let final = sequence[^1]
  let body = sequence[2 ..< sequence.high]
  let parameters = parseParameters(body)
  var modifiers: set[Modifier]

  case final
  of 'A', 'B', 'C', 'D', 'H', 'F':
    if parameters.len >= 2:
      modifiers = modifiersFromParameter(parameters[^1])
    let key = case final
      of 'A': keyArrowUp
      of 'B': keyArrowDown
      of 'C': keyArrowRight
      of 'D': keyArrowLeft
      of 'H': keyHome
      else: keyEnd
    keyInput(key, modifiers = modifiers, sequence = sequence)
  of 'Z':
    keyInput(keyBacktab, modifiers = {modifierShift}, sequence = sequence)
  of '~':
    if parameters.len == 0:
      return keyInput(keyUnknown, sequence = sequence)
    if parameters.len >= 2:
      modifiers = modifiersFromParameter(parameters[^1])
    let key = case parameters[0]
      of 1, 7: keyHome
      of 2: keyInsert
      of 3: keyDelete
      of 4, 8: keyEnd
      of 5: keyPageUp
      of 6: keyPageDown
      else: keyUnknown
    keyInput(key, modifiers = modifiers, sequence = sequence)
  else:
    keyInput(keyUnknown, sequence = sequence)

proc decodeSs3(sequence: string): InputEvent =
  let key = case sequence[^1]
    of 'A': keyArrowUp
    of 'B': keyArrowDown
    of 'C': keyArrowRight
    of 'D': keyArrowLeft
    of 'H': keyHome
    of 'F': keyEnd
    else: keyUnknown
  keyInput(key, sequence = sequence)

proc decodeControl(value: char): InputEvent =
  if value in {'\r', '\n'}:
    keyInput(keyEnter, sequence = $value)
  elif value == '\t':
    keyInput(keyTab, sequence = $value)
  elif value in {'\b', '\x7f'}:
    keyInput(keyBackspace, sequence = $value)
  elif value == '\x03':
    keyInput(keyCtrlC, modifiers = {modifierCtrl}, sequence = $value)
  elif value == '\x04':
    keyInput(keyCtrlD, modifiers = {modifierCtrl}, sequence = $value)
  elif value in {'\x01' .. '\x1a'}:
    keyInput(
      keyText,
      text = $(char(ord('a') + ord(value) - 1)),
      modifiers = {modifierCtrl},
      sequence = $value
    )
  else:
    keyInput(keyUnknown, sequence = $value)

proc decodePlain(decoder: var InputDecoder; extraModifiers: set[Modifier] = {};
                 prefix = ""): Option[InputEvent] =
  if decoder.buffer.len == 0:
    return none(InputEvent)

  let first = uint8(decoder.buffer[0])
  if first < 0x20'u8 or first == 0x7f'u8:
    var event = decodeControl(decoder.consume(1)[0])
    event.keyEvent.modifiers = event.keyEvent.modifiers + extraModifiers
    event.keyEvent.sequence = prefix & event.keyEvent.sequence
    return some(event)

  if first == uint8(' '):
    let value = decoder.consume(1)
    return some(keyInput(keySpace, text = value,
      modifiers = extraModifiers, sequence = prefix & value))

  let length = utf8Length(first)
  if length == 0:
    let invalid = decoder.consume(1)
    return some(keyInput(keyUnknown, modifiers = extraModifiers,
      sequence = prefix & invalid))
  if decoder.buffer.len < length:
    if not decoder.finished:
      return none(InputEvent)
    let incomplete = decoder.consume(1)
    return some(keyInput(keyUnknown, modifiers = extraModifiers,
      sequence = prefix & incomplete))
  if not validContinuation(decoder.buffer, length):
    let invalid = decoder.consume(1)
    return some(keyInput(keyUnknown, modifiers = extraModifiers,
      sequence = prefix & invalid))

  let value = decoder.consume(length)
  some(keyInput(keyText, text = value, modifiers = extraModifiers,
    sequence = prefix & value))

proc nextEvent*(decoder: var InputDecoder; flushEscape = false): Option[InputEvent] =
  ## Decodes the next complete event, if available.
  ##
  ## A lone Escape is intentionally ambiguous. Pass `flushEscape = true` after
  ## the caller's short Escape timeout expires. Once `finish` has been called,
  ## pending incomplete input is flushed automatically and exactly one
  ## `eventEndOfInput` is emitted after it.
  if decoder.buffer.len == 0:
    if decoder.finished and not decoder.eofEmitted:
      decoder.eofEmitted = true
      return some(endOfInput())
    return none(InputEvent)

  if decoder.buffer[0] != '\e':
    return decoder.decodePlain()

  if decoder.buffer.len == 1:
    if flushEscape or decoder.finished:
      discard decoder.consume(1)
      return some(keyInput(keyEscape, sequence = "\e"))
    return none(InputEvent)

  if decoder.buffer[1] == '[':
    var finalIndex = -1
    for index in 2 ..< decoder.buffer.len:
      let value = ord(decoder.buffer[index])
      if value >= 0x40 and value <= 0x7e:
        finalIndex = index
        break
    if finalIndex < 0:
      if not (flushEscape or decoder.finished) and decoder.buffer.len <= 64:
        return none(InputEvent)
      let unknown = decoder.consume(min(decoder.buffer.len, 64))
      return some(keyInput(keyUnknown, sequence = unknown))
    return some(decodeCsi(decoder.consume(finalIndex + 1)))

  if decoder.buffer[1] == 'O':
    if decoder.buffer.len < 3:
      if not (flushEscape or decoder.finished):
        return none(InputEvent)
      let unknown = decoder.consume(decoder.buffer.len)
      return some(keyInput(keyUnknown, sequence = unknown))
    return some(decodeSs3(decoder.consume(3)))

  discard decoder.consume(1)
  let oldFinished = decoder.finished
  let decoded = decoder.decodePlain({modifierAlt}, "\e")
  if decoded.isNone and (flushEscape or oldFinished):
    return some(keyInput(keyEscape, sequence = "\e"))
  decoded
