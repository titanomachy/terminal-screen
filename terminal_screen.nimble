# Package

version       = "0.1.0"
author        = "titanomachy"
description   = "Pure-Nim terminal sessions, input events, cursor control, and geometry detection"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"


# Tasks

task compilePackage, "Compile terminal_screen into the build directory":
  exec "nim c --path:src src/terminal_screen.nim"

task test, "Run the terminal_screen test suite":
  exec "nim c --path:src tests/pty_process_helper.nim"
  exec "nim c -r --path:src tests/test_terminal_screen.nim"

task examples, "Check that all terminal_screen examples compile":
  exec "nim check --path:src examples/read_keys.nim"
  exec "nim check --path:src examples/cursor_commands.nim"

task docs, "Generate terminal_screen API documentation":
  exec "nim doc --project --index:on --outdir:build/docs --path:src src/terminal_screen.nim"

task releaseCheck, "Run the local release-readiness checks":
  exec "nimble check"
  exec "nimble compilePackage"
  exec "nimble test"
  exec "nimble examples"
  exec "nimble docs"
