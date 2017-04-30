# untar

This library does one and only one thing very well, it decompresses and
extracts .tar.gz archives.

## Installation

```
nimble install untar
```

## Usage

```nim
import os
import untar

var file = newTarFile("file.tar.gz")
file.extract(getCurrentDir() / "extracted-files")
```

## Dependencies

This package aims to have as few dependencies as possible. The ``zlib`` library
is the only dependency.

## License

MIT