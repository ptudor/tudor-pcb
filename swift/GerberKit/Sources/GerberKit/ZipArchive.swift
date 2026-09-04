import Foundation
import zlib

public enum ZipArchiveError: Error, LocalizedError, Sendable {
    case invalidArchive
    case unsupportedCompression(UInt16)
    case encryptedEntry(String)
    case unsafeSize(String)
    case decompressionFailed(String, Int32)
    case checksumMismatch(String)

    public var errorDescription: String? {
        switch self {
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

    public init() { }

    public func read(_ archive: Data) throws -> [ZipEntry] {
        guard let eocd = endOfCentralDirectory(in: archive) else {
            throw ZipArchiveError.invalidArchive
        }
        let entryCount = Int(archive.uint16(at: eocd + 10))
        let directoryOffset = Int(archive.uint32(at: eocd + 16))
        guard entryCount <= 20_000, directoryOffset >= 0, directoryOffset < archive.count else {
            throw ZipArchiveError.invalidArchive
        }

        var cursor = directoryOffset
        var totalOutput = 0
        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard archive.uint32(at: cursor) == 0x0201_4B50, cursor + 46 <= archive.count else {
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
            let recordEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard recordEnd <= archive.count else { throw ZipArchiveError.invalidArchive }

            let nameData = archive.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "unnamed-entry"
            cursor = recordEnd

            if name.hasSuffix("/") { continue }
            guard flags & 0x0001 == 0 else { throw ZipArchiveError.encryptedEntry(name) }
            guard uncompressedSize <= Self.maximumEntrySize,
                  compressedSize <= archive.count,
                  totalOutput + uncompressedSize <= Self.maximumArchiveSize else {
                throw ZipArchiveError.unsafeSize(name)
            }
            guard archive.uint32(at: localOffset) == 0x0403_4B50, localOffset + 30 <= archive.count else {
                throw ZipArchiveError.invalidArchive
            }
            let localNameLength = Int(archive.uint16(at: localOffset + 26))
            let localExtraLength = Int(archive.uint16(at: localOffset + 28))
            let dataOffset = localOffset + 30 + localNameLength + localExtraLength
            guard dataOffset >= 0, dataOffset + compressedSize <= archive.count else {
                throw ZipArchiveError.invalidArchive
            }
            let compressed = archive.subdata(in: dataOffset..<(dataOffset + compressedSize))
            let payload: Data
            switch method {
            case 0:
                payload = compressed
            case 8:
                payload = try inflateRaw(compressed, expectedSize: uncompressedSize, name: name)
            default:
                throw ZipArchiveError.unsupportedCompression(method)
            }

            guard payload.count == uncompressedSize else {
                throw ZipArchiveError.decompressionFailed(name, Z_DATA_ERROR)
            }
            let actualCRC: UInt32 = payload.withUnsafeBytes { bytes in
                let base = bytes.bindMemory(to: Bytef.self).baseAddress
                return UInt32(crc32(0, base, uInt(payload.count)))
            }
            guard actualCRC == expectedCRC else { throw ZipArchiveError.checksumMismatch(name) }
            totalOutput += payload.count
            entries.append(ZipEntry(name: name, data: payload))
        }

        return entries
    }

    private func endOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if data.uint32(at: offset) == 0x0605_4B50 { return offset }
            offset -= 1
        }
        return nil
    }

    private func inflateRaw(_ compressed: Data, expectedSize: Int, name: String) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
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
        guard result == Z_STREAM_END else { throw ZipArchiveError.decompressionFailed(name, result) }
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
