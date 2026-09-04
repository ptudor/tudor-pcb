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
    private static let maximumNestedDepth = 3
    private static let maximumNestedArchives = 12
    private static let maximumNestedExpandedBytes = 768 * 1_024 * 1_024

    public init() { }

    public func load(from url: URL) throws -> BoardDocument {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let files: [ZipEntry]
        if values.isDirectory == true {
            files = try filesInDirectory(url)
        } else if url.pathExtension.lowercased() == "zip" {
            files = try ZipArchiveReader().read(Data(contentsOf: url, options: .mappedIfSafe))
                + sidecarImages(beside: url)
        } else {
            files = [ZipEntry(name: url.lastPathComponent, data: try Data(contentsOf: url, options: .mappedIfSafe))]
        }
        return try load(files: files, name: url.deletingPathExtension().lastPathComponent)
    }

    public func load(files: [ZipEntry], name: String) throws -> BoardDocument {
        var budget = NestedArchiveBudget()
        return try loadContainer(files: files, name: name, depth: 0, budget: &budget)
    }

    private func loadContainer(
        files: [ZipEntry],
        name: String,
        depth: Int,
        budget: inout NestedArchiveBudget
    ) throws -> BoardDocument {
        if let envelope = jlcpcbProductionEnvelope(in: files) {
            var document = try loadFlat(files: envelope.productionFiles, name: name)
            document.packageRole = .jlcpcbProduction
            document.enclosedSourceArchives = envelope.originalArchives
            return document
        }

        do {
            var document = try loadFlat(files: files, name: name)
            if document.layers.contains(where: {
                $0.sourceGenerator?.localizedCaseInsensitiveContains("jlccam") == true
            }) {
                document.packageRole = .jlcpcbProduction
            }
            return document
        } catch FabricationPackageError.noSupportedLayers {
            guard depth < Self.maximumNestedDepth else {
                throw FabricationPackageError.nestedArchiveLimit
            }
        }

        let nested = files.filter {
            URL(fileURLWithPath: $0.name).pathExtension.lowercased() == "zip"
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !nested.isEmpty else { throw FabricationPackageError.noSupportedLayers }

        var candidates: [(name: String, document: BoardDocument, score: Int)] = []
        for archive in nested {
            budget.archiveCount += 1
            guard budget.archiveCount <= Self.maximumNestedArchives else {
                throw FabricationPackageError.nestedArchiveLimit
            }
            guard let entries = try? ZipArchiveReader().read(archive.data) else { continue }
            budget.expandedBytes += entries.reduce(0) { $0 + $1.data.count }
            guard budget.expandedBytes <= Self.maximumNestedExpandedBytes else {
                throw FabricationPackageError.nestedArchiveLimit
            }
            let archiveName = URL(fileURLWithPath: archive.name).deletingPathExtension().lastPathComponent
            guard var document = try? loadContainer(
                files: entries,
                name: archiveName,
                depth: depth + 1,
                budget: &budget
            ) else { continue }
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

    private func loadFlat(files: [ZipEntry], name: String) throws -> BoardDocument {
        let gerberParser = GerberParser()
        let drillParser = ExcellonParser()
        var layers: [GerberLayer] = []
        var drills: [DrillHit] = []
        var colorful: [ColorSilkscreenInfo] = []
        var previews: [BoardSidePreview] = []
        var warnings: [String] = []

        for file in files.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let contents = String(decoding: file.data.prefix(8_192), as: UTF8.self)
            let kind = LayerClassifier.classify(fileName: file.name, contents: contents)
            if isJLCCamDrill(file.name, contents: contents) {
                do {
                    let drillLayer = try gerberParser.parse(data: file.data, fileName: file.name)
                    layers.append(drillLayer)
                    drills += drillHits(from: drillLayer)
                } catch {
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
                    drills += try drillParser.parse(data: file.data, fileName: file.name)
                } catch {
                    warnings.append("\(file.name): \(error.localizedDescription)")
                }
            default:
                if let side = previewSide(for: file.name), isImage(file.name) {
                    previews.removeAll { $0.side == side }
                    previews.append(BoardSidePreview(side: side, fileName: file.name, imageData: file.data))
                } else if LayerClassifier.isGerber(file.name, contents: contents) {
                    do {
                        layers.append(try gerberParser.parse(data: file.data, fileName: file.name))
                    } catch GerberParseError.missingGeometry where kind == .documentation || kind == .other {
                        // Empty documentation and auxiliary Gerbers are common and harmless.
                    } catch {
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

    private func filesInDirectory(_ directory: URL) throws -> [ZipEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [ZipEntry] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 192 * 1_024 * 1_024 else { continue }
            files.append(ZipEntry(
                name: fileURL.path.replacingOccurrences(of: directory.path + "/", with: ""),
                data: try Data(contentsOf: fileURL, options: .mappedIfSafe)
            ))
        }
        return files
    }

    private func sidecarImages(beside archive: URL) -> [ZipEntry] {
        let parent = archive.deletingLastPathComponent()
        let stem = archive.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_Gerbers", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-Gerbers", with: "", options: .caseInsensitive)
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return candidates.compactMap { candidate in
            let name = candidate.lastPathComponent
            guard name.localizedCaseInsensitiveContains(stem),
                  previewSide(for: name) != nil,
                  isImage(name),
                  let values = try? candidate.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 48 * 1_024 * 1_024,
                  let data = try? Data(contentsOf: candidate, options: .mappedIfSafe) else { return nil }
            return ZipEntry(name: name, data: data)
        }
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

private struct NestedArchiveBudget {
    var archiveCount = 0
    var expandedBytes = 0
}

private struct JLCPCBEnvelope {
    var productionFiles: [ZipEntry]
    var originalArchives: [String]
}
