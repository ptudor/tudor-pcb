import Foundation
import Testing
@testable import GerberKit

@Test func deniedTraversalOversizedExpectedLayerAndAllFailedInputsRetainCauses() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let header = "%FSLAX24Y24*%%MOMM*%"
    let valid = Data((header + "%ADD10C,1*%D10*X10000Y10000D03*M02*").utf8)
    try valid.write(to: root.appending(path: "board.gtl"))
    let denied = root.appending(path: "denied")
    try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
    try valid.write(to: denied.appending(path: "inner.g1"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
    do { _ = try FabricationPackageLoader().load(from: root); Issue.record("Accepted an unreadable fabrication subtree") }
    catch { #expect(error.localizedDescription.contains("denied")) }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
    let oversized = root.appending(path: "oversized.gbl")
    #expect(FileManager.default.createFile(atPath: oversized.path, contents: nil))
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: UInt64(193 * 1024 * 1024))
    try handle.close()
    do { _ = try FabricationPackageLoader().load(from: root); Issue.record("Accepted oversized expected copper") }
    catch { #expect(error is ImportLimitError); #expect(error.localizedDescription.contains("oversized.gbl")) }
    let invalid = [ZipEntry(name: "bad.gtl", data: Data((header + "D99*X0Y0D03*M02*").utf8)),
                   ZipEntry(name: "bad.gbl", data: Data((header + "%ADD*%M02*").utf8))]
    do { _ = try FabricationPackageLoader().load(files: invalid, name: "malformed"); Issue.record("Accepted all-malformed package") }
    catch { #expect(error.localizedDescription.contains("bad.gtl")); #expect(error.localizedDescription.contains("bad.gbl")) }
    let partial = try FabricationPackageLoader().load(files: invalid + [ZipEntry(name: "board.gko", data: valid)], name: "partial")
    #expect(partial.warnings.contains { $0.contains("bad.gtl") })
    #expect(partial.warnings.contains { $0.contains("bad.gbl") })
}
