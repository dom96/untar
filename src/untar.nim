import streams, strutils, os, logging

import untarpkg/gzip

type
  TarFile* = ref object
    dataStream: GzStream

  FileInfo* = object
    filename*: string
    size*: int
    typeflag*: TypeFlag

  TypeFlag* = enum
    NormalFile = '0',
    HardLink = '1',
    SymbolicLink = '2',
    CharacterSpecial = '3',
    BlockSpecial = '4',
    Directory = '5',
    FIFO = '6',
    ContiguousFile = '7',
    MetaData = 'g'

  TarError* = object of Exception

proc newTarFile*(filename: string): TarFile =
  ## Opens a .tar.gz file for reading.
  result = TarFile(dataStream: newGzStream(filename))

proc roundup(x, v: int): int {.inline.} =
  # Stolen from Nim's osalloc.nim
  result = (x + (v-1)) and not (v-1)
  assert(result >= x)

proc toTypeFlag(flag: char): TypeFlag =
  if flag == '\0':
    return NormalFile
  else:
    return TypeFlag(flag)

iterator walk*(tar: TarFile): tuple[info: FileInfo, contents: string] =
  ## Decompresses the tar file and yields each file that is read.
  var previousWasEmpty = false
  while not tar.dataStream.atEnd():
    let header = tar.dataStream.readStr(512)

    # Gather info about the file/dir.
    let filename = header[0 .. 100]
    let fileSize = parseOctInt(header[124 .. 135])
    let typeFlag = header[156]

    # Skip empty records
    if filename[0] == '\0':
      if previousWasEmpty:
        break
      else:
        previousWasEmpty = true
        continue

    # Read the file contents.
    let alignedFileSize = roundup(fileSize, 512)
    let fileContents = tar.dataStream.readStr(alignedFileSize)[0 .. <fileSize]

    # Construct the info object.
    let info = FileInfo(filename: filename, size: fileSize,
                        typeflag: toTypeFlag(typeFlag))
    yield (info, fileContents)

proc extract*(tar: TarFile, directory: string) =
  ## Extracts the files stored in the opened ``TarFile`` into the specified
  ## ``directory``.
  createDir(directory)

  for info, contents in tar.walk():
    # Things to consider regarding `..' and absolutely paths:
    # https://www.gnu.org/software/tar/manual/html_node/absolute.html

    # For now just reject these. TODO: Turn absolute paths into non-absolutes.
    if info.filename.isAbsolute():
      raise newException(TarError, "Rejecting an absolute path: " &
                         info.filename)

    # TODO: This may be incorrect.
    if "/../" in info.filename or r"\..\" in info.filename:
       raise newException(TarError, "Rejecting '..' in path: " & info.filename)

    case info.typeflag
    of NormalFile:
      writeFile(directory / info.filename, contents)
    of Directory:
      createDir(directory / info.filename)
    else:
      warn("Ignoring object of type '$1'" % $info.typeflag)

when isMainModule:
  var file = newTarFile("master.tar.gz")
  removeDir(getCurrentDir() / "extract-test")
  file.extract(getCurrentDir() / "extract-test")