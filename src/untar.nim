import streams, strutils, os, logging, sequtils

import untar/gzip

type
  TarFile* = ref object
    myDataStream: Stream
    filename: string

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
  result = TarFile(
    myDataStream: nil,
    filename: filename
  )

proc getDataStream(tar: TarFile): Stream =
  if tar.myDataStream.isNil():
    let ext = tar.filename.splitFile().ext
    case ext
    of ".gz":
      tar.myDataStream = newGzStream(tar.filename)
    of ".tar":
      tar.myDataStream = newFileStream(tar.filename, fmRead, 1000)
    else:
      raise newException(TarError, "Unsupported file extension: " & ext)

  return tar.myDataStream

proc roundup(x, v: int): int {.inline.} =
  # Stolen from Nim's osalloc.nim
  result = (x + (v-1)) and not (v-1)
  assert(result >= x)

proc toTypeFlag(flag: char): TypeFlag =
  if flag == '\0':
    return NormalFile
  else:
    return TypeFlag(flag)

proc concatFilename(prefix, filename: string): string =
  ## Concatenates `prefix` and `filename` so that there are no NUL (\0)
  ## bytes in between them.
  if prefix.len == 0: return filename

  var realPrefixLen = 0
  while prefix[realPrefixLen] != '\0':
    realPrefixLen.inc()

  return prefix[0 ..< realPrefixLen] / filename

iterator walk*(tar: TarFile): tuple[info: FileInfo, contents: string] =
  ## Decompresses the tar file and yields each file that is read.
  var previousWasEmpty = false
  var count = 0
  let dataStream = tar.getDataStream()
  while not dataStream.atEnd():
    let header = dataStream.readStr(512)

    # Gather info about the file/dir.
    let filename = header[0 ..< 100]                # name is 100 characters long

    # Skip empty records
    if filename[0] == '\0':
      if previousWasEmpty:
        break
      else:
        previousWasEmpty = true
        continue

    let fileSize = parseOctInt(header[124 .. 134])
    let typeFlag = header[156]

    # U-Star
    # - Filename prefix.
    var filenamePrefix = ""
    if header[257 ..< (257+6)] == "ustar\0":
      filenamePrefix = header[345 ..< (345+155)]

    # Read the file contents.
    let alignedFileSize = roundup(fileSize, 512)
    let fileContents = dataStream.readStr(alignedFileSize)[0 ..< fileSize]

    # Construct the info object.
    let info = FileInfo(filename: concatFilename(filenamePrefix, filename),
                        size: fileSize,
                        typeflag: toTypeFlag(typeFlag))

    # Some tarballs don't have the outer directory defined. So we implicitly
    # yield it.
    if count == 0 and info.typeflag != Directory:
      let dir = info.filename.splitFile().dir
      yield (FileInfo(filename: dir, size: 0, typeFlag: Directory), "")

    count.inc()
    yield (info, fileContents)


  tar.myDataStream.close()
  tar.myDataStream = nil

proc extract*(tar: TarFile, directory: string, skipOuterDirs = true, tempDir: string = "") =
  ## Extracts the files stored in the opened ``TarFile`` into the specified
  ## ``directory``.
  ##
  ## Options
  ## -------
  ##
  ## ``skipOuterDirs`` - If ``true``, the archive's directory structure is not
  ## recreated; all files are deposited in the extraction directory. Similar to
  ## ``unzip``'s ``-j`` flag.

  # Create a temporary directory for us to extract into. This allows us to
  # implement the ``skipOuterDirs`` feature and ensures that no files are
  # extracted into the specified directory if the extraction fails mid-way.
  var tempDir = tempDir
  if tempDir.len == 0:
    tempDir = getTempDir() / "untar-nim"
  removeDir(tempDir)
  createDir(tempDir)

  for info, contents in tar.walk():
    # Things to consider regarding `..' and absolute paths:
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
      writeFile(tempDir / info.filename, contents)
    of Directory:
      createDir(tempDir / info.filename)
    else:
      warn("Ignoring object of type '$1'" % $info.typeflag)

  # Determine which directory to copy.
  var srcDir = tempDir
  let contents = toSeq(walkDir(srcDir))
  if contents.len == 1 and skipOuterDirs:
    # Skip the outer directory.
    srcDir = contents[0][1]

  # Finally copy the directory to what the user specified.
  copyDir(srcDir, directory)

proc close*(tar: TarFile) =
  ## Closes the file stream associated with this tar file.
  if not tar.myDataStream.isNil():
    tar.myDataStream.close()

when isMainModule:
  var file = newTarFile("nim-0.17.0.tar.gz")
  for info, contents in file.walk:
    echo(info)
  removeDir(getCurrentDir() / "extract-test")
  file.extract(getCurrentDir() / "extract-test")
  file.close()
