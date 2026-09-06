import Foundation
import Testing
@testable import GerberKit

func drillFile(_ header: String, body: String, tool: String = "T01C1.0") throws -> [DrillHit] {
    try ExcellonParser().parse(data: Data(("M48\n" + header + "\n" + tool + "\n%\nT01\n" + body + "\nM30\n").utf8), fileName: "format.drl")
}

@Test func excellonAbsoluteIncrementalAndOmittedAxes() throws {
    for mode in ["G91", "ICI,ON"] {
        let hits = try drillFile("METRIC", body: "\(mode)\nX1.0Y1.0\nX1.0Y1.0\nY-0.5\nICI,OFF\nX+3.0\nG91X-1.0Y1.0\nG90\nX0.0")
        #expect(hits.map(\.center) == [Point2D(x: 1, y: 1), Point2D(x: 2, y: 2), Point2D(x: 2, y: 1.5), Point2D(x: 3, y: 1.5), Point2D(x: 2, y: 2.5), Point2D(x: 0, y: 2.5)])
    }
}

@Test func excellonRetainedZerosMatchExporterConventions() throws {
    // KiCad writeEXCELLONHeader maps SUPPRESS_LEADING to TZ and SUPPRESS_TRAILING to LZ.
    for (units, pattern, fraction, scale) in [("INCH", "00.0000", 4, 25.4), ("METRIC", "000.000", 3, 1.0), ("METRIC", "0000.00", 2, 1.0)] {
        let trailing = try drillFile("\(units),TZ,\(pattern)", body: "X1Y-1")
        #expect(abs(trailing[0].center.x - scale / pow(10, Double(fraction))) < 1e-10)
        #expect(trailing[0].center.y == -trailing[0].center.x)
        let leading = try drillFile("\(units),LZ,\(pattern)", body: "X01Y-01")
        let integerCount = pattern.split(separator: ".")[0].count
        #expect(abs(leading[0].center.x - scale * pow(10, Double(integerCount - 2))) < 1e-10)
        let decimals = try drillFile("\(units),LZ,\(pattern)", body: "X1.25Y-2.5")
        #expect(decimals[0].center == Point2D(x: 1.25 * scale, y: -2.5 * scale))
    }
    let altium = try drillFile(";FILE_FORMAT=2:4\nINCH,TZ", body: "X10000Y20000")
    #expect(altium[0].center == Point2D(x: 25.4, y: 50.8))
    let kicad = try drillFile("; FORMAT={3:3 / absolute / metric / suppress leading zeros}\nMETRIC,TZ", body: "X1000Y2000")
    #expect(kicad[0].center == Point2D(x: 1, y: 2))
    let fixed = try drillFile(";FILE_FORMAT=4:2\nMETRIC", body: "X000125Y000250")
    #expect(fixed[0].center == Point2D(x: 1.25, y: 2.5))
}

@Test func ambiguousOrInvalidDrillCoordinatesAndToolsAreDiagnosed() throws {
    for header in ["INCH,TZ", "METRIC", ";FILE_FORMAT=3:3\nMETRIC", ";FILE_FORMAT=99:99\nMETRIC"] {
        #expect(throws: ExcellonParseError.self) { try drillFile(header, body: "X1Y1") }
    }
    for body in ["XnanY1.0", "X1..0Y1.0", "X999999999999999999999999.0Y0.0"] {
        #expect(throws: ExcellonParseError.self) { try drillFile("METRIC", body: body) }
    }
    for tool in ["T01C0", "T01C-1", "T01Cnan", "T01Cinf", "T01C9999999999999999999999"] {
        #expect(throws: ExcellonParseError.self) { try drillFile("METRIC", body: "X1.0Y1.0", tool: tool) }
    }
}
