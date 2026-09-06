import Foundation
import Testing
@testable import GerberKit

@Test func drillFallbackUnionsEveryHitAndSlotEndpoint() throws {
    let header = "M48\nMETRIC\nT01C1.0\n%\nT01\n"
    let hits = ZipEntry(name: "board.drl", data: Data((header + "X0.0Y0.0\nX100.0Y50.0\nM30\n").utf8))
    let document = try FabricationPackageLoader().load(files: [hits], name: "drills")
    #expect(document.bounds == Bounds2D(minimum: Point2D(x: -0.5, y: -0.5), maximum: Point2D(x: 100.5, y: 50.5)))
    let slots = ZipEntry(name: "board.drl", data: Data((header + "X0.0Y0.0\nX100.0Y50.0G85X120.0Y-20.0\nM30\n").utf8))
    let slotBoard = try FabricationPackageLoader().load(files: [slots], name: "slots")
    #expect(slotBoard.bounds == Bounds2D(minimum: Point2D(x: -0.5, y: -20.5), maximum: Point2D(x: 120.5, y: 50.5)))
    let outlined = try FabricationPackageLoader().load(files: [slots, ZipEntry(name: "board.gko", data: groupingOutline(10))], name: "outline")
    #expect(outlined.bounds == Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    #expect(throws: FabricationPackageError.self) { try FabricationPackageLoader().load(files: [], name: "empty") }
}
