# Gerber Metal

Gerber Metal is a native SwiftUI and Metal viewer for PCB fabrication packages.
It opens Gerber ZIP archives or extracted layer folders, presents the board as an
interactive 3D object, and calls attention to fabrication details that deserve a
human review.

The macOS app is the primary review workstation. The same source also builds for
iPhone and iPad so a fabrication package can be checked from Files.

## Build

```sh
cd swift
xcodegen generate
xcodebuild -project GerberMetal.xcodeproj -scheme GerberMetalMac \
  -destination 'platform=macOS' build
```

The reusable parser and document model have their own tests:

```sh
cd swift/GerberKit
swift test
```

The generated Xcode project is intentionally ignored. Edit `swift/project.yml`,
then regenerate it with XcodeGen.

