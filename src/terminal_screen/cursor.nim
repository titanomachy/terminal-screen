## Pure ANSI cursor commands and explicit stream-writing helpers.

const
  HideCursorCode* = "\e[?25l"
    ## ANSI sequence that hides the cursor.
  ShowCursorCode* = "\e[?25h"
    ## ANSI sequence that shows the cursor.

proc positive(value: int; name: string) =
  if value <= 0:
    raise newException(ValueError, name & " must be greater than zero")

proc cursorPositionCode*(column, row: int): string =
  ## Returns an absolute, one-based cursor-position command.
  positive(column, "column")
  positive(row, "row")
  "\e[" & $row & ";" & $column & "H"

proc cursorUpCode*(count = 1): string =
  ## Returns a relative cursor-up command.
  positive(count, "count")
  "\e[" & $count & "A"

proc cursorDownCode*(count = 1): string =
  ## Returns a relative cursor-down command.
  positive(count, "count")
  "\e[" & $count & "B"

proc cursorForwardCode*(count = 1): string =
  ## Returns a relative cursor-forward command.
  positive(count, "count")
  "\e[" & $count & "C"

proc cursorBackwardCode*(count = 1): string =
  ## Returns a relative cursor-backward command.
  positive(count, "count")
  "\e[" & $count & "D"

proc cursorColumnCode*(column: int): string =
  ## Returns a one-based absolute column command.
  positive(column, "column")
  "\e[" & $column & "G"

proc writeControl*(output: File; code: string; flush = false) =
  ## Writes one control sequence to `output` and optionally flushes it.
  output.write(code)
  if flush:
    output.flushFile()

proc hideCursor*(output: File = stdout; flush = false) =
  ## Hides the cursor on `output`.
  output.writeControl(HideCursorCode, flush)

proc showCursor*(output: File = stdout; flush = false) =
  ## Shows the cursor on `output`.
  output.writeControl(ShowCursorCode, flush)

proc moveCursorTo*(column, row: int; output: File = stdout; flush = false) =
  ## Moves the cursor to a one-based column and row.
  output.writeControl(cursorPositionCode(column, row), flush)

proc moveCursorUp*(count = 1; output: File = stdout; flush = false) =
  ## Moves the cursor up by `count` rows.
  output.writeControl(cursorUpCode(count), flush)

proc moveCursorDown*(count = 1; output: File = stdout; flush = false) =
  ## Moves the cursor down by `count` rows.
  output.writeControl(cursorDownCode(count), flush)

proc moveCursorForward*(count = 1; output: File = stdout; flush = false) =
  ## Moves the cursor forward by `count` columns.
  output.writeControl(cursorForwardCode(count), flush)

proc moveCursorBackward*(count = 1; output: File = stdout; flush = false) =
  ## Moves the cursor backward by `count` columns.
  output.writeControl(cursorBackwardCode(count), flush)

proc moveCursorToColumn*(column: int; output: File = stdout; flush = false) =
  ## Moves the cursor to a one-based absolute column.
  output.writeControl(cursorColumnCode(column), flush)
