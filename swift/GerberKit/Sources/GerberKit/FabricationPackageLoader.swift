import Foundation

public enum FabricationPackageError: Error, LocalizedError, Sendable {
    case noSupportedLayers
    case nestedArchiveLimit
    case ambiguousNestedArchives([String])
    case ambiguousBoardSets([String])
    case duplicateEntry(String)

    public var errorDescription: String? {
        switch self {
        case .noSupportedLayers:
            "No Gerber or Excellon layers were found in this package."
        case .nestedArchiveLimit:
            "The nested fabrication archives exceed the safe expansion limit."
        case let .duplicateEntry(path):
            "Duplicate archive entry \(path); a unique source path is required."
        case let .ambiguousBoardSets(names):
            "Separate board sets require selection: \(names.joined(separator: ", "))."
        case let .ambiguousNestedArchives(names):
            "Several equally likely fabrication packages were found: \(names.joined(separator: ", "))."
        }
    }
}

public struct FabricationPackageLoader: Sendable {
    private let limits: ImportLimits
    public init(limits: ImportLimits = .init()) { self.limits = limits }

    public func load(from url: URL, selection: FabricationSelection? = nil) throws -> BoardDocument {
        var budget = ImportBudget(limits: limits)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let files: [ZipEntry]
        var sidecarWarnings: [String] = []
        if values.isDirectory == true {
            files = try filesInDirectory(url, budget: &budget)
        } else if url.pathExtension.lowercased() == "zip" {
            let data = try readFile(url, budget: &budget, isArchive: true)
            files = try ZipArchiveReader().read(data, budget: &budget, path: url.lastPathComponent)
                + sidecarImages(beside: url, budget: &budget, warnings: &sidecarWarnings)
        } else {
            try budget.file(path: url.path)
            files = [ZipEntry(name: url.lastPathComponent, data: try readFile(url, budget: &budget))]
        }
        var document = try loadContainer(files: files, name: url.deletingPathExtension().lastPathComponent, depth: 0, path: [], selection: selection, budget: &budget)
        document.warnings += sidecarWarnings
        return document
    }

    public func load(files: [ZipEntry], name: String, selection: FabricationSelection? = nil) throws -> BoardDocument {
        var budget = ImportBudget(limits: limits)
        for file in files {
            try budget.file(path: file.name)
            try budget.input(file.data.count, path: file.name, isArchive: file.name.lowercased().hasSuffix(".zip"))
        }
        return try loadContainer(files: files, name: name, depth: 0, path: [], selection: selection, budget: &budget)
    }

