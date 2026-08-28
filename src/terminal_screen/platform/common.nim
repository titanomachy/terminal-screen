## Internal values exchanged between platform backends and the session layer.

import ../types

type
  PlatformReadKind* = enum
    platformTimeout
    platformBytes
    platformEvent
    platformEndOfInput

  PlatformRead* = object
    case kind*: PlatformReadKind
    of platformBytes:
      data*: string
    of platformEvent:
      event*: InputEvent
    of platformTimeout, platformEndOfInput:
      discard

proc timedOut*(): PlatformRead =
  PlatformRead(kind: platformTimeout)

proc bytesRead*(data: string): PlatformRead =
  PlatformRead(kind: platformBytes, data: data)

proc eventRead*(event: InputEvent): PlatformRead =
  PlatformRead(kind: platformEvent, event: event)

proc inputEnded*(): PlatformRead =
  PlatformRead(kind: platformEndOfInput)
