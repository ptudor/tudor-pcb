import Foundation
import Testing
@testable import GerberKit

private let budgetLayer = Data("%FSLAX24Y24*%%MOMM*%%ADD10C,1*%D10*X0Y0D03*M02*".utf8)

@Test func importBudgetsRejectBeforeLoadingLargeOrNumerousFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for i in 0..<4 { try budgetLayer.write(to: root.appending(path: "board\(i).gtl")) }
    var limits = ImportLimits()
    limits.inputBytes = budgetLayer.count * 3
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(from: root) }
    limits = ImportLimits()
    limits.files = 3
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(from: root) }
    limits = ImportLimits()
    limits.fileBytes = budgetLayer.count - 1
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(from: root.appending(path: "board0.gtl")) }
    // Known unrelated assets do not consume reads/input bytes.
    try Data(repeating: 0, count: 4096).write(to: root.appending(path: "manual.pdf"))
    limits = ImportLimits()
    limits.inputBytes = budgetLayer.count * 4
    #expect(try FabricationPackageLoader(limits: limits).load(from: root).layers.count == 4)
}

@Test func zipBudgetsIncludeNestedExpansionAndCompressedInput() throws {
    let inner = storedZIP([("board.gtl", budgetLayer)])
    let outer = storedZIP([("board.zip", inner)])
    var limits = ImportLimits()
    limits.expandedBytes = inner.count + budgetLayer.count - 1
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "outer.zip", data: outer)], name: "outer") }
    limits.expandedBytes += 1
    #expect(try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "outer.zip", data: outer)], name: "outer").layers.count == 1)
    limits = ImportLimits()
    limits.compressedBytes = budgetLayer.count - 1
    #expect(throws: ImportLimitError.self) { try ZipArchiveReader(limits: limits).read(inner) }
    var mismatch = inner
    let central = 30 + "board.gtl".utf8.count + budgetLayer.count
    mismatch[central + 24] = UInt8(budgetLayer.count - 1)
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(mismatch) }
}

@Test func sidecarAndDecodedTextAndGeometryBudgetsAreShared() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let archive = root.appending(path: "board.zip")
    try storedZIP([("board.gtl", budgetLayer)]).write(to: archive)
    for ext in ["png", "jpg", "tiff", "heic"] { try Data([0]).write(to: root.appending(path: "board_top.\(ext)")) }
    var limits = ImportLimits()
    limits.files = 4
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(from: archive) }
    limits = ImportLimits()
    limits.decodedBytes = budgetLayer.count * 4 - 1
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "board.gtl", data: budgetLayer)], name: "board") }
    limits = ImportLimits()
    limits.geometryObjects = 1
    #expect(throws: ImportLimitError.self) {
        try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "a.gtl", data: budgetLayer), ZipEntry(name: "b.gbl", data: budgetLayer)], name: "board")
    }
}

@Test func rejectsPaddedDeflateAndChecksDepthAndPeakAllocation() throws {
    let fixture = try #require(Bundle.module.url(forResource: "Fixtures/padded-deflate", withExtension: "zip"))
    #expect(throws: ZipArchiveError.self) { try ZipArchiveReader().read(Data(contentsOf: fixture)) }
    var limits = ImportLimits()
    limits.allocationBytes = budgetLayer.count
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "board.gtl", data: budgetLayer)], name: "board") }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let nested = root.appending(path: "a/b")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try budgetLayer.write(to: nested.appending(path: "board.gtl"))
    limits = ImportLimits()
    limits.directoryDepth = 1
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(from: root) }
}
