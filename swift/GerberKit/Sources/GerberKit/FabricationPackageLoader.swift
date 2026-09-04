import Foundation

public enum FabricationPackageError: Error, LocalizedError, Sendable {
    case noSupportedLayers

    public var errorDescription: String? {
        switch self {
        case .noSupportedLayers:
            "No Gerber or Excellon layers were found in this package."
        }
    }
}

public struct FabricationPackageLoader: Sendable {
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
        let gerberParser = GerberParser()
        let drillParser = ExcellonParser()
        var layers: [GerberLayer] = []
        var drills: [DrillHit] = []
        var colorful: [ColorSilkscreenInfo] = []
        var previews: [BoardSidePreview] = []
        var warnings: [String] = []

        for file in files.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let kind = LayerClassifier.classify(fileName: file.name)
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
                } else if LayerClassifier.isGerber(file.name) {
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
}
