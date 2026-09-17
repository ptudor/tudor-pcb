import Foundation

/// Cumulative limits apply to an entire import, including nested containers and proofs.
/// Allocation accounting is conservative: retained inputs, decoded text, and temporary
/// decompression copies are charged together, rather than relying on allocator timing.
public struct ImportLimits: Sendable {
    public var inputBytes = 768 * 1_024 * 1_024
    public var fileBytes = 192 * 1_024 * 1_024
    public var files = 20_000
    public var directoryDepth = 32
    public var compressedBytes = 768 * 1_024 * 1_024
    public var expandedBytes = 768 * 1_024 * 1_024
    public var decodedBytes = 768 * 1_024 * 1_024
    public var allocationBytes = 2 * 1_024 * 1_024 * 1_024
    public var geometryObjects = 1_000_000
    public var geometryPoints = 4_000_000
    public var imageFileBytes = 48 * 1_024 * 1_024
    public var imageDimension = 16_384
    public var imagePixels = 64_000_000
    public var imageFrames = 1
    public var archiveDepth = 3
    public var archives = 12
    public init() { }
}

public struct ImportLimitError: Error, LocalizedError, Sendable, Equatable {
    public let resource: String
    public let path: String
    public var errorDescription: String? { DiagnosticStrings.importLimitExceeded(path: path, resource: DiagnosticStrings.limitResource(resource)) }
}

struct ImportBudget {
    let limits: ImportLimits
    private var used: [String: Int] = [:]

    init(limits: ImportLimits) { self.limits = limits }

    mutating func charge(_ resource: String, _ amount: Int, maximum: Int, path: String) throws {
        try Task.checkCancellation()
        let current = used[resource, default: 0]
        guard amount >= 0, maximum >= 0, current <= maximum, amount <= maximum - current else {
            throw ImportLimitError(resource: resource, path: path)
        }
        used[resource] = current + amount
    }

    func remaining(_ resource: String, maximum: Int) -> Int {
        max(0, maximum - used[resource, default: 0])
    }

    func checkFileSize(_ size: Int, path: String) throws {
        guard size >= 0, size <= limits.fileBytes else {
            throw ImportLimitError(resource: "file bytes", path: path)
        }
    }

    mutating func input(_ size: Int, path: String, isArchive: Bool = false) throws {
        if !isArchive { try checkFileSize(size, path: path) }
        try charge("input bytes", size, maximum: limits.inputBytes, path: path)
        try charge("allocations", size, maximum: limits.allocationBytes, path: path)
    }

    mutating func file(path: String) throws {
        try charge("files", 1, maximum: limits.files, path: path)
    }

    mutating func decodedText(_ bytes: Int, path: String) throws {
        // UTF-16 storage and parser/tokenization scratch, without unchecked products.
        for _ in 0..<4 {
            try charge("decoded bytes", bytes, maximum: limits.decodedBytes, path: path)
            try charge("allocations", bytes, maximum: limits.allocationBytes, path: path)
        }
    }
}
