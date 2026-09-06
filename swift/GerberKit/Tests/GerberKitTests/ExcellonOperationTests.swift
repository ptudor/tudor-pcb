import Foundation
import Testing
@testable import GerberKit

@Test func excellonSlotsRoutesAndRepeatsRetainMachiningState() throws {
    let slot = try drillFile("METRIC", body: "X1.0Y2.0G85X5.0Y2.0")
    #expect(slot == [DrillHit(center: Point2D(x: 1, y: 2), end: Point2D(x: 5, y: 2), diameter: 1, plated: nil)])
    let route = try drillFile("METRIC", body: "G00X1.0Y2.0\nM15\nG01X5.0Y2.0\nY3.0\nM16\nG00X9.0Y9.0\nG01X8.0Y8.0\nG05\nX0.0Y0.0\nR3X1.0Y2.0")
    #expect(route.count == 6)
    #expect(route[0] == slot[0])
    #expect(route[1].center == Point2D(x: 5, y: 2) && route[1].end == Point2D(x: 5, y: 3))
    #expect(route.suffix(4).map(\.center) == [Point2D.zero, Point2D(x: 1, y: 2), Point2D(x: 2, y: 4), Point2D(x: 3, y: 6)])
    let incremental = try drillFile("METRIC", body: "G00X1.0Y2.0\nG91\nG85X4.0Y0.0")
    #expect(incremental == slot)
    let bounds = Bounds2D(minimum: .zero, maximum: Point2D(x: 8, y: 4))
    let textures = try BoardRasterizer().render(BoardDocument(name: "slot", drills: slot, bounds: bounds), options: .init(maximumTextureDimension: 256))
    let slotAlpha = try rgba(textures.boardMask, x: 96, y: 64)[3]
    withKnownIssue("RA6X-026: drilling is still painted on faces instead of removed from the substrate mask") {
        #expect(slotAlpha == 0)
    }
    #expect(try rgba(textures.top, x: 96, y: 64)[0] < 10)
    #expect(try rgba(textures.boardMask, x: 96, y: 32)[3] == 255)
}

@Test func invalidExcellonOperationsCannotFabricateHoles() throws {
    for body in ["T99\nX1.0Y1.0", "T00\nX1.0Y1.0", "G00X1.0Y1.0\nM15\nG02X2.0Y2.0I1.0J0.0\nM16", "M30\nX1.0Y1.0", "X1.0Y1.0\nR1000000000X1.0", "G00X1.0Y1.0\nM15\nG01X2.0Y2.0", "G93X0.0Y0.0", "X1.0Y1.0G85", "R2X1.0Y1.0"] {
        #expect(throws: ExcellonParseError.self) { try drillFile("METRIC", body: body) }
    }
    let source = Data("M48\nMETRIC\nT01C1.0\n%\nT01\nX0.0Y0.0\nR3X1.0Y0.0\nM30\n".utf8)
    var limits = ImportLimits(); limits.geometryObjects = 3
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(files: [ZipEntry(name: "board.drl", data: source)], name: "repeat-budget") }
    let plated = try drillFile(";TYPE=PLATED\nMETRIC", body: "X1.0Y2.0G85X5.0Y2.0")
    #expect(plated[0].plated == true)
}
