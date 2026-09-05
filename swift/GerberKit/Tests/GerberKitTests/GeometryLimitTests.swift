import Foundation
import Testing
@testable import GerberKit

@Test(arguments: [
    "%SRX1000000000Y1I1J0*%D10*X0Y0D03*%SR*%",
    "D10*X0Y0D02*G03X1Y0I999999999999999999999999999999999J0D01*",
    "D10*X0Y0D02*G03X1Y0I1000000000J0D01*"
])
func parserRejectsUnboundedGeometry(body: String) throws {
    let source = "%FSLAX24Y24*%%MOMM*%%ADD10C,1*%" + body + "M02*"
    #expect(throws: GeometryLimitError.self) {
        try GerberParser().parse(data: Data(source.utf8), fileName: "limits.gtl")
    }
}

@Test func legalLargePanelRetainsEveryObject() throws {
    let source = "%FSLAX24Y24*%%MOMM*%%ADD10C,1*%%SRX100Y100I2J3*%D10*X0Y0D03*%SR*%M02*"
    let layer = try GerberParser().parse(data: Data(source.utf8), fileName: "panel.gtl")
    #expect(layer.primitives.count == 10_000)
    #expect(layer.primitives.last == .flash(center: Point2D(x: 198, y: 297), shape: .circle(diameter: 1), polarity: .dark))
    #expect(Set(layer.primitives).count == 10_000)
}

@Test func publicRenderAndOutlineExtractionRejectUnboundedGeometry() throws {
    let hugeArc = GerberPrimitive.arc(start: .zero, end: Point2D(x: 1, y: 0), center: Point2D(x: 100_000, y: 0), clockwise: false, width: 0.1, polarity: .dark)
    let board = BoardDocument(name: "large", layers: [GerberLayer(fileName: "outline.gko", kind: .outline, primitives: [hugeArc])])
    #expect(throws: GeometryLimitError.self) { try BoardOutlineExtractor.edgePaths(in: board) }
    #expect(throws: GeometryLimitError.self) { try BoardRasterizer().render(board) }
    let polygon = BoardDocument(name: "polygon", layers: [GerberLayer(fileName: "board.gtl", kind: .copper(side: .top, index: nil), primitives: [.flash(center: .zero, shape: .polygon(diameter: 1, vertices: Int.max, rotationDegrees: 0), polarity: .dark)])])
    #expect(throws: GeometryLimitError.self) { try BoardRasterizer().render(polygon) }
}

@Test func geometryWorkCooperatesWithCancellation() async throws {
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return try GerberParser().parse(data: Data("%ADD10C,1*%D10*X0Y0D03*M02*".utf8), fileName: "cancel.gtl")
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Ignored cancellation") }
    catch is CancellationError { }
}
