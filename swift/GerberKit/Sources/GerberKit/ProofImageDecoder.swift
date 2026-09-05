import CoreGraphics
import Foundation
import ImageIO

public struct ProofImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let sourceWidth: Int
    public let sourceHeight: Int
}

public enum ProofImageError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case let .invalid(name): "\(name): the proof image format, metadata, or pixel data is invalid or unsupported." }
    }
}

public enum ProofImageDecoder {
    public static func decode(_ data: Data, name: String, maximumDimension: Int = 4096,
                              limits: ImportLimits = .init()) throws -> ProofImage {
        var budget = ImportBudget(limits: limits)
        try budget.input(data.count, path: name)
        return try decode(data, name: name, maximumDimension: maximumDimension, budget: &budget)
    }

    static func decode(_ data: Data, name: String, maximumDimension: Int = 4096,
                       budget: inout ImportBudget) throws -> ProofImage {
        try Task.checkCancellation()
        guard data.count <= budget.limits.imageFileBytes else { throw ImportLimitError(resource: "image input bytes", path: name) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "public.tiff", "public.heic", "public.heif"].contains(type) else {
            throw ProofImageError.invalid(name)
        }
        let frames = CGImageSourceGetCount(source)
        guard frames > 0, frames <= budget.limits.imageFrames else { throw ImportLimitError(resource: "image frames", path: name) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw ProofImageError.invalid(name) }
        let w = width.doubleValue, h = height.doubleValue
        guard w.isFinite, h.isFinite, w > 0, h > 0, w.rounded() == w, h.rounded() == h,
              w <= Double(min(16_384, budget.limits.imageDimension)), h <= Double(min(16_384, budget.limits.imageDimension)),
              w * h <= Double(budget.limits.imagePixels) else { throw ImportLimitError(resource: "image dimensions/pixels", path: name) }
        let sourceWidth = Int(w), sourceHeight = Int(h)
        let (pixels, overflow) = sourceWidth.multipliedReportingOverflow(by: sourceHeight)
        guard !overflow, pixels <= Int.max / 4 else { throw ImportLimitError(resource: "image pixels", path: name) }
        // Charge full decoder scratch conservatively as well as the thumbnail.
        try budget.charge("allocations", pixels * 4, maximum: budget.limits.allocationBytes, path: name)
        let dimension = min(max(maximumDimension, 1), 4096)
        let scale = min(1, Double(dimension) / max(w, h))
        let thumbnailBytes = Int(ceil(w * scale)) * Int(ceil(h * scale)) * 4
        try budget.charge("decoded bytes", thumbnailBytes, maximum: budget.limits.decodedBytes, path: name)
        try budget.charge("allocations", thumbnailBytes, maximum: budget.limits.allocationBytes, path: name)
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ProofImageError.invalid(name) }
        try Task.checkCancellation()
        return ProofImage(cgImage: image, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    /// Call from an owned background task. Coordination and security scope cover
    /// the complete provider read and decode, including every failure exit.
    public static func read(_ url: URL, side: GerberSide, limits: ImportLimits = .init()) async throws -> BoardSidePreview {
        let coordination = ProofReadCoordination()
        let task = Task.detached(priority: .userInitiated) {
            try readCoordinated(url, side: side, limits: limits, coordinator: coordination.coordinator)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: {
            task.cancel()
            coordination.coordinator.cancel()
        }
    }

    private static func readCoordinated(_ url: URL, side: GerberSide, limits: ImportLimits,
                                       coordinator: NSFileCoordinator) throws -> BoardSidePreview {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        var coordinationError: NSError?
        var result: Result<BoardSidePreview, any Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                try Task.checkCancellation()
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size >= 0, size <= limits.imageFileBytes, size < Int.max else {
                    throw ImportLimitError(resource: "image input bytes", path: url.path)
                }
                var budget = ImportBudget(limits: limits)
                try budget.input(size, path: url.path)
                let handle = try FileHandle(forReadingFrom: coordinated)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: size + 1) ?? Data()
                guard data.count <= size else { throw ImportLimitError(resource: "image changed during read", path: url.path) }
                let image = try decode(data, name: url.lastPathComponent, budget: &budget)
                return BoardSidePreview(side: side, fileName: url.lastPathComponent, imageData: data, validatedImage: image)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ProofImageError.invalid(url.lastPathComponent) }
        return try result.get()
    }
}


// NSFileCoordinator cancellation is designed to be called while coordination is
// pending; the read callback itself is serialized by coordinate(readingItemAt:).
private final class ProofReadCoordination: @unchecked Sendable {
    let coordinator = NSFileCoordinator()
}
