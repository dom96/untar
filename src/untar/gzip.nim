import streams, os

when defined(windows):
  {.compile: ("../zlib/*.c", "zlib_$#.obj").}
  {.pragma: mydyn.}
elif defined(macosx):
  const libz = "libz.dylib"
  {.pragma: mydyn, dynlib: libz.}
else:
  const libz = "libz.so(|.0)"
  {.pragma: mydyn, dynlib: libz.}

type
  GzFilePtr = pointer

const Z_ERRNO = -1

# gzopen does not support Unicode paths on Windows,
# so use gzdopen instead
proc gzdopen(fd: cint, mode: cstring): GzFilePtr {.cdecl,
  importc: "gzdopen", mydyn.}

proc gzread(thefile: GzFilePtr, buf: pointer, length: cint): int32 {.cdecl,
  importc: "gzread", mydyn.}

proc gzseek*(thefile: GzFilePtr, offset: int32, whence: int32): int32 {.cdecl,
  importc, mydyn.}

proc gzeof(thefile: GzFilePtr): int {.cdecl, importc, mydyn.}
proc gzclose(thefile: GzFilePtr): int32 {.cdecl, importc, mydyn.}
proc gzerror(thefile: GzFilePtr, errnum: ptr cint): cstring
  {.cdecl, importc, mydyn.}

type
  GzStream* = ref object of Stream
    handle: GzFilePtr
    pos: int
    isAtEnd: bool

  ZlibError* = object of Exception

proc checkZlibError(ret: cint, handle: GzFilePtr) =
  if ret == Z_ERRNO:
    var errnum: cint
    let msg = gzerror(handle, addr errnum)
    if errnum == Z_ERRNO:
      raiseOSError(osLastError())
    else:
      raise newException(ZlibError, "Zlib call didn't return Z_OK. " &
                         "Error was: " & $msg & ". Errnum: " & $errnum)

proc gzAtEnd(s: Stream): bool =
  var s = GzStream(s)
  result = s.isAtEnd

proc gzGetPosition(s: Stream): int =
  var s = GzStream(s)
  return s.pos

proc gzReadData(s: Stream, buffer: pointer, bufLen: int): int =
  if bufLen == 0: return 0
  var s = GzStream(s)
  let ret = gzread(s.handle, buffer, bufLen.cint)
  checkZlibError ret, s.handle
  s.pos.inc(ret)
  s.isAtEnd = ret == 0

  return ret

proc gzClose(s: Stream) =
  var s = GzStream(s)
  checkZlibError gzclose(s.handle), s.handle
  s.handle = nil

proc newGzStream*(filename: string): GzStream =
  ## creates a new stream for the GZ-compressed file located at ``filename``.
  new(result)
  let
    file = open(filename)
    fd = file.getFileHandle()
    handle = gzdopen(fd, "r")
  if handle == nil:
    close(file)
    raise newException(ZlibError, "Cannot open the GZ File")
  result.handle = handle
  result.pos = 0
  result.closeImpl = gzClose
  result.atEndImpl = gzAtEnd
  result.getPositionImpl = gzGetPosition
  result.readDataImpl = gzReadData
