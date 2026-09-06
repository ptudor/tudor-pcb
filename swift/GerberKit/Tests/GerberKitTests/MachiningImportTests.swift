import Foundation
import Testing
@testable import GerberKit

private func machiningGerber(_ attribute: String = "", aperture: String = "C,1", body: String = "X10000Y20000D03*") -> Data {
    Data(("%FSLAX24Y24*%%MOMM*%" + attribute + "%ADD10\(aperture)*%D10*" + body + "M02*").utf8)
}

@Test func importsEquivalentDrillSyntaxesExtensionsAndMetadata() throws {
    let source = Data("M48\nMETRIC\nT01C1.0\n%\nT01\nX1.0Y2.0\nM30\n".utf8)
    let expected = [DrillHit(center: Point2D(x: 1, y: 2), diameter: 1, plated: nil)]
    for ext in ["drl", "txt", "nc", "tap"] {
        let document = try FabricationPackageLoader().load(files: [ZipEntry(name: "neutral." + ext, data: source)], name: "drills")
        #expect(document.drills == expected)
        #expect(document.warnings.isEmpty)
    }
    for (attribute, plated) in [("Plated,1,4,PTH,Drill", true), ("NonPlated,1,4,NPTH,Rout", false)] {
        let doc = try FabricationPackageLoader().load(files: [ZipEntry(name: "neutral.gbr", data: machiningGerber("%TF.FileFunction,\(attribute)*%"))], name: "X2")
        #expect(doc.drills == [DrillHit(center: Point2D(x: 1, y: 2), diameter: 1, plated: plated, layerSpan: DrillLayerSpan(start: 1, end: 4))])
        let commented = source.replacingText("M48", with: "M48\n; #@! TF.FileFunction,\(attribute)")
        let nc = try FabricationPackageLoader().load(files: [ZipEntry(name: "neutral.txt", data: commented)], name: "NC")
        #expect(nc.drills == doc.drills)
    }
    var production = Data("G04 -- output software:jlccam pro v3.4.8 *".utf8)
    production.append(machiningGerber())
    let jlc = try FabricationPackageLoader().load(files: [ZipEntry(name: "ok/drl", data: production)], name: "production")
    #expect(jlc.drills == expected)
    let ordinary = try FabricationPackageLoader().load(files: [ZipEntry(name: "Drill.gbr", data: machiningGerber())], name: "ordinary")
    #expect(ordinary.drills == expected)
}

@Test func machiningConversionPreservesSlotsAndRejectsWholeUnsupportedLayers() throws {
    let slot = try FabricationPackageLoader().load(files: [ZipEntry(name: "Drill.gbr", data: machiningGerber(aperture: "O,5X1", body: "X30000Y20000D03*"))], name: "slot")
    #expect(slot.drills == [DrillHit(center: Point2D(x: 1, y: 2), end: Point2D(x: 5, y: 2), diameter: 1, plated: nil)])
    let unsupported = [
        machiningGerber(body: "X10000Y20000D03*%LPC*%X10000Y20000D03*"),
        machiningGerber(aperture: "R,1X2"),
        machiningGerber(body: "X10000Y0D02*G75*G03X0Y10000I-10000J0D01*"),
        machiningGerber("%TF.FileFunction,Plated,1,2,Blind*%")
    ]
    for bad in unsupported {
        let doc = try FabricationPackageLoader().load(files: [ZipEntry(name: "board.gtl", data: machiningGerber()), ZipEntry(name: "Drill.gbr", data: bad)], name: "unsupported")
        #expect(doc.drills.isEmpty)
        #expect(doc.layers.count == 1)
        #expect(doc.warnings.count == 1)
    }
    for text in ["These are arbitrary coordinates X1 Y2", "G90\nG00X1.0Y2.0\nM30", "M48\nMETRIC\nG93X0.0Y0.0\nM30"] {
        #expect(throws: (any Error).self) { try FabricationPackageLoader().load(files: [ZipEntry(name: "program.nc", data: Data(text.utf8))], name: "not-drills") }
    }
    let legacy = Data(#"{"center":{"x":1,"y":2},"diameter":1,"plated":true}"#.utf8)
    #expect(try JSONDecoder().decode(DrillHit.self, from: legacy).layerSpan == nil)
    let roundTrip = try JSONDecoder().decode([DrillHit].self, from: JSONEncoder().encode(slot.drills))
    #expect(roundTrip == slot.drills)
}

private extension Data {
    func replacingText(_ text: String, with replacement: String) -> Data {
        Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: text, with: replacement).utf8)
    }
}
