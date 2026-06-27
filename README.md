# BatChmodAS

BatChmodAS has developed a new discontinued BatChmod for Apple Silicon.
Builded with Codex.

## Features

- Native SwiftUI macOS app
- File and folder selection
- Drag and drop files or folders into the window
- Owner and group selection
- Read, write, and execute permission editing
- Recursive permission application for folders
- English and Japanese localization
- Custom app icon
- Release app bundle generation

## Requirements

- macOS 14 or later
- Xcode / Swift toolchain
- Apple Silicon Mac

## Build

Debug build and run:

```bash
./script/build_and_run.sh
```

Release build:

```bash
./script/build_and_run.sh --release
```

The release app is generated at:

```text
dist/BatChmodAS.app
```

## Version

Current release version: `1.0`
