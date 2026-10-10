## Internal, non-blocking access to bytes already retained by a borrowed File.

import std/options

import ../types
import ./common

# ISO C has no buffered-byte query. Keep the CRT-specific probe here, using
# header-declared fields or accessors rather than assuming FILE memory offsets.
# Never call getc on an empty buffer: that would read ahead or block a timeout.
{.emit: """
#include <stdio.h>
#if defined(__linux__) && !defined(__GLIBC__)
#include <stdio_ext.h>
#endif
#if defined(_UCRT) || (defined(_MSC_VER) && _MSC_VER >= 1900)
#ifdef __cplusplus
extern "C" {
#endif
extern int __cdecl _get_stream_buffer_pointers(FILE *, char ***, char ***, int **);
#ifdef __cplusplus
}
#endif
#endif
static int terminalScreenHasBufferedInput(FILE *stream) {
#if defined(__GLIBC__)
  return stream->_IO_read_ptr < stream->_IO_read_end;
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
  return stream->_r > 0;
#elif defined(_UCRT) || (defined(_MSC_VER) && _MSC_VER >= 1900)
  char **base, **position;
  int *remaining;
  return _get_stream_buffer_pointers(stream, &base, &position, &remaining) == 0
      && remaining != NULL && *remaining > 0;
#elif defined(_WIN32)
  return stream->_cnt > 0;
#elif defined(__linux__)
  return __freadahead(stream) > 0;
#else
#error Unsupported C runtime for buffered terminal input
#endif
}
""".}

proc hasBufferedInput(input: File): cint {.
  importc: "terminalScreenHasBufferedInput", nodecl.}

proc readBufferedInput*(input: File): Option[PlatformRead] =
  ## Consumes one byte only when it is already in the File's buffer.
  if hasBufferedInput(input) == 0:
    return none(PlatformRead)
  try:
    return some(bytesRead($input.readChar()))
  except IOError as error:
    raise newException(TerminalIOError,
      "cannot read buffered terminal input: " & error.msg)
