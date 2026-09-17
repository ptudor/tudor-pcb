import Foundation

/// English source text for import warnings and errors that the app shows to the
/// user: package structure, size and geometry limits, archives, proof images,
/// and outline analysis.
///
/// Every key lives in `Resources/Diagnostics.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md). Syntax problems inside a
/// Gerber or Excellon file are in `SyntaxStrings`.
enum DiagnosticStrings {
    // MARK: Composition

    /// "file.gbr: message" — a subject (file name, folder, or archive path)
    /// followed by the message that concerns it.
    static func subjectMessage(_ subject: String, _ message: String) -> String {
        String(localized: "\(subject): \(message)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Prefixes a message with the file or folder it concerns. %1$@ is a file name or path, %2$@ is the message (a full sentence). Keep the separator between them.")
    }

    /// "file.gbr: %ADD10C,0.1*%: reason" — a syntax problem located by file and
    /// the offending command.
    static func fileCommandReason(_ file: String, _ command: String, _ reason: String) -> String {
        String(localized: "\(file): \(command): \(reason)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Locates a syntax problem. %1$@ is a file name, %2$@ is the exact command text quoted from the file (do not translate it), %3$@ is the reason (a full sentence). Keep the separators.")
    }

    /// "outer.zip → inner.zip" — one step of a nested container path.
    static func nestedPath(_ outer: String, _ inner: String) -> String {
        String(localized: "\(outer) → \(inner)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Joins the names of nested archives or folders, outermost first. %1$@ is the containing archive or folder, %2$@ is the item inside it. The arrow may be replaced with one that reads naturally in your language and writing direction.")
    }

    static func joinedPath(_ components: [String]) -> String {
        guard let first = components.first else { return "" }
        return components.dropFirst().reduce(first) { nestedPath($0, $1) }
    }

    // MARK: Board geometry

    static var boardBoundsInvalid: String {
        String(localized: "Board bounds must be finite and ordered, with each dimension between 0.000001 and 1000000 mm.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when the board's overall width or height is missing, not a number, or outside the supported range. 'mm' is millimeters.")
    }

    static var boardThicknessInvalid: String {
        String(localized: "Board thickness must be finite, positive, and at most 1000000 mm.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when the board thickness is not a positive number within the supported range. 'mm' is millimeters.")
    }

    // MARK: Rendering

    static var textureCanvasAllocationFailed: String {
        String(localized: "Could not allocate the board texture canvas.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when the app cannot reserve memory for the image (texture) it paints the board into before displaying it in 3D.")
    }

    static var renderedImageCreationFailed: String {
        String(localized: "Could not create the rendered board image.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when the painted board image could not be turned into a displayable picture.")
    }

    // MARK: Limits

    static func geometryLimitExceeded(context: String, resource: String) -> String {
        String(localized: "\(context): geometry limit exceeded (\(resource)).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a file's drawing is too complex to process safely. %1$@ is a file name or command, %2$@ names the limit that was exceeded (a short phrase such as 'number of geometry points').")
    }

    static func importLimitExceeded(path: String, resource: String) -> String {
        String(localized: "\(path): import limit exceeded (\(resource)).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a package is too large or too deeply nested to import safely. %1$@ is a file name or path, %2$@ names the limit that was exceeded (a short phrase such as 'file size').")
    }

