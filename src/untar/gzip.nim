import streams

{.passl: "-lz".}

type
  GzFilePtr = pointer

const Z_ERRNO = -1

proc gzopen(path: cstring, mode: cstring): GzFilePtr {.cdecl,
  importc: "gzopen".}

proc gzread(thefile: GzFilePtr, buf: pointer, length: int): int32 {.cdecl,
  importc: "gzread".}

proc gzseek*(thefile: GzFilePtr, offset: int32, whence: int32): int32 {.cdecl,
  importc.}

proc gzeof(thefile: GzFilePtr): int {.cdecl, importc.}
proc gzclose(thefile: GzFilePtr): int32 {.cdecl, importc.}

type
  GzStream* = ref object of Stream
    handle: GzFilePtr
    pos: int
    isAtEnd: bool

  ZlibError* = object of Exception

proc checkZlibError(ret: cint) =
  if ret == Z_ERRNO:
    raise newException(ZlibError, "Zlib call didn't return Z_OK")

proc gzAtEnd(s: Stream): bool =
  var s = GzStream(s)
  result = s.isAtEnd

proc gzGetPosition(s: Stream): int =
  var s = GzStream(s)
  return s.pos

proc gzReadData(s: Stream, buffer: pointer, bufLen: int): int =
  if bufLen == 0: return 0
  var s = GzStream(s)
  let ret = gzread(s.handle, buffer, bufLen)
  checkZlibError ret
  s.pos.inc(ret)
  s.isAtEnd = ret == 0

  return ret

proc gzClose(s: Stream) =
  var s = GzStream(s)
  checkZlibError gzclose(s.handle)
  s.handle = nil

proc newGzStream*(filename: string): GzStream =
  ## creates a new stream for the GZ-compressed file located at ``filename``.
  new(result)
  result.handle = gzopen(filename, "r")
  result.pos = 0
  result.closeImpl = gzClose
  result.atEndImpl = gzAtEnd
  result.getPositionImpl = gzGetPosition
  result.readDataImpl = gzReadData