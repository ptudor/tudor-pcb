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
- JLCPCB production-review envelopes and safely nested fabrication ZIPs
- Multi-contour boards, routed cutouts, and EasyEDA breakaway panel rails
- Persistent fabrication history with source age, first/last inspection times,
  board statistics, generator details, search, and secure quick reopen

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

### JLCPCB production reviews

Open the downloaded review ZIP or its extracted folder directly. Tudor PCB uses
the engineer-produced Gerbers in `ok/`, recognizes JLCCam's extensionless layer
names, ignores the `.ddw` and `.tgz` helper files, and records ZIPs in `YG/` as
the enclosed original uploads. Generic nested ZIPs are searched up to three
levels deep with archive-count and expanded-size limits. A unique best board is
opened automatically; equally plausible boards are reported for explicit user
choice instead of choosing one silently.

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

For zero-width routed outline strokes, raster mask inference uses a 0.7-pixel
barrier solely to infer board fill. Copper strokes keep their physical width;
zero-size copper is invisible. The 3D mesh uses the specified board thickness
without display exaggeration. Rendering rejects nonfinite/reversed bounds,
nonpositive thickness, and dimensions outside the supported 0.000001–1000000 mm
range with a recoverable geometry error.

Aperture macros retain their definitions until ADD instantiation. Supported macro
primitives are circles (1), vector lines (2/20), outlines (4), polygons (5),
thermals (7), and rectangles (21/22), with checked parameter expressions and
ordered local dark/clear composition. Unsupported instantiated primitives reject
the layer with a diagnostic. Aperture holes remain transparent to previous layer
geometry. Codable retains all existing shape cases and adds `compound`; old
payloads still decode, while older readers must reject the new case rather than
substituting geometry. Reference semantics: [Ucamco Gerber specification, sections
4.4–4.5](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf).

Excellon coordinates support explicit decimals (including EasyEDA/XNC), G90/G91
and ICI modes, declared integer/fractional precision, Altium `FILE_FORMAT`, and
KiCad `FORMAT` comments. LZ/TZ use the CNC-7/KiCad **retained-zero** convention:
LZ retains leading zeros; TZ retains trailing zeros. This matches
[KiCad's exporter](https://docs.kicad.org/doxygen/gendrill__excellon__writer_8cpp_source.html).
Integer coordinates without enough format information are rejected with an
explicit diagnostic; export explicit decimals or include a recognized declaration.
A present drill map does not establish alignment.

Layer roles prefer structured Gerber `FileFunction` attributes, then recognized
JLCCam basenames, established extensions, and finally basename keywords. Conflicts
with filename roles produce warnings. Parent directory names never assign roles;
Gerber and Excellon syntax are detected separately before parser dispatch.

Machining import detects Excellon M48 headers independently of `.drl`, `.txt`,
`.nc` or `.tap` names, and reads X2 Plated/NonPlated Gerbers and JLCCam `ok/drl`.
Round holes, obround flashes and straight routed slots preserve physical dimensions;
plating and declared through-layer spans are retained. Clear machining operations,
unsupported shapes, arc routes and blind/buried depth models reject the affected
layer with a warning instead of becoming ordinary through holes.