    /// The human-readable name of an internal limit identifier. Identifiers are
    /// stable strings used in code and tests; only their presentation is
    /// localized. An unknown identifier is shown as is.
    static func limitResource(_ identifier: String) -> String {
        switch identifier {
        case "allocations":
            String(localized: "memory needed to process the package", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the total memory the import would need. Shown inside parentheses after 'limit exceeded'.")
        case "input bytes":
            String(localized: "total input size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the combined size of all files read during one import. Shown inside parentheses after 'limit exceeded'.")
        case "file bytes":
            String(localized: "file size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the size of one file. Shown inside parentheses after 'limit exceeded'.")
        case "files":
            String(localized: "number of files", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many files one package may contain. Shown inside parentheses after 'limit exceeded'.")
        case "file changed during read":
            String(localized: "file changed while it was being read", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: a file grew or changed on disk while the app was reading it. Shown inside parentheses after 'limit exceeded'.")
        case "image changed during read":
            String(localized: "image changed while it was being read", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: an image file changed on disk while the app was reading it. Shown inside parentheses after 'limit exceeded'.")
        case "compressed bytes":
            String(localized: "compressed size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the compressed size of ZIP archive contents. Shown inside parentheses after 'limit exceeded'.")
        case "expanded bytes":
            String(localized: "decompressed size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the size of ZIP archive contents after decompression. Shown inside parentheses after 'limit exceeded'.")
        case "decoded bytes":
            String(localized: "decoded data size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the size of text or image data after decoding. Shown inside parentheses after 'limit exceeded'.")
        case "nested archives":
            String(localized: "number of nested archives", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many ZIP archives inside other archives one package may contain. Shown inside parentheses after 'limit exceeded'.")
        case "archive depth":
            String(localized: "archive nesting depth", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many levels of ZIP-inside-ZIP are followed. Shown inside parentheses after 'limit exceeded'.")
        case "directory depth":
            String(localized: "folder nesting depth", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many levels of subfolders are followed when a folder is opened. Shown inside parentheses after 'limit exceeded'.")
        case "geometry objects":
            String(localized: "number of geometry objects", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many drawn shapes (lines, arcs, flashes, regions) the import may hold. Shown inside parentheses after 'limit exceeded'.")
        case "geometry points":
            String(localized: "number of geometry points", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many coordinate points the drawn shapes may add up to. Shown inside parentheses after 'limit exceeded'.")
        case "document primitives":
            String(localized: "number of drawing objects in the board", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many drawn shapes the whole board may hold when it is painted. Shown inside parentheses after 'limit exceeded'.")
        case "document points/segments":
            String(localized: "number of points and segments in the board", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many coordinate points and line segments the whole board may hold when it is painted. Shown inside parentheses after 'limit exceeded'.")
        case "document drills":
            String(localized: "number of drill hits", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many drilled holes and slots the board may hold. Shown inside parentheses after 'limit exceeded'.")
        case "contour points":
            String(localized: "points in one contour", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many points one closed outline (contour) may have. Shown inside parentheses after 'limit exceeded'.")
        case "custom aperture vertices":
            String(localized: "custom aperture vertex count", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many corner points a user-defined aperture (a Gerber drawing tool shape) may have. Shown inside parentheses after 'limit exceeded'.")
        case "polygon vertices/angle":
            String(localized: "polygon vertex count and rotation", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the number of corners and the rotation angle of a polygon aperture (a Gerber drawing tool shape). Shown inside parentheses after 'limit exceeded'.")
        case "aperture nesting":
            String(localized: "aperture nesting depth", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many levels of shapes-inside-shapes an aperture (a Gerber drawing tool shape) may have. Shown inside parentheses after 'limit exceeded'.")
        case "aperture subprimitives":
            String(localized: "aperture sub-shapes", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many smaller shapes one compound aperture (a Gerber drawing tool shape) may be built from. Shown inside parentheses after 'limit exceeded'.")
        case "aperture points":
            String(localized: "aperture points", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many coordinate points one aperture (a Gerber drawing tool shape) may add up to. Shown inside parentheses after 'limit exceeded'.")
        case "macro parameters":
            String(localized: "aperture macro parameters", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many parameters an aperture macro (a parameterized Gerber shape definition) may take. Shown inside parentheses after 'limit exceeded'.")
        case "macro geometry":
            String(localized: "aperture macro geometry", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many shapes an aperture macro (a parameterized Gerber shape definition) may produce. Shown inside parentheses after 'limit exceeded'.")
        case "macro geometry points":
            String(localized: "aperture macro geometry points", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many coordinate points an aperture macro (a parameterized Gerber shape definition) may produce. Shown inside parentheses after 'limit exceeded'.")
        case "macro expression length":
            String(localized: "aperture macro expression length", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how long an arithmetic expression inside an aperture macro (a parameterized Gerber shape definition) may be. Shown inside parentheses after 'limit exceeded'.")
        case "macro expression depth":
            String(localized: "aperture macro expression nesting", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how deeply parentheses may nest in an arithmetic expression inside an aperture macro (a parameterized Gerber shape definition). Shown inside parentheses after 'limit exceeded'.")
        case "step-repeat count/spacing":
            String(localized: "step-and-repeat count and spacing", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the number of copies and the spacing of a Gerber step-and-repeat block (a pattern repeated in a grid). Shown inside parentheses after 'limit exceeded'.")
        case "valid arc radius/endpoints":
            String(localized: "arc radius and endpoints", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: an arc's radius and end points do not describe a valid arc. Shown inside parentheses after 'limit exceeded'.")
        case "tessellated segments per arc":
            String(localized: "segments per arc", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many straight segments one arc may be divided into for drawing. Shown inside parentheses after 'limit exceeded'.")
        case "finite supported coordinates":
            String(localized: "coordinates", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: a coordinate is not a number or lies outside the supported range. Shown inside parentheses after 'limit exceeded'.")
        case "finite supported dimension":
            String(localized: "dimension", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: a width, height, or diameter is not a number or lies outside the supported range. Shown inside parentheses after 'limit exceeded'.")
        case "resolved outline points":
            String(localized: "outline points", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many points the board outline may have after analysis. Shown inside parentheses after 'limit exceeded'.")
        case "resolved linear outline output":
            String(localized: "outline segments", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many straight segments the board outline may have after analysis. Shown inside parentheses after 'limit exceeded'.")
        case "outline intersection work":
            String(localized: "outline intersection processing", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how much work finding crossings between outline shapes may take. Shown inside parentheses after 'limit exceeded'.")
        case "outline intersection output":
            String(localized: "outline intersection results", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many crossings between outline shapes may be produced. Shown inside parentheses after 'limit exceeded'.")
        case "outline endpoint tolerance":
            String(localized: "outline endpoint tolerance", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: the distance allowed between outline line ends that should meet is not usable. Shown inside parentheses after 'limit exceeded'.")
        case "unresolved outline endpoint density":
            String(localized: "unconnected outline endpoints in one area", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many unconnected outline line ends may lie close together. Shown inside parentheses after 'limit exceeded'.")
        case "bore wall points":
            String(localized: "drill wall points", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many points are used to draw the inside walls of drilled holes in 3D. Shown inside parentheses after 'limit exceeded'.")
        case "bore wall material work":
            String(localized: "drill wall processing", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how much work cutting drilled holes out of the board model may take. Shown inside parentheses after 'limit exceeded'.")
        case "bore tessellation":
            String(localized: "drill wall segments", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many segments the inside wall of one drilled hole is divided into for 3D drawing. Shown inside parentheses after 'limit exceeded'.")
        case "machined wall mesh":
            String(localized: "drilled wall mesh size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the size of the 3D mesh built for all drilled and routed walls. Shown inside parentheses after 'limit exceeded'.")
        case "image input bytes":
            String(localized: "image file size", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the size of one proof image file. Shown inside parentheses after 'limit exceeded'.")
        case "image dimensions/pixels":
            String(localized: "image dimensions", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the width and height of a proof image. Shown inside parentheses after 'limit exceeded'.")
        case "image pixels":
            String(localized: "image pixel count", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: the total number of pixels in a proof image. Shown inside parentheses after 'limit exceeded'.")
        case "image frames":
            String(localized: "image frame count", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit: how many frames (pages or animation frames) a proof image may contain. Shown inside parentheses after 'limit exceeded'.")
        case "positive artwork mapping dimensions":
            String(localized: "artwork mapping dimensions", table: "Diagnostics", bundle: Bundle.module,
                   comment: "Name of a limit violation: the rectangle a proof image is mapped onto must have positive width and height. Shown inside parentheses after 'limit exceeded'.")
        default:
            identifier
        }
    }

    // MARK: Packages and containers

    static var noSupportedLayers: String {
        String(localized: "No Gerber or Excellon layers were found in this package.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a ZIP or folder contains no board files. 'Gerber' is the file format for board layers and 'Excellon' the file format for drill data; keep both names as written.")
    }

    static var nestedArchiveLimit: String {
        String(localized: "The nested fabrication archives exceed the safe expansion limit.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when ZIP archives inside the package contain too many further archives to unpack safely.")
    }

    static func duplicateEntry(_ path: String) -> String {
        String(localized: "Duplicate archive entry \(path); a unique source path is required.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a ZIP archive lists the same file path twice. %@ is the repeated path.")
    }

    static func ambiguousBoardSets(_ names: [String]) -> String {
        String(localized: "Separate board sets require selection: \(list(names)).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a package holds several complete boards and the user must pick one. %@ is a comma-separated list of the board set names.")
    }

    static func ambiguousNestedArchives(_ names: [String]) -> String {
        String(localized: "Several equally likely fabrication packages were found: \(list(names)).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a package holds several ZIP archives that could each be the board and the user must pick one. %@ is a comma-separated list of archive names.")
    }

    static func chooseFabricationBoard(_ names: [String]) -> String {
        String(localized: "Choose a fabrication board: \(list(names))", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a package holds several boards and the user must pick one. %@ is a comma-separated list of the candidate names.")
    }

    static var selectedArchiveMissing: String {
        String(localized: "The selected archive is no longer present.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when reopening a board from history and the ZIP archive that was chosen inside the package has since been removed.")
    }

    static func selectedBoardSetMissing(_ name: String) -> String {
        String(localized: "The selected board set is no longer present: \(name)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when reopening a board from history and the board set that was chosen inside the package has since been removed. %@ is the board set name.")
    }

    static var directoryEnumerationFailed: String {
        String(localized: "Could not enumerate fabrication directory.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when the app cannot list the contents of a folder the user opened.")
    }

    static func entryMetadataUnreadable(_ detail: String) -> String {
        String(localized: "Could not read fabrication entry metadata: \(detail)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a file's size or type could not be read from disk. %@ is the operating system's description of the problem (a full sentence).")
    }

    static func directoryImportIncomplete(_ detail: String) -> String {
        String(localized: "Directory import is incomplete: \(detail)", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when some files in a folder could not be read. %@ lists the affected paths and problems, one per line.")
    }

    // MARK: Gerber files

    static var notTextGerber: String {
        String(localized: "The layer is not an ASCII or UTF-8 Gerber file.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a file expected to be a Gerber board layer is not plain text. 'ASCII' and 'UTF-8' are text encodings; keep them as written.")
    }

    static func noDrawableGeometry(_ file: String) -> String {
        String(localized: "No drawable Gerber geometry was found in \(file).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a Gerber file parses but draws nothing. %@ is the file name.")
    }

    // MARK: Proof images

    static func proofImageInvalid(_ name: String) -> String {
        String(localized: "\(name): the proof image format, metadata, or pixel data is invalid or unsupported.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a proof image (a picture of the finished board) cannot be decoded. %@ is the file name.")
    }

    static func colorProofPayloadEmpty(_ file: String) -> String {
        String(localized: "[Color proof] \(file): factory payload is empty; validity has not been established.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning about the manufacturer's encrypted color silkscreen data: the file is empty, so it cannot be checked. %@ is the file name. Keep the bracketed tag at the start; it marks warnings about color proofs.")
    }

    static var colorProofGalleryOnlyTop: String {
        String(localized: "[Color proof] Top: a validated gallery proof is available but unmapped; exact board colors remain unavailable.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning for the top face: a proof picture was accepted but has not been positioned on the board, so the 3D view cannot show true colors. Keep the bracketed tag at the start; it marks warnings about color proofs.")
    }

    static var colorProofGalleryOnlyBottom: String {
        String(localized: "[Color proof] Bottom: a validated gallery proof is available but unmapped; exact board colors remain unavailable.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning for the bottom face: a proof picture was accepted but has not been positioned on the board, so the 3D view cannot show true colors. Keep the bracketed tag at the start; it marks warnings about color proofs.")
    }

    static var colorProofUnverifiedTop: String {
        String(localized: "[Color proof] Top: factory payload present, validity unverified; exact colors are unavailable without a validated proof.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning for the top face: the manufacturer's encrypted color data exists but cannot be checked, and no proof picture has been accepted, so the 3D view cannot show true colors. Keep the bracketed tag at the start; it marks warnings about color proofs.")
    }

    static var colorProofUnverifiedBottom: String {
        String(localized: "[Color proof] Bottom: factory payload present, validity unverified; exact colors are unavailable without a validated proof.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning for the bottom face: the manufacturer's encrypted color data exists but cannot be checked, and no proof picture has been accepted, so the 3D view cannot show true colors. Keep the bracketed tag at the start; it marks warnings about color proofs.")
    }

    static func sidecarProofsUninspectable(_ detail: String) -> String {
        String(localized: "Sibling proofs could not be inspected: \(detail) Use Color proof options to select a proof explicitly, or open its containing folder.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning shown when the folder next to an opened ZIP could not be listed for proof images. %@ is the operating system's description of the problem (a full sentence ending with a period). 'Color proof options' is the name of a menu in the app.")
    }

    static func sidecarProofUnreadable(_ name: String, _ detail: String) -> String {
        String(localized: "\(name): sibling proof could not be read: \(detail) Select it explicitly with Color proof options.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning shown when a proof image found next to an opened ZIP could not be read. %1$@ is the image file name, %2$@ is the operating system's description of the problem (a full sentence ending with a period). 'Color proof options' is the name of a menu in the app.")
    }

    // MARK: ZIP archives

    static var zipUnsupportedZIP64: String {
        String(localized: "ZIP64 archives are not supported.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a ZIP file that uses the ZIP64 large-archive extension. Keep 'ZIP64' as written.")
    }

    static var zipUnsupportedSplitArchive: String {
        String(localized: "Split ZIP archives are not supported.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a ZIP archive that was divided into several files (multi-part archive).")
    }

    static var zipInvalidArchive: String {
        String(localized: "The ZIP central directory is missing or damaged.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a ZIP file whose table of contents (the 'central directory') cannot be read.")
    }

    static func zipUnsupportedCompression(_ method: UInt16) -> String {
        String(localized: "ZIP compression method \(Int(method)) is not supported.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a ZIP entry compressed with a method the app cannot decompress. %lld is the method's numeric code from the ZIP specification.")
    }

    static func zipEncryptedEntry(_ name: String) -> String {
        String(localized: "\(name) is encrypted at the ZIP level.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a password-protected file inside a ZIP archive. %@ is the file name.")
    }

    static func zipUnsafeSize(_ name: String) -> String {
        String(localized: "\(name) exceeds the safe in-memory size limit.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown for a file inside a ZIP archive that is too large to unpack into memory. %@ is the file name.")
    }

    static func zipDecompressionFailed(_ name: String, code: Int32) -> String {
        String(localized: "Could not decompress \(name) (zlib \(Int(code))).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a file inside a ZIP archive fails to decompress. %1$@ is the file name, %2$lld is the error code from the zlib library; keep 'zlib' as written.")
    }

    static func zipChecksumMismatch(_ name: String) -> String {
        String(localized: "\(name) failed its ZIP checksum.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Error shown when a file inside a ZIP archive is corrupt (its stored checksum does not match its contents). %@ is the file name.")
    }

    // MARK: Board outline analysis

    static func degenerateRegionContour(_ file: String) -> String {
        String(localized: "\(file): degenerate region contour; material topology is unresolved.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: a filled region in the board outline file has no area (its points lie on a line), so the app cannot tell where board material is. %@ is the file name.")
    }

    static func flashedOutlineUnsupported(_ file: String) -> String {
        String(localized: "\(file): flashed outline geometry has no supported routed centerline.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the board outline file contains a 'flash' (a stamped shape) instead of drawn lines, which cannot define a cut path. %@ is the file name.")
    }

    static func inferredEndpointJoin(_ source: String, tolerance: String) -> String {
        String(localized: "\(source): inferred a routed endpoint join within \(tolerance) mm; verify the source gap.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: two outline lines did not quite meet, so the app assumed they connect. %1$@ is the file name, %2$@ is the gap distance as a number; 'mm' is millimeters.")
    }

    static func ambiguousEndpointsUnjoined(_ source: String) -> String {
        String(localized: "\(source): ambiguous nearby routed endpoints were left unjoined.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: several outline line ends lie close together and the app could not tell which ones connect, so it left them apart. %@ is the file name.")
    }

    static func nonmanifoldJunction(_ source: String) -> String {
        String(localized: "\(source): nonmanifold routed junction; material topology is unresolved.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: three or more outline lines meet at one point, so the app cannot tell where board material is. %@ is the file name.")
    }

    static func openRoutedPaths(_ source: String) -> String {
        String(localized: "\(source): open routed paths require panel/material inference; inspect their endpoints.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the board outline does not close into a loop, so the app had to guess the board shape. %@ is the file name.")
    }

    static func degenerateRoutedContour(_ source: String) -> String {
        String(localized: "\(source): degenerate routed contour; material topology is unresolved.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: a closed outline loop has no area, so the app cannot tell where board material is. %@ is the file name.")
    }

    // MARK: Layer classification

    static func excellonSyntaxConflictsRole(_ file: String, role: String) -> String {
        String(localized: "\(file): Excellon syntax conflicts with filename role \(role).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the file's name suggests one layer type but its contents are drill data. %1$@ is the file name, %2$@ is the layer name the file name suggested (for example 'Top copper'). 'Excellon' is the drill file format; keep it as written.")
    }

    static func conflictingFileFunctions(_ file: String) -> String {
        String(localized: "\(file): conflicting FileFunction attributes; layer role is unresolved.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the file declares more than one layer type, so the app could not decide which it is. %@ is the file name. 'FileFunction' is a Gerber attribute name; keep it as written.")
    }

    static func unsupportedFileFunction(_ file: String, attribute: String) -> String {
        String(localized: "\(file): unsupported FileFunction \(attribute); layer role is unresolved.", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the file declares a layer type the app does not know. %1$@ is the file name, %2$@ is the declared value quoted from the file (do not translate it). 'FileFunction' is a Gerber attribute name; keep it as written.")
    }

    static func fileFunctionOverridesRole(_ file: String, role: String) -> String {
        String(localized: "\(file): FileFunction overrides conflicting filename role \(role).", table: "Diagnostics", bundle: Bundle.module,
               comment: "Warning: the file's declared layer type disagrees with what its name suggests, and the declaration was used. %1$@ is the file name, %2$@ is the layer name the file name suggested (for example 'Top copper'). 'FileFunction' is a Gerber attribute name; keep it as written.")
    }

    private static func list(_ names: [String]) -> String {
        names.formatted(.list(type: .and, width: .narrow))
    }
}
