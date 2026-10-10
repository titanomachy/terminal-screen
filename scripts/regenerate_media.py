#!/usr/bin/env python3
"""Rebuild README casts, GIFs, and PNGs on Linux/macOS; requires Nim and media tools."""

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
FONT = "JetBrainsMono Nerd Font Mono"
DEMOS = {
    "keys": ("read_keys", "Reading keys safely", True),
    "detect": ("detect_terminal", "Terminal detection and geometry", False),
    "cursor": ("cursor_commands", "Cursor control", True),
    "decode": ("decode_input", "Incremental input decoding", True),
    "redirected": ("redirected_input", "Redirected input and EOF", False),
}


def run(*args):
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    subprocess.run(args, cwd=ROOT, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", default=FONT, help="exact installed monospace family")
    args = parser.parse_args()
    recordings = ROOT / "docs/recordings"
    images = ROOT / "docs/images"
    recordings.mkdir(parents=True, exist_ok=True)
    images.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="terminal-screen-media-") as temp:
        for mode, (example, title, animated) in DEMOS.items():
            binary = Path(temp) / example
            run("nim", "c", "--path:src", f"--out:{binary}", f"examples/{example}.nim")
            cast = recordings / f"{example}.cast"
            command = shlex.join(["python3", "scripts/record_demo.py", mode, str(binary)])
            run("asciinema", "record", "--headless", "--quiet", "--return",
                "--window-size", "64x12", "--capture-env", "TERM", "--title", title,
                "--command", command, "--overwrite", str(cast))
            # Keep reproducible command metadata without a disposable directory name.
            lines = cast.read_text().splitlines()
            header = json.loads(lines[0])
            header["command"] = shlex.join([
                "python3", "scripts/record_demo.py", mode, f"build/{example}"])
            header.pop("timestamp", None)
            header["env"] = {"TERM": "xterm-256color"}
            lines[0] = json.dumps(header)
            cast.write_text("\n".join(lines) + "\n")
            # Start after the first complete output; no blank opening frame.
            clock = 0.0
            start = None
            end = None
            for line in lines[1:]:
                delta, kind, data = json.loads(line)
                clock += delta
                if (start is None and kind == "o" and
                        data.replace("\x1b[?25l", "").strip()):
                    start = clock + 0.02
                if kind == "o" and data == "\x1b[?25h":
                    end = clock - 0.02
            if start is None or end is None or end <= start:
                raise RuntimeError(f"no complete content interval for {example}")
            gif = images / f"{example}.gif" if animated else Path(temp) / f"{example}.gif"
            run("agg", "--quiet", "--text-font-family", args.font, "--font-size", "18",
                "--line-height", "1.4", "--renderer", "swash", "--theme", "github-dark",
                "--idle-time-limit", "1", "--last-frame-duration", "2",
                "--select", f"{start}..{end}", str(cast), str(gif))
            if not animated:
                run("magick", str(gif), "-coalesce", "-delete", "0--2",
                    str(images / f"{example}.png"))
            print(f"Recorded {example}: 64x12, {args.font}, swash", flush=True)


if __name__ == "__main__":
    main()
