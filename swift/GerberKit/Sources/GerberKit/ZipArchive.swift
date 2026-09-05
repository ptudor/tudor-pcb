import Foundation
import zlib

public enum ZipArchiveError: Error, LocalizedError, Sendable {
    case invalidArchive
    case unsupportedZIP64
    case unsupportedSplitArchive
    case unsupportedCompression(UInt16)
    case encryptedEntry(String)
    case unsafeSize(String)
    case decompressionFailed(String, Int32)
    case checksumMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedZIP64: "ZIP64 archives are not supported."
        case .unsupportedSplitArchive: "Split ZIP archives are not supported."
        case .invalidArchive: "The ZIP central directory is missing or damaged."
        case let .unsupportedCompression(method): "ZIP compression method \(method) is not supported."
        case let .encryptedEntry(name): "\(name) is encrypted at the ZIP level."
        case let .unsafeSize(name): "\(name) exceeds the safe in-memory size limit."
        case let .decompressionFailed(name, code): "Could not decompress \(name) (zlib \(code))."
        case let .checksumMismatch(name): "\(name) failed its ZIP checksum."
        }
    }
}

public struct ZipEntry: Sendable, Hashable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Small, dependency-free ZIP reader for fabrication packages. It intentionally
/// extracts into memory rather than the filesystem, eliminating path traversal.
public struct ZipArchiveReader: Sendable {
    private static let maximumEntrySize = 192 * 1_024 * 1_024
    private static let maximumArchiveSize = 768 * 1_024 * 1_024

    private let limits: ImportLimits
    public init(limits: ImportLimits = .init()) { self.limits = limits }

    public func read(_ archive: Data) throws -> [ZipEntry] {
        var budget = ImportBudget(limits: limits)
        try budget.input(archive.count, path: "ZIP", isArchive: true)
        return try read(archive, budget: &budget, path: "ZIP")
    }

