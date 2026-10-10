#!/usr/bin/env python3
"""Finite README capture driver. Uses a private PTY for scripted key input."""

import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import termios
import time


def record_keys(binary):
    master, slave = pty.openpty()

    def resize(columns):
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 12, columns, 0, 0))

    resize(64)
    child = subprocess.Popen([binary], stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    # Start only after the program has entered raw mode and printed its prompt.
    schedule = [(0.5, b"a"), (1.0, "é".encode()), (1.5, b"\x1b[A"),
                (2.0, b"\x1b[1;5D"), (2.5, b"\r"), (3.0, 60),
                (3.7, b"\x03")]
    ready = None
    pending = b""
    deadline = time.monotonic() + 10
    try:
        while time.monotonic() < deadline:
            now = time.monotonic()
            if ready is not None and schedule and now - ready >= schedule[0][0]:
                _, action = schedule.pop(0)
                if isinstance(action, int):
                    resize(action)
                else:
                    os.write(master, action)
            if select.select([master], [], [], 0.02)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
                pending += data
                if ready is None and b"Press keys" in pending:
                    ready = time.monotonic()
        else:
            raise RuntimeError("key demo did not finish within 10 seconds")
        if child.wait(timeout=2) != 0:
            raise RuntimeError("key demo failed")
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        os.close(master)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["keys", "detect", "cursor", "decode", "redirected"])
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    binary = str(args.binary)
    sys.stdout.write("\x1b[?25l")
    sys.stdout.flush()
    try:
        if args.mode == "keys":
            record_keys(binary)
        elif args.mode == "redirected":
            subprocess.run([binary], input=b"Hi\n", check=True, timeout=10)
        else:
            command = [binary, "--demo"] if args.mode == "decode" else [binary]
            subprocess.run(command, check=True, timeout=10)
        # Hide the recording cursor after the application restores its own state.
        sys.stdout.write("\x1b[?25l")
        sys.stdout.flush()
        time.sleep(1)
    finally:
        sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
