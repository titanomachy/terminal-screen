## Keep every compiler product under the package build directory.
import std/os

let buildDir = thisDir() / "build"
switch("outDir", buildDir)
switch("nimcache", buildDir / "nimcache" / ("nim-" & NimVersion))

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
