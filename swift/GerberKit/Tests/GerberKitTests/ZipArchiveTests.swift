import Foundation
import Testing
@testable import GerberKit

private func put16(_ value: UInt16, _ offset: Int, in data: inout Data) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}
private func put32(_ value: UInt32, _ offset: Int, in data: inout Data) {
    for i in 0..<4 { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
}
private func get32(_ data: Data, _ offset: Int) -> UInt32 {
    (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
}
private func withComment(_ comment: Data) -> Data {
    var data = storedZIP([("board.gtl", Data("layer".utf8))])
    put16(UInt16(comment.count), data.count - 2, in: &data)
    data.append(comment)
    return data
}

@Test func zipCommentsCannotMasqueradeAsEndRecords() throws {
    var comment = Data("comment PK".utf8)
    comment.append(contentsOf: [5, 6])
    comment.append(Data(repeating: 0, count: 30))
    for data in [withComment(comment), withComment(Data(repeating: 65, count: 65_535))] {
        #expect(try ZipArchiveReader().read(data) == [ZipEntry(name: "board.gtl", data: Data("layer".utf8))])
    }
}

@Test func zipRejectsTruncatedAndInconsistentHeaders() throws {
    let original = storedZIP([("a.gtl", Data([1, 2, 3]))])
    for length in 0..<original.count {
        #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(Data(original.prefix(length))) }
    }
    let central = 30 + 5 + 3
    let eocd = original.count - 22
    for (offset, value) in [(0, UInt8(0)), (30, UInt8(98)), (18, UInt8(2)), (central + 20, UInt8(2)),
                            (central + 42, UInt8(1)), (eocd + 10, UInt8(2)), (eocd + 12, UInt8(1)), (eocd + 16, UInt8(1))] {
        var data = original
        data[offset] = value
        #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(data) }
    }
    var badCRC = original
    badCRC[35] = 99
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(badCRC) }
}

@Test func zipAcceptsDataDescriptorsAndEmptyEntries() throws {
    for signature in [false, true] {
        var data = storedZIP([("a.gtl", Data([1, 2, 3]))])
        let central = 38
        var descriptor = Data(repeating: 0, count: signature ? 16 : 12)
        let start = signature ? 4 : 0
        if signature { put32(0x0807_4B50, 0, in: &descriptor) }
        put32(get32(data, 14), start, in: &descriptor)
        put32(3, start + 4, in: &descriptor)
        put32(3, start + 8, in: &descriptor)
        put16(8, 6, in: &data)
        for offset in [14, 18, 22] { put32(0, offset, in: &data) }
        put16(8, central + 8, in: &data)
        data.insert(contentsOf: descriptor, at: central)
        put32(UInt32(central + descriptor.count), data.count - 6, in: &data)
        #expect(try ZipArchiveReader().read(data) == [ZipEntry(name: "a.gtl", data: Data([1, 2, 3]))])
    }
    #expect(try ZipArchiveReader().read(storedZIP([])).isEmpty)
    #expect(try ZipArchiveReader().read(storedZIP([("empty.gtl", Data())])).first?.data.isEmpty == true)
    let emptyDeflate = try #require(Bundle.module.url(forResource: "Fixtures/empty-deflate", withExtension: "zip"))
    #expect(try ZipArchiveReader().read(Data(contentsOf: emptyDeflate)).first?.data.isEmpty == true)
}

@Test func zipRejectsOverlappingPayloadsAndUnsupportedModes() throws {
    var overlap = storedZIP([("a", Data([1])), ("a", Data([1]))])
    let firstCentral = 64
    put32(0, firstCentral + 47 + 42, in: &overlap)
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(overlap) }
    let original = storedZIP([("a", Data([1]))])
    let central = 32
    var encrypted = original
    put16(1, 6, in: &encrypted); put16(1, central + 8, in: &encrypted)
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(encrypted) }
    var compression = original
    put16(99, 8, in: &compression); put16(99, central + 10, in: &compression)
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(compression) }
    var zip64 = original
    put16(.max, zip64.count - 12, in: &zip64)
    do { _ = try ZipArchiveReader().read(zip64); Issue.record("Accepted ZIP64") }
    catch ZipArchiveError.unsupportedZIP64 { }
    var split = original
    put16(1, split.count - 18, in: &split)
    do { _ = try ZipArchiveReader().read(split); Issue.record("Accepted split archive") }
    catch ZipArchiveError.unsupportedSplitArchive { }
}
