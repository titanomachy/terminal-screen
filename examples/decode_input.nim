## Run: nim r --path:src examples/decode_input.nim
## Add --demo for paced output, or --help for usage.
import std/[options, os]
import terminal_screen

if "--help" in commandLineParams():
  echo "Usage: decode_input [--demo]"
  quit(0)

let demo = "--demo" in commandLineParams()
var decoder = initInputDecoder()
let fragments = ["\xC3", "\xA9\e[", "A", "\e[1;5D"]
let labels = ["\\xC3", "\\xA9\\e[", "A", "\\e[1;5D"]

echo "Incremental decoding / UTF-8 and escape sequences"
for index, fragment in fragments:
  echo "feed \"", labels[index], "\""
  decoder.feed(fragment)
  var emitted = false
  while true:
    let event = decoder.nextEvent()
    if event.isNone:
      break
    let key = event.get().keyEvent
    echo "  -> ", key.key, " text=\"", key.text, "\" modifiers=", key.modifiers
    emitted = true
  if not emitted:
    echo "  -> waiting for more bytes"
  if demo:
    sleep(700)

decoder.finish()
echo "finish -> ", decoder.nextEvent().get().kind
if demo:
  sleep(800)
