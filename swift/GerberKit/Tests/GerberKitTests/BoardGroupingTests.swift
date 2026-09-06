import Foundation
import Testing
@testable import GerberKit

func groupingOutline(_ size: Int) -> Data {
    Data("%FSLAX24Y24*%%MOMM*%%ADD10C,0.1*%D10*X0Y0D02*X\(size*10000)Y0D01*Y\(size*10000)D01*X0D01*Y0D01*M02*".utf8)
}

@Test func separateDirectoriesEnvelopesAndProjectsCannotMerge() throws {
    for names in [["a/board.gko", "b/board.gko"], ["a.gko", "b.gko"]] {
        do {
            _ = try FabricationPackageLoader().load(files: [ZipEntry(name: names[0], data: groupingOutline(10)), ZipEntry(name: names[1], data: groupingOutline(20))], name: "mixed")
            Issue.record("Merged board sets")
        } catch FabricationPackageError.ambiguousBoardSets(let paths) { #expect(paths.count == 2) }
    }
    let jlc = Data("G04 -- output software:jlccam pro v3.4.8 *".utf8) + groupingOutline(10)
    var files: [ZipEntry] = []
    for prefix in ["a", "b"] { for layer in ["ko", "tl", "bl", "to"] { files.append(ZipEntry(name: "\(prefix)/ok/\(layer)", data: jlc)) } }
    #expect(throws: FabricationPackageError.self) { try FabricationPackageLoader().load(files: files, name: "two-envelopes") }
    let duplicate = try ZipArchiveReader().read(storedZIP([("board.gko", groupingOutline(10)), ("board.gko", groupingOutline(20))]))
    #expect(throws: FabricationPackageError.self) { try FabricationPackageLoader().load(files: duplicate, name: "duplicate") }
}

@Test func auxiliaryOrIncompleteRootDoesNotHideEnclosedBoard() throws {
    let nested = storedZIP([("board.gko", groupingOutline(20)), ("board.gtl", groupingOutline(20))])
    for auxiliary in ["drawing.gdd", "partial.gtl"] {
        let document = try FabricationPackageLoader().load(files: [ZipEntry(name: auxiliary, data: groupingOutline(5)), ZipEntry(name: "board.zip", data: nested)], name: "delivery")
        #expect(document.name == "board")
        #expect(document.bounds.width == 20)
        #expect(document.layers.count == 2)
    }
    let panelSource = Data(String(decoding: groupingOutline(20), as: UTF8.self).replacingOccurrences(of: "D10*", with: "%SRX2Y1I30J0*%D10*").replacingOccurrences(of: "M02*", with: "%SR*%M02*").utf8)
    let panel = try FabricationPackageLoader().load(files: [ZipEntry(name: "panel.gko", data: panelSource), ZipEntry(name: "panel.gtl", data: panelSource)], name: "panel")
    #expect(panel.bounds.width == 50)
    #expect(panel.layers[0].primitives.count == 8)
    #expect(panel.layers.count == 2)
    #expect(Set(panel.layers.map(\.id)).count == 2)
}

@Test func productionLayersRetainOriginalSourcePaths() throws {
    let jlc = Data("G04 -- output software:jlccam pro v3.4.8 *".utf8) + groupingOutline(10)
    let document = try FabricationPackageLoader().load(files: ["ko", "tl", "bl", "to"].map { ZipEntry(name: "delivery/ok/" + $0, data: jlc) }, name: "production")
    #expect(document.layers.allSatisfy { $0.fileName.hasPrefix("delivery/ok/") })
    #expect(Set(document.layers.map(\.id)).count == 4)
}