    private func readFile(_ url: URL, budget: inout ImportBudget, isArchive: Bool = false) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try budget.input(size, path: url.path, isArchive: isArchive)
        // Read only the preflighted length plus one byte, so a growing file cannot
        // bypass the budget between stat and read.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard size < Int.max else { throw ImportLimitError(resource: "input bytes", path: url.path) }
        let data = try handle.read(upToCount: size + 1) ?? Data()
        guard data.count <= size else { throw ImportLimitError(resource: "file changed during read", path: url.path) }
        return data
    }

    private func loadContainer(
        files: [ZipEntry], name: String, depth: Int, path: [String],
        selection: FabricationSelection?, budget: inout ImportBudget
    ) throws -> BoardDocument {
        var names = Set<String>()
        for file in files {
            guard names.insert(file.name).inserted else { throw FabricationPackageError.duplicateEntry((path + [file.name]).joined(separator: " → ")) }
        }
        if let selection, path.count < selection.containers.count {
            let requested = selection.containers[path.count]
            guard let archive = files.first(where: { $0.name == requested && $0.name.lowercased().hasSuffix(".zip") }) else {
                throw FabricationContainerError(path: path + [requested], reason: "The selected archive is no longer present.")
            }
            return try loadNested(archive, depth: depth, path: path, selection: selection, budget: &budget)
        }
        let groups = flatGroups(in: files)
        var flatFiles = files
        if let selectedGroup = selection?.group {
            guard let group = groups.first(where: { $0.name == selectedGroup }) else {
                throw FabricationContainerError(path: path, reason: "The selected board set is no longer present: " + selectedGroup)
            }
            flatFiles = group.files
        } else if groups.count > 1 {
            throw FabricationSelectionRequired(candidates: groups.map { .init(containers: path, group: $0.name) })
        }
        let identity = FabricationSelection(containers: path, group: selection?.group ?? groups.first?.name)
        if let envelope = jlcpcbProductionEnvelope(in: flatFiles) {
            var document = try loadFlat(files: envelope.productionFiles, name: name, budget: &budget)
            document.packageRole = .jlcpcbProduction
            document.enclosedSourceArchives = envelope.originalArchives
            document.sourceSelection = identity
            return document
        }
        var fallback: BoardDocument?
        do {
            var document = try loadFlat(files: flatFiles, name: name, budget: &budget)
            if document.layers.contains(where: { $0.sourceGenerator?.localizedCaseInsensitiveContains("jlccam") == true }) { document.packageRole = .jlcpcbProduction }
            document.sourceSelection = identity
            if selection != nil { return document }
            fallback = document
        } catch FabricationPackageError.noSupportedLayers { }
        let nested = files.filter { $0.name.lowercased().hasSuffix(".zip") }.sorted { $0.name < $1.name }
        var candidates: [BoardDocument] = fallback.map { [$0] } ?? []
        for archive in nested {
            do { candidates.append(try loadNested(archive, depth: depth, path: path, selection: nil, budget: &budget)) }
            catch FabricationPackageError.noSupportedLayers { continue } // Only safely evaluated non-board content is harmless.
        }
        guard let bestScore = candidates.map(packageScore).max() else { throw FabricationPackageError.noSupportedLayers }
        let best = candidates.filter { packageScore($0) == bestScore }
        guard best.count == 1 else { throw FabricationSelectionRequired(candidates: best.compactMap(\.sourceSelection)) }
        return best[0]
    }

    private func loadNested(_ archive: ZipEntry, depth: Int, path: [String], selection: FabricationSelection?, budget: inout ImportBudget) throws -> BoardDocument {
        let nextPath = path + [archive.name]
        let context = nextPath.joined(separator: " → ")
        guard depth < limits.archiveDepth else { throw ImportLimitError(resource: "archive depth", path: context) }
        try budget.charge("nested archives", 1, maximum: limits.archives, path: context)
        do {
            let entries = try ZipArchiveReader().read(archive.data, budget: &budget, path: context)
            var document = try loadContainer(files: entries, name: URL(fileURLWithPath: archive.name).deletingPathExtension().lastPathComponent,
                                             depth: depth + 1, path: nextPath, selection: selection, budget: &budget)
            if document.packageRole == .direct { document.packageRole = .nestedArchive }
            if document.packageRole == .nestedArchive, !document.enclosedSourceArchives.contains(archive.name) { document.enclosedSourceArchives.append(archive.name) }
            return document
        } catch let error as ImportLimitError {
            throw ImportLimitError(resource: error.resource, path: error.path.hasPrefix(context) ? error.path : context + " → " + error.path)
        } catch let error as GeometryLimitError {
            throw GeometryLimitError(resource: error.resource, context: context + " → " + error.context)
        }
          catch let error as FabricationSelectionRequired { throw error }
          catch let error as FabricationContainerError {
            throw FabricationContainerError(path: error.path.starts(with: nextPath) ? error.path : nextPath + error.path, reason: error.reason)
        }
          catch FabricationPackageError.noSupportedLayers { throw FabricationPackageError.noSupportedLayers }
          catch is CancellationError { throw CancellationError() }
          catch { throw FabricationContainerError(path: nextPath, reason: error.localizedDescription) }
    }

    private struct FlatGroup {
        var name: String
        var files: [ZipEntry]
    }

    private func flatGroups(in files: [ZipEntry]) -> [FlatGroup] {
        let material = files.filter { file in
            guard !file.name.lowercased().hasSuffix(".zip") else { return false }
            let contents = String(decoding: file.data.prefix(8192), as: UTF8.self)
            switch LayerClassifier.classify(fileName: file.name, contents: contents) {
            case .copper, .outline, .drill, .solderMask, .silkscreen, .paste: return true
            default: return false
            }
        }
        let directories = Dictionary(grouping: material) { (file: ZipEntry) in
            let directory = (file.name as NSString).deletingLastPathComponent
            return directory.isEmpty ? "." : directory
        }
        return directories.keys.sorted().flatMap { directory -> [FlatGroup] in
            let members = directories[directory]!
            let directoryFiles = files.filter { file in
                let parent = (file.name as NSString).deletingLastPathComponent
                return (parent.isEmpty ? "." : parent) == directory
            }
            // A production set may have multiple legend overlays by design.
            if members.contains(where: { String(decoding: $0.data.prefix(512), as: UTF8.self).localizedCaseInsensitiveContains("output software:jlccam") }) {
                return [FlatGroup(name: directory, files: directoryFiles)]
            }
            let byRole = Dictionary(grouping: members) { LayerClassifier.classify(fileName: $0.name, contents: String(decoding: $0.data.prefix(8192), as: UTF8.self)) }
            guard byRole.values.contains(where: { $0.count > 1 }) else { return [FlatGroup(name: directory, files: directoryFiles)] }
            // Repeated roles with different stems are separate project candidates.
            let projects = Dictionary(grouping: members) { ($0.name as NSString).deletingPathExtension }
            let plausible = projects.filter { _, members in
                let roles = Set(members.map { LayerClassifier.classify(fileName: $0.name, contents: String(decoding: $0.data.prefix(8192), as: UTF8.self)) })
                return roles.contains(.outline) || roles.count >= 2
            }
            // Separate PTH/via drill files and overlay layers are ordinary parts
            // of one set; a repeated role alone does not establish another board.
            guard plausible.count > 1 else { return [FlatGroup(name: directory, files: directoryFiles)] }
            return projects.keys.sorted().map { stem in FlatGroup(name: stem, files: directoryFiles.filter { ($0.name as NSString).deletingPathExtension == stem }) }
        }
    }

    private func loadFlat(files: [ZipEntry], name: String, budget: inout ImportBudget) throws -> BoardDocument {
        let gerberParser = GerberParser()
        let drillParser = ExcellonParser()
        var layers: [GerberLayer] = []
        var drills: [DrillHit] = []
        var colorful: [ColorSilkscreenInfo] = []
        var previews: [BoardSidePreview] = []
        var warnings: [String] = []

        for file in files.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            // Stored ZIP bytes can contain literal Gerber headers; containers
            // must be evaluated only through the archive path.
            if file.name.lowercased().hasSuffix(".zip") { continue }
            var contents = String(decoding: file.data.prefix(8_192), as: UTF8.self)
            let initialKind = LayerClassifier.classify(fileName: file.name, contents: contents)
            let isDrill: Bool
            if case .drill = initialKind { isDrill = true } else { isDrill = false }
            if isDrill || LayerClassifier.isGerber(file.name, contents: contents) {
                try budget.decodedText(file.data.count, path: file.name)
                contents = String(decoding: file.data, as: UTF8.self)
            }
            let classification = LayerClassifier.classification(fileName: file.name, contents: contents)
            warnings += classification.warnings
            let kind = classification.kind
            let syntax = LayerClassifier.syntax(contents: contents)
            if isJLCCamDrill(file.name, contents: contents) {
                do {
                    let drillLayer = try gerberParser.parse(data: file.data, fileName: file.name, budget: &budget)
                    let hits = try GerberMachiningConverter.convert(drillLayer, source: contents, budget: &budget)
                    layers.append(drillLayer)
                    drills += hits
                } catch let error as ImportLimitError { throw error }
                  catch let error as GeometryLimitError { throw error }
                  catch is CancellationError { throw CancellationError() }
                  catch {
                    warnings.append("\(file.name): \(error.localizedDescription)")
                }
                continue
            }
            switch kind {
            case let .colorfulSilkscreen(side):
                colorful.append(ColorSilkscreenInfo(
                    side: side,
                    fileName: file.name,
                    payload: .encryptedJLC,
                    byteCount: file.data.count
                ))
            case .drill:
                do {
                    switch syntax {
                    case .gerber:
                        let drillLayer = try gerberParser.parse(data: file.data, fileName: file.name, budget: &budget)
                        let hits = try GerberMachiningConverter.convert(drillLayer, source: contents, budget: &budget)
                        layers.append(drillLayer)
                        drills += hits
                    case .excellon:
                        drills += try drillParser.parse(data: file.data, fileName: file.name, budget: &budget)
                    case .unknown:
                        throw ExcellonParseError(fileName: file.name, command: "header", reason: "Unrecognized drill syntax.")
                    }
                } catch let error as ImportLimitError { throw error }
                  catch let error as GeometryLimitError { throw error }
                  catch is CancellationError { throw CancellationError() }
                  catch {
                    warnings.append("\(file.name): \(error.localizedDescription)")
                }
            default:
                if let side = previewSide(for: file.name), isImage(file.name) {
                    let decoded = try ProofImageDecoder.decode(file.data, name: file.name, budget: &budget)
                    previews.append(BoardSidePreview(side: side, fileName: file.name, imageData: file.data, validatedImage: decoded, purpose: .galleryProof))
                } else if LayerClassifier.isGerber(file.name, contents: contents) {
                    do {
                        layers.append(try gerberParser.parse(data: file.data, fileName: file.name, budget: &budget))
                    } catch GerberParseError.missingGeometry where kind == .documentation || kind == .other {
                        // Empty documentation and auxiliary Gerbers are common and harmless.
                    } catch let error as ImportLimitError { throw error }
                      catch let error as GeometryLimitError { throw error }
                  catch is CancellationError { throw CancellationError() }
                      catch {
                        warnings.append("\(file.name): \(error.localizedDescription)")
                    }
                }
            }
        }

        guard !layers.isEmpty || !drills.isEmpty else {
            if !warnings.isEmpty { throw FabricationContainerError(path: [name], reason: warnings.joined(separator: "\n")) }
            throw FabricationPackageError.noSupportedLayers
        }

        let preferredBounds = layers.filter { $0.kind == .outline }.compactMap(\.centerlineBounds)
        let allBounds = preferredBounds.isEmpty ? layers.compactMap(\.bounds) : preferredBounds
        var bounds = allBounds.reduce(nil) { partial, next in partial?.union(next) ?? next }
        if bounds == nil {
            for drill in drills {
                let endpoints = [drill.center] + (drill.end.map { [$0] } ?? [])
                let hitBounds = Bounds2D.containing(endpoints)!.expanded(by: drill.diameter / 2)
                bounds = bounds?.union(hitBounds) ?? hitBounds
            }
        }
        let safeBounds = bounds.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            ?? Bounds2D(minimum: .zero, maximum: Point2D(x: 100, y: 60))

        var document = BoardDocument(
            name: name,
            layers: layers,
            drills: drills,
            bounds: safeBounds,
            colorSilkscreens: colorful,
            sidePreviews: previews,
            warnings: warnings
        )
        document.warnings += try BoardOutlineExtractor.topology(in: document).warnings
        document.refreshProofWarnings()
        return document
    }

    private func filesInDirectory(_ directory: URL, budget: inout ImportBudget) throws -> [ZipEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var traversalErrors: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                traversalErrors.append("\(url.path): \(error.localizedDescription)")
                return false
            }
        ) else { throw FabricationContainerError(path: [directory.path], reason: "Could not enumerate fabrication directory.") }
        var files: [ZipEntry] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard enumerator.level <= limits.directoryDepth else {
                throw ImportLimitError(resource: "directory depth", path: fileURL.path)
            }
            let values: URLResourceValues
            do { values = try fileURL.resourceValues(forKeys: Set(keys)) }
            catch { throw FabricationContainerError(path: [fileURL.path], reason: "Could not read fabrication entry metadata: \(error.localizedDescription)") }
            guard values.isRegularFile == true, !isKnownIrrelevant(fileURL) else { continue }
            try budget.file(path: fileURL.path)
            files.append(ZipEntry(
                // URL enumeration can add /private to /var or /tmp. Component
                // depth preserves the relative identity across those aliases.
                name: fileURL.pathComponents.suffix(enumerator.level).joined(separator: "/"),
                data: try readFile(fileURL, budget: &budget, isArchive: fileURL.pathExtension.lowercased() == "zip")
            ))
        }
        if !traversalErrors.isEmpty {
            throw FabricationContainerError(path: [directory.path], reason: "Directory import is incomplete: " + traversalErrors.joined(separator: "\n"))
        }
        return files
    }

    private func isKnownIrrelevant(_ url: URL) -> Bool {
        ["pdf", "md", "html", "htm", "json", "yaml", "yml", "step", "stp", "iges", "stl", "ddw", "tgz", "gz", "7z"]
            .contains(url.pathExtension.lowercased())
    }

    private func sidecarImages(beside archive: URL, budget: inout ImportBudget, warnings: inout [String]) throws -> [ZipEntry] {
        let parent = archive.deletingLastPathComponent()
        let candidates: [URL]
        do {
            candidates = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        } catch {
            warnings.append("Sibling proofs could not be inspected: \(error.localizedDescription) Use Color proof options to select a proof explicitly, or open its containing folder.")
            return []
        }
        var result: [ZipEntry] = []
        for candidate in candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = candidate.lastPathComponent
            guard Self.matchesSidecar(name, archiveName: archive.lastPathComponent), previewSide(for: name) != nil, isImage(name) else { continue }
            do {
                guard try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                try budget.file(path: candidate.path)
                result.append(ZipEntry(name: name, data: try readFile(candidate, budget: &budget)))
            } catch let error as ImportLimitError { throw error }
              catch is CancellationError { throw CancellationError() }
              catch { warnings.append("\(name): sibling proof could not be read: \(error.localizedDescription) Select it explicitly with Color proof options.") }
        }
        return result
    }

    static func matchesSidecar(_ imageName: String, archiveName: String) -> Bool {
        var stem = URL(fileURLWithPath: archiveName).deletingPathExtension().lastPathComponent.lowercased()
        for suffix in ["_gerbers", "-gerbers"] where stem.hasSuffix(suffix) { stem.removeLast(suffix.count) }
        let name = URL(fileURLWithPath: imageName).deletingPathExtension().lastPathComponent.lowercased()
        guard name.hasPrefix(stem), name.count > stem.count else { return false }
        let suffix = name.dropFirst(stem.count)
        guard suffix.first == "_" || suffix.first == "-" else { return false }
        let tokens = suffix.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        return !tokens.isEmpty && tokens.allSatisfy { ["top", "bottom", "artwork", "proof", "preview", "side"].contains($0) }
    }

    private func previewSide(for fileName: String) -> GerberSide? {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.lowercased()
        if base.hasSuffix("_top") || base.hasSuffix("-top") || base.contains("top-preview") { return .top }
        if base.hasSuffix("_bottom") || base.hasSuffix("-bottom") || base.contains("bottom-preview") { return .bottom }
        return nil
    }

    private func isImage(_ fileName: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(
            URL(fileURLWithPath: fileName).pathExtension.lowercased()
        )
    }

    private func jlcpcbProductionEnvelope(in files: [ZipEntry]) -> JLCPCBEnvelope? {
        var productionFiles: [ZipEntry] = []
        var originalArchives: [String] = []

        for file in files {
            let components = file.name
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .map(String.init)
            let lower = components.map { $0.lowercased() }

            if lower.contains("yg"), URL(fileURLWithPath: file.name).pathExtension.lowercased() == "zip" {
                originalArchives.append(file.name)
            }

            guard let okIndex = lower.firstIndex(of: "ok"), okIndex + 1 < components.count else { continue }
            let relativeName = components[(okIndex + 1)...].joined(separator: "/")
            let ext = URL(fileURLWithPath: relativeName).pathExtension.lowercased()
            guard !["ddw", "tgz", "gz", "7z"].contains(ext) else { continue }
            let contents = String(decoding: file.data.prefix(512), as: UTF8.self)
            guard contents.localizedCaseInsensitiveContains("output software:jlccam") else { continue }
            productionFiles.append(file)
        }

        guard productionFiles.contains(where: {
            URL(fileURLWithPath: $0.name).lastPathComponent.lowercased() == "ko"
        }), productionFiles.count >= 4 else { return nil }
        return JLCPCBEnvelope(
            productionFiles: productionFiles,
            originalArchives: originalArchives.sorted()
        )
    }

    private func isJLCCamDrill(_ fileName: String, contents: String) -> Bool {
        URL(fileURLWithPath: fileName).lastPathComponent.lowercased() == "drl"
            && contents.localizedCaseInsensitiveContains("output software:jlccam")
    }

    private func packageScore(_ document: BoardDocument) -> Int {
        var score = document.layers.count * 10 + min(document.drills.count, 100)
        if document.layers.contains(where: { $0.kind == .outline }) { score += 1_000 }
        if document.layers.contains(where: { $0.kind == .copper(side: .top, index: nil) }) { score += 200 }
        if document.layers.contains(where: { $0.kind == .copper(side: .bottom, index: nil) }) { score += 200 }
        return score
    }
}

private struct JLCPCBEnvelope {
    var productionFiles: [ZipEntry]
    var originalArchives: [String]
}
