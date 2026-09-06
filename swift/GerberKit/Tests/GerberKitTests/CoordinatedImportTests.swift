import Foundation
import Testing
@testable import GerberKit

@Test func coordinatedOpeningInPlaceReadsStandaloneAndZIPWithoutWritingSources() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let layer = Data("%FSLAX24Y24*%%MOMM*%%ADD10C,1*%D10*X10000Y10000D03*M02*".utf8)
    let archive = storedZIP([("board.gtl", layer)])
    let worker = FabricationWorkSession()
    for (name, bytes) in [("board.gtl", layer), ("board.zip", archive)] {
        let url = folder.appending(path: name)
        try bytes.write(to: url)
        let before = try url.resourceValues(forKeys: [.contentModificationDateKey])
        let document = try await worker.load(url)
        #expect(document.layers.count == 1)
        #expect(document.layers[0].primitives.count == 1)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before.contentModificationDate)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["board.gtl", "board.zip"])
    do { _ = try await worker.load(folder.appending(path: "missing.gtl")); Issue.record("Missing coordinated source should fail") }
    catch { #expect((error as NSError).domain == NSCocoaErrorDomain) }
}
