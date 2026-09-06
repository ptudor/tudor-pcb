import Foundation

public enum FabricationPackageError: Error, LocalizedError, Sendable {
    case noSupportedLayers
    case nestedArchiveLimit
    case ambiguousNestedArchives([String])

    public var errorDescription: String? {
        switch self {
        case .noSupportedLayers:
            "No Gerber or Excellon layers were found in this package."
        case .nestedArchiveLimit:
            "The nested fabrication archives exceed the safe expansion limit."
        case let .ambiguousNestedArchives(names):
            "Several equally likely fabrication packages were found: \(names.joined(separator: ", "))."
        }
    }
}

public struct FabricationPackageLoader: Sendable {
    private let limits: ImportLimits
    public init(limits: ImportLimits = .init()) { self.limits = limits }

    public func load(from url: URL) throws -> BoardDocument {
        var budget = ImportBudget(limits: limits)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let files: [ZipEntry]
        if values.isDirectory == true {
            files = try filesInDirectory(url, budget: &budget)
        } else if url.pathExtension.lowercased() == "zip" {
            let data = try readFile(url, budget: &budget, isArchive: true)
            files = try ZipArchiveReader().read(data, budget: &budget, path: url.lastPathComponent)
                + sidecarImages(beside: url, budget: &budget)
        } else {
            try budget.file(path: url.path)
            files = [ZipEntry(name: url.lastPathComponent, data: try readFile(url, budget: &budget))]
        }
        return try loadContainer(files: files, name: url.deletingPathExtension().lastPathComponent, depth: 0, budget: &budget)
    }

    public func load(files: [ZipEntry], name: String) throws -> BoardDocument {
        var budget = ImportBudget(limits: limits)
        for file in files {
            try budget.file(path: file.name)
            try budget.input(file.data.count, path: file.name, isArchive: file.name.lowercased().hasSuffix(".zip"))
        }
        return try loadContainer(files: files, name: name, depth: 0, budget: &budget)
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
        files: [ZipEntry],
        name: String,
        depth: Int,
        budget: inout ImportBudget
    ) throws -> BoardDocument {
        if let envelope = jlcpcbProductionEnvelope(in: files) {
            var document = try loadFlat(files: envelope.productionFiles, name: name, budget: &budget)
            document.packageRole = .jlcpcbProduction
            document.enclosedSourceArchives = envelope.originalArchives
            return document
        }

        do {
            var document = try loadFlat(files: files, name: name, budget: &budget)
            if document.layers.contains(where: {
                $0.sourceGenerator?.localizedCaseInsensitiveContains("jlccam") == true
            }) {
                document.packageRole = .jlcpcbProduction
            }
            return document
        } catch FabricationPackageError.noSupportedLayers {
            guard depth < limits.archiveDepth else {
                throw FabricationPackageError.nestedArchiveLimit
            }
        }

        let nested = files.filter {
            URL(fileURLWithPath: $0.name).pathExtension.lowercased() == "zip"
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !nested.isEmpty else { throw FabricationPackageError.noSupportedLayers }

        var candidates: [(name: String, document: BoardDocument, score: Int)] = []
        for archive in nested {
            try budget.charge("nested archives", 1, maximum: limits.archives, path: archive.name)
            let entries: [ZipEntry]
            do {
                entries = try ZipArchiveReader().read(archive.data, budget: &budget, path: archive.name)
            } catch let error as ImportLimitError { throw error }
              catch let error as GeometryLimitError { throw error }
                  catch is CancellationError { throw CancellationError() }
              catch { continue }
            let archiveName = URL(fileURLWithPath: archive.name).deletingPathExtension().lastPathComponent
            var document: BoardDocument
            do { document = try loadContainer(
                files: entries,
                name: archiveName,
                depth: depth + 1,
                budget: &budget
            ) } catch let error as ImportLimitError { throw error }
                catch let error as GeometryLimitError { throw error }
                  catch is CancellationError { throw CancellationError() }
                catch { continue }
            if document.packageRole == .direct {
                document.packageRole = .nestedArchive
            }
            if document.packageRole == .nestedArchive,
               !document.enclosedSourceArchives.contains(archive.name) {
                document.enclosedSourceArchives.append(archive.name)
            }
            candidates.append((archive.name, document, packageScore(document)))
        }

        guard let bestScore = candidates.map(\.score).max() else {
            throw FabricationPackageError.noSupportedLayers
        }
        let best = candidates.filter { $0.score == bestScore }
        guard best.count == 1, let selection = best.first else {
            throw FabricationPackageError.ambiguousNestedArchives(best.map(\.name))
        }
        return selection.document
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
                    layers.append(drillLayer)
                    drills += drillHits(from: drillLayer)
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
                        layers.append(try gerberParser.parse(data: file.data, fileName: file.name, budget: &budget))
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
                    previews.removeAll { $0.side == side }
                    previews.append(BoardSidePreview(side: side, fileName: file.name, imageData: file.data, validatedImage: decoded))
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

        guard !layers.isEmpty || !drills.isEmpty else { throw FabricationPackageError.noSupportedLayers }
        if !colorful.isEmpty, previews.isEmpty {
            warnings.append(
                "EasyEDA color-silkscreen payloads are present and valid for JLCPCB, but are encrypted for the factory. Add a top/bottom PNG proof to inspect the exact colors locally."
            )
        }

        let preferredBounds = layers.filter { $0.kind == .outline }.compactMap(\.centerlineBounds)
        let allBounds = preferredBounds.isEmpty ? layers.compactMap(\.bounds) : preferredBounds
        var bounds = allBounds.reduce(nil) { partial, next in partial?.union(next) ?? next }
        for drill in drills where bounds == nil {
            let radius = drill.diameter / 2
            let hitBounds = Bounds2D(
                minimum: Point2D(x: drill.center.x - radius, y: drill.center.y - radius),
                maximum: Point2D(x: drill.center.x + radius, y: drill.center.y + radius)
            )
            bounds = bounds?.union(hitBounds) ?? hitBounds
        }
        let safeBounds = bounds.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            ?? Bounds2D(minimum: .zero, maximum: Point2D(x: 100, y: 60))

        return BoardDocument(
            name: name,
            layers: layers,
            drills: drills,
            bounds: safeBounds,
            colorSilkscreens: colorful,
            sidePreviews: previews,
            warnings: warnings
        )
    }

    private func filesInDirectory(_ directory: URL, budget: inout ImportBudget) throws -> [ZipEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [ZipEntry] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard enumerator.level <= limits.directoryDepth else {
                throw ImportLimitError(resource: "directory depth", path: fileURL.path)
            }
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, !isKnownIrrelevant(fileURL) else { continue }
            try budget.file(path: fileURL.path)
            files.append(ZipEntry(
                name: String(fileURL.path.dropFirst(directory.path.count + 1)),
                data: try readFile(fileURL, budget: &budget, isArchive: fileURL.pathExtension.lowercased() == "zip")
            ))
        }
        return files
    }

