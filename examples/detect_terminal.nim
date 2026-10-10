## Run: nim r --path:src examples/detect_terminal.nim
import std/options
import terminal_screen

let capabilities = detectCapabilities()
echo "Terminal capabilities"
echo "  Input terminal:  ", capabilities.inputIsTerminal
echo "  Output terminal: ", capabilities.outputIsTerminal
echo "  ANSI output:     ", capabilities.supportsAnsi
echo "  Raw input:       ", capabilities.supportsRawMode
echo "  Resize events:   ", capabilities.supportsResizeEvents

let size = tryTerminalSize()
if size.isSome:
  echo "Viewport: ", size.get().columns, " columns x ", size.get().rows, " rows"
else:
  echo "Geometry unavailable; use a non-interactive fallback."
