# README media

The README uses real output from the programs in `examples/`. Each visual links
to its example and source asciicast; no compiler output is recorded.

| Example | Source recording | Visual |
| --- | --- | --- |
| Key and resize events | [read_keys.cast](read_keys.cast) | [read_keys.gif](../images/read_keys.gif) |
| Detection and geometry | [detect_terminal.cast](detect_terminal.cast) | [detect_terminal.png](../images/detect_terminal.png) |
| Cursor updates | [cursor_commands.cast](cursor_commands.cast) | [cursor_commands.gif](../images/cursor_commands.gif) |
| Incremental decoding | [decode_input.cast](decode_input.cast) | [decode_input.gif](../images/decode_input.gif) |
| Redirected input | [redirected_input.cast](redirected_input.cast) | [redirected_input.png](../images/redirected_input.png) |

## Regenerate

On Linux or macOS, install Nim, Asciinema 3, Agg, ImageMagick 7 (`magick`),
and the `JetBrainsMono Nerd Font Mono` font. From the repository root:

```sh
fc-match 'JetBrainsMono Nerd Font Mono'
nim r scripts/regenerate_media.nim
```

The script replaces the five recordings and five images above. It compiles each
example and the Nim capture driver before capture, and puts binaries,
intermediate GIFs, and Nim caches under `build/`. Use
`nim r scripts/regenerate_media.nim --font 'Family Name'` to select another
installed monospace family explicitly. Both scripts use only Nim's standard
library and OS APIs; Python is not required.

`record_demo.nim` provides finite capture commands. Compile it with
`nim c scripts/record_demo.nim`, then run `build/record_demo MODE build/EXAMPLE`
(see `build/record_demo --help`). The key demo runs in a private
PTY: it waits for the raw-mode prompt, sends `a`, `é`, Up, Ctrl+Left, Enter,
resizes to 60×12, then sends Ctrl+C. Cursor updates run at 180 ms per step;
decoder fragments arrive at 700 ms intervals. Redirected input supplies `Hi`
and a newline through a pipe. These captures do not alter the developer's
terminal. The wrapper hides the recording cursor outside the application and
restores it when capture finishes, fails, times out, or is interrupted with
Ctrl+C; the final restoration is trimmed from media.

## Rendering and validation

- Capture: Asciinema 3.2.1, asciicast v3, headless, 64×12 cells, no keyboard input
  capture, `TERM=xterm-256color`.
- Metadata: title, geometry, and a command referencing `build/`; temporary paths
  and wall-clock timestamps are removed.
- Render: Agg 1.9.0, `JetBrainsMono Nerd Font Mono`, 18 px, line height 1.4,
  `swash`, `github-dark`, idle limit 1 second, final frame 2 seconds.
- Output: 713×328 pixels for every visual. GIFs retain animation; PNGs use the
  final coalesced frame. Rendering starts just after the first content output
  and ends just before the wrapper restores cursor visibility.
- Verified on Linux with Nim 2.2.12: formats and frame counts, coalesced first
  and last frames, text clipping, redraws, cursor artifacts, and blank flashes.
  The GIFs have 8 key-event frames, 14 cursor frames, and 5 decoder frames.

To render an existing recording without rebuilding its example:

```sh
agg --text-font-family 'JetBrainsMono Nerd Font Mono' \
  --font-size 18 --line-height 1.4 --renderer swash --theme github-dark \
  --idle-time-limit 1 --last-frame-duration 2 \
  docs/recordings/read_keys.cast /tmp/read_keys.gif
```

The regeneration script derives a content start time from each recording to
skip its initial blank terminal. Inspect frames after changing the font or
timing:

```sh
file docs/images/read_keys.gif
identify docs/images/read_keys.gif
magick docs/images/read_keys.gif -coalesce /tmp/read-keys-%02d.png
git diff --check
```