    private func isKnownIrrelevant(_ url: URL) -> Bool {
        ["pdf", "md", "html", "htm", "json", "yaml", "yml", "step", "stp", "iges", "stl", "ddw", "tgz", "gz", "7z"]
            .contains(url.pathExtension.lowercased())
    }

    private func sidecarImages(beside archive: URL, budget: inout ImportBudget) throws -> [ZipEntry] {
        let parent = archive.deletingLastPathComponent()
        let stem = archive.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_Gerbers", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Gerbers", with: "", options: .caseInsensitive)
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [ZipEntry] = []
        for candidate in candidates {
            let name = candidate.lastPathComponent
            guard name.localizedCaseInsensitiveContains(stem), previewSide(for: name) != nil, isImage(name),
                  try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try budget.file(path: candidate.path)
            result.append(ZipEntry(name: name, data: try readFile(candidate, budget: &budget)))
        }
        return result
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
            productionFiles.append(ZipEntry(name: relativeName, data: file.data))
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

    private func drillHits(from layer: GerberLayer) -> [DrillHit] {
        layer.primitives.compactMap { primitive in
            switch primitive {
            case let .flash(center, shape, polarity) where polarity == .dark:
                let dimensions = shape.dimensions
                return DrillHit(
                    center: center,
                    diameter: max(0.001, min(dimensions.width, dimensions.height)),
                    plated: nil
                )
            case let .line(start, end, width, polarity) where polarity == .dark:
                return DrillHit(center: start, end: end, diameter: max(width, 0.001), plated: nil)
            default:
                return nil
            }
        }
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
