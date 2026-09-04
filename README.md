# Tudor PCB

Tudor PCB is a native SwiftUI and Metal viewer for PCB fabrication packages.
It opens Gerber ZIP archives or extracted layer folders, presents the board as an
interactive 3D object, and calls attention to fabrication details that deserve a
human review.

The macOS app is the primary review workstation. The same source also builds for
iPhone and iPad so a fabrication package can be checked from Files.

## What it understands

- RS-274X Gerber lines, flashes, circular interpolation, regions, dark/clear
  polarity, aperture macros, and panel step-repeat
- Excellon plated and non-plated drill files
- EasyEDA Pro, Eagle, KiCad/X2, and common Altium layer naming
- Direct ZIP opening with size limits and CRC verification (nothing is extracted
  into a temporary directory)
- Multi-contour boards, routed cutouts, and EasyEDA breakaway panel rails

### EasyEDA color silkscreen

EasyEDA's `.FCTS` and `.FCBS` files are not ordinary Gerbers. Their SVG payloads
are AES-GCM encrypted, and the AES material is wrapped to JLCPCB's RSA public
key; only JLCPCB has the private key. Tudor PCB therefore does not claim to
decrypt them. It detects both factory payloads, renders the accompanying normal
silkscreen as a geometrically accurate fallback, and clearly labels the exact
color proof as unavailable.

For exact colors, place `*_top.png` / `*_bottom.png` review images beside the
Gerber ZIP (they are discovered automatically), or use **Color proof options**
to attach the original board-sized top/bottom artwork. Board-sized artwork is
mapped to the main routed board rather than stretched across panel rails.

## Build

```sh
cd swift
xcodegen generate
xcodebuild -project TudorPCB.xcodeproj -scheme TudorPCBMac \
  -destination 'platform=macOS' build
```

The reusable parser and document model have their own tests:

```sh
cd swift/GerberKit
swift test
```

The generated Xcode project is intentionally ignored. Edit `swift/project.yml`,
then regenerate it with XcodeGen.