    func read(_ archive: Data, budget: inout ImportBudget, path: String) throws -> [ZipEntry] {
        let eocd = try endOfCentralDirectory(in: archive)
        let entryCount = Int(archive.uint16(at: eocd + 10))
        let directoryOffset = Int(archive.uint32(at: eocd + 16))
        let directoryEnd = directoryOffset + Int(archive.uint32(at: eocd + 12))
        guard entryCount <= 20_000 else { throw ZipArchiveError.unsafeSize(path) }
        var cursor = directoryOffset
        var records: [Record] = []
        records.reserveCapacity(entryCount)

        // Validate all metadata/ranges before allocating any decompressed payload.
        for _ in 0..<entryCount {
            try Task.checkCancellation()
            guard cursor + 46 <= directoryEnd, archive.uint32(at: cursor) == 0x0201_4B50 else {
                throw ZipArchiveError.invalidArchive
            }
            let flags = archive.uint16(at: cursor + 8)
            let method = archive.uint16(at: cursor + 10)
            let expectedCRC = archive.uint32(at: cursor + 16)
            let compressedSize = Int(archive.uint32(at: cursor + 20))
            let uncompressedSize = Int(archive.uint32(at: cursor + 24))
            let nameLength = Int(archive.uint16(at: cursor + 28))
            let extraLength = Int(archive.uint16(at: cursor + 30))
            let commentLength = Int(archive.uint16(at: cursor + 32))
            let localOffset = Int(archive.uint32(at: cursor + 42))
            guard compressedSize != Int(UInt32.max), uncompressedSize != Int(UInt32.max), localOffset != Int(UInt32.max) else {
                throw ZipArchiveError.unsupportedZIP64
            }
            guard archive.uint16(at: cursor + 34) == 0 else { throw ZipArchiveError.unsupportedSplitArchive }
            let recordEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard recordEnd <= directoryEnd else { throw ZipArchiveError.invalidArchive }
            try validateExtra(archive, range: (cursor + 46 + nameLength)..<(cursor + 46 + nameLength + extraLength))
            let nameData = archive.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let name = String(data: nameData, encoding: .utf8) ?? (flags & 0x0800 == 0 ? String(data: nameData, encoding: .isoLatin1) : nil), !name.isEmpty else {
                throw ZipArchiveError.invalidArchive
            }
            try budget.file(path: path + "/" + name)
            guard flags & 0x0001 == 0 else { throw ZipArchiveError.encryptedEntry(name) }
            guard method == 0 || method == 8 else { throw ZipArchiveError.unsupportedCompression(method) }
            guard uncompressedSize <= Self.maximumEntrySize, compressedSize <= Self.maximumEntrySize else {
                throw ZipArchiveError.unsafeSize(name)
            }
            guard method != 0 || compressedSize == uncompressedSize else { throw ZipArchiveError.invalidArchive }
            guard localOffset + 30 <= directoryOffset, archive.uint32(at: localOffset) == 0x0403_4B50,
                  archive.uint16(at: localOffset + 4) == archive.uint16(at: cursor + 6),
                  archive.uint16(at: localOffset + 6) == flags,
                  archive.uint16(at: localOffset + 8) == method else { throw ZipArchiveError.invalidArchive }
            let localNameLength = Int(archive.uint16(at: localOffset + 26))
            let localExtraLength = Int(archive.uint16(at: localOffset + 28))
            let dataOffset = localOffset + 30 + localNameLength + localExtraLength
            let dataEnd = dataOffset + compressedSize
            guard dataEnd <= directoryOffset, localNameLength == nameLength,
                  archive[(localOffset + 30)..<(localOffset + 30 + localNameLength)] == nameData else {
                throw ZipArchiveError.invalidArchive
            }
            try validateExtra(archive, range: (localOffset + 30 + localNameLength)..<dataOffset)
            var localEnd = dataEnd
            if flags & 0x0008 == 0 {
                guard archive.uint32(at: localOffset + 14) == expectedCRC,
                      archive.uint32(at: localOffset + 18) == compressedSize,
                      archive.uint32(at: localOffset + 22) == uncompressedSize else { throw ZipArchiveError.invalidArchive }
            } else {
                guard [0, expectedCRC].contains(archive.uint32(at: localOffset + 14)),
                      [0, UInt32(compressedSize)].contains(archive.uint32(at: localOffset + 18)),
                      [0, UInt32(uncompressedSize)].contains(archive.uint32(at: localOffset + 22)) else {
                    throw ZipArchiveError.invalidArchive
                }
                let descriptor = dataEnd + (archive.uint32(at: dataEnd) == 0x0807_4B50 ? 4 : 0)
                localEnd = descriptor + 12
                guard localEnd <= directoryOffset,
                      archive.uint32(at: descriptor) == expectedCRC,
                      archive.uint32(at: descriptor + 4) == compressedSize,
                      archive.uint32(at: descriptor + 8) == uncompressedSize else { throw ZipArchiveError.invalidArchive }
            }
            try budget.checkFileSize(uncompressedSize, path: path + "/" + name)
            try budget.checkFileSize(compressedSize, path: path + "/" + name)
            try budget.charge("compressed bytes", compressedSize, maximum: min(Self.maximumArchiveSize, budget.limits.compressedBytes), path: path)
            try budget.charge("expanded bytes", uncompressedSize, maximum: min(Self.maximumArchiveSize, budget.limits.expandedBytes), path: path)
            try budget.charge("allocations", compressedSize, maximum: budget.limits.allocationBytes, path: path)
            for _ in 0..<2 {
                try budget.charge("allocations", uncompressedSize, maximum: budget.limits.allocationBytes, path: path)
            }
            records.append(Record(name: name, method: method, crc: expectedCRC, expanded: uncompressedSize,
                                  payload: dataOffset..<dataEnd, local: localOffset..<localEnd))
            cursor = recordEnd
        }
        guard cursor == directoryEnd else { throw ZipArchiveError.invalidArchive }
        var previousEnd = 0
        for record in records.sorted(by: { $0.local.lowerBound < $1.local.lowerBound }) {
            guard record.local.lowerBound >= previousEnd else { throw ZipArchiveError.invalidArchive }
            previousEnd = record.local.upperBound
        }
        var entries: [ZipEntry] = []
        for record in records {
            try Task.checkCancellation()
            let compressed = archive.subdata(in: record.payload)
            let payload = record.method == 0 ? compressed : try inflateRaw(compressed, expectedSize: record.expanded, name: record.name)
            guard payload.count == record.expanded else { throw ZipArchiveError.decompressionFailed(record.name, Z_DATA_ERROR) }
            let actualCRC: UInt32 = payload.withUnsafeBytes { bytes in
                UInt32(crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(payload.count)))
            }
            guard actualCRC == record.crc else { throw ZipArchiveError.checksumMismatch(record.name) }
            if !record.name.hasSuffix("/") { entries.append(ZipEntry(name: record.name, data: payload)) }
        }
        return entries
    }

    private struct Record {
        let name: String
        let method: UInt16
        let crc: UInt32
        let expanded: Int
        let payload: Range<Int>
        let local: Range<Int>
    }

    private func validateExtra(_ data: Data, range: Range<Int>) throws {
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            guard cursor + 4 <= range.upperBound else { throw ZipArchiveError.invalidArchive }
            let tag = data.uint16(at: cursor)
            let size = Int(data.uint16(at: cursor + 2))
            guard cursor + 4 + size <= range.upperBound else { throw ZipArchiveError.invalidArchive }
            if tag == 1 { throw ZipArchiveError.unsupportedZIP64 }
            cursor += 4 + size
        }
    }

    private func endOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else { throw ZipArchiveError.invalidArchive }
        var unsupported: ZipArchiveError?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            guard data.uint32(at: offset) == 0x0605_4B50,
                  offset + 22 + Int(data.uint16(at: offset + 20)) == data.count else { continue }
            let count = Int(data.uint16(at: offset + 10))
            let size = Int(data.uint32(at: offset + 12))
            let directory = Int(data.uint32(at: offset + 16))
            if count == Int(UInt16.max) || size == Int(UInt32.max) || directory == Int(UInt32.max) {
                unsupported = .unsupportedZIP64; continue
            }
            if data.uint16(at: offset + 4) != 0 || data.uint16(at: offset + 6) != 0 {
                unsupported = .unsupportedSplitArchive; continue
            }
            guard data.uint16(at: offset + 8) == count, directory + size == offset else { continue }
            var cursor = directory
            var actual = 0
            while cursor + 46 <= offset, data.uint32(at: cursor) == 0x0201_4B50, actual < count {
                cursor += 46 + Int(data.uint16(at: cursor + 28)) + Int(data.uint16(at: cursor + 30)) + Int(data.uint16(at: cursor + 32))
                actual += 1
            }
            guard actual == count, cursor == offset else { continue }
            return offset
        }
        throw unsupported ?? .invalidArchive
    }

    private func inflateRaw(_ compressed: Data, expectedSize: Int, name: String) throws -> Data {
        var output = [UInt8](repeating: 0, count: max(1, expectedSize))
        let outputCapacity = output.count
        var stream = z_stream()
        let initialization = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initialization == Z_OK else { throw ZipArchiveError.decompressionFailed(name, initialization) }
        defer { inflateEnd(&stream) }

        let result: Int32 = compressed.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, stream.total_in == compressed.count, stream.total_out == expectedSize else { throw ZipArchiveError.decompressionFailed(name, result) }
        return Data(output.prefix(Int(stream.total_out)))
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[index(startIndex, offsetBy: offset)])
            | UInt16(self[index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[index(startIndex, offsetBy: offset)])
            | UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8
            | UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16
            | UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
    }
}
