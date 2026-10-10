## Rebuild README casts, GIFs, and PNGs on Linux/macOS.
## Run: nim r scripts/regenerate_media.nim [--font 'Family Name']

when not (defined(linux) or defined(macosx)):
  {.error: "README media regeneration requires Linux or macOS".}

import std/[json, os, osproc, strutils]

const
  root = currentSourcePath().parentDir.parentDir
  defaultFont = "JetBrainsMono Nerd Font Mono"
  demos = [
    ("keys", "read_keys", "Reading keys safely", true),
    ("detect", "detect_terminal", "Terminal detection and geometry", false),
    ("cursor", "cursor_commands", "Cursor control", true),
    ("decode", "decode_input", "Incremental input decoding", true),
    ("redirected", "redirected_input", "Redirected input and EOF", false)]

proc run(command: string; args: varargs[string]) =
  let child = startProcess(command, workingDir = root, args = args,
    options = {poUsePath, poParentStreams})
  defer: child.close()
  let status = child.waitForExit()
  if status != 0:
    raise newException(IOError, command & " failed with exit code " & $status)

proc normalizeCast(castPath, mode, example: string): string =
  var lines = readFile(castPath).strip().splitLines()
  var header = parseJson(lines[0])
  if header["version"].getInt() != 3:
    raise newException(ValueError, "expected asciicast v3: " & castPath)
  header["command"] = %quoteShellCommand(
    ["build/record_demo", mode, "build/" & example])
  header.delete("timestamp")
  header["env"] = %*{"TERM": "xterm-256color"}
  lines[0] = $header
  writeFile(castPath, lines.join("\n") & "\n")

  # v3 timestamps are deltas. Trim the opening blank and final cursor restore.
  var clock = 0.0
  var start = -1.0
  var finish = -1.0
  for line in lines.toOpenArray(1, lines.high):
    let event = parseJson(line)
    clock += event[0].getFloat()
    if event[1].getStr() == "o":
      let data = event[2].getStr()
      if start < 0 and data.replace("\e[?25l", "").strip().len > 0:
        start = clock + 0.02
      if data == "\e[?25h":
        finish = clock - 0.02
  if start < 0 or finish <= start:
    raise newException(IOError, "no complete content interval for " & example)
  result = $start & ".." & $finish

proc main() =
  var font = defaultFont
  let args = commandLineParams()
  var index = 0
  while index < args.len:
    case args[index]
    of "-h", "--help":
      echo "Usage: regenerate_media [--font 'Family Name']"
      echo "Requires Nim, Asciinema 3, Agg, and ImageMagick 7 (magick)."
      return
    of "--font":
      inc index
      if index >= args.len:
        raise newException(ValueError, "--font requires an installed font family")
      font = args[index]
    else:
      if args[index].startsWith("--font="):
        font = args[index][7 .. ^1]
      else:
        raise newException(ValueError, "unknown argument: " & args[index])
    inc index
  if font.len == 0:
    raise newException(ValueError, "font family must not be empty")

  let recordings = root / "docs/recordings"
  let images = root / "docs/images"
  let build = root / "build"
  createDir(recordings)
  createDir(images)
  createDir(build)
  putEnv("TERM", "xterm-256color")
  run("nim", "c", "scripts/record_demo.nim")
  for (mode, example, title, animated) in demos:
    let binary = build / example
    run("nim", "c", "--path:src", "examples/" & example & ".nim")
    let castPath = recordings / (example & ".cast")
    let command = quoteShellCommand([build / "record_demo", mode, binary])
    run("asciinema", "record", "--headless", "--quiet", "--return",
      "--window-size", "64x12", "--capture-env", "TERM", "--title", title,
      "--command", command, "--overwrite", castPath)
    let selection = normalizeCast(castPath, mode, example)
    let gif = (if animated: images else: build) / (example & ".gif")
    run("agg", "--quiet", "--text-font-family", font, "--font-size", "18",
      "--line-height", "1.4", "--renderer", "swash", "--theme", "github-dark",
      "--idle-time-limit", "1", "--last-frame-duration", "2",
      "--select", selection, castPath, gif)
    if not animated:
      run("magick", gif, "-coalesce", "-delete", "0--2",
        images / (example & ".png"))
    echo "Recorded ", example, ": 64x12, ", font, ", swash"

when isMainModule:
  try:
    main()
  except CatchableError as error:
    stderr.writeLine("regenerate_media: " & error.msg)
    quit(QuitFailure)
