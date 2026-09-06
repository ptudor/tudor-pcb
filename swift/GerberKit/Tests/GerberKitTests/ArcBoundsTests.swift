import Foundation
import Testing
@testable import GerberKit

@Test func directedArcBoundsContainOnlySweptCardinalExtrema() throws {
    let points = [Point2D(x: 10, y: 0), Point2D(x: 0, y: 10), Point2D(x: -10, y: 0), Point2D(x: 0, y: -10)]
    for index in 0..<4 {
        let start = points[index], end = points[(index + 1) % 4]
        for clockwise in [false, true] {
            let a = clockwise ? end : start, b = clockwise ? start : end
            let arc = GerberPrimitive.arc(start: a, end: b, center: .zero, clockwise: clockwise, width: 0.2, polarity: .dark)
            let layer = GerberLayer(fileName: "board.gko", kind: .outline, primitives: [arc])
            #expect(layer.centerlineBounds == Bounds2D.containing([a, b]))
            #expect(layer.centerlineBounds?.width == 10 && layer.centerlineBounds?.height == 10)
            #expect(arc.bounds == layer.centerlineBounds?.expanded(by: 0.1))
        }
        let full = GerberPrimitive.arc(start: start, end: start, center: .zero, clockwise: index.isMultiple(of: 2), width: 0, polarity: .dark)
        #expect(full.bounds == Bounds2D(minimum: Point2D(x: -10, y: -10), maximum: Point2D(x: 10, y: 10)))
    }
    let a = Point2D(x: cos(-.pi / 4) * 10, y: sin(-.pi / 4) * 10)
    let b = Point2D(x: a.x, y: -a.y)
    let wrapping = GerberPrimitive.arc(start: a, end: b, center: .zero, clockwise: false, width: 0, polarity: .dark)
    #expect(wrapping.bounds?.maximum.x == 10)
    #expect(wrapping.bounds?.minimum.x == a.x)
    let major = GerberPrimitive.arc(start: a, end: b, center: .zero, clockwise: true, width: 0, polarity: .dark)
    #expect(major.bounds?.minimum.x == -10 && major.bounds?.height == 20)
}

@Test func invalidArcCentersAreRejectedAndSectorDimensionsRemainCenterlineBased() throws {
    for (start, end) in [(Point2D.zero, Point2D(x: 1, y: 0)), (Point2D(x: 1, y: 0), Point2D(x: 2, y: 0))] {
        let arc = GerberPrimitive.arc(start: start, end: end, center: .zero, clockwise: false, width: 0.1, polarity: .dark)
        #expect(arc.bounds == nil)
        #expect(throws: GeometryLimitError.self) { try BoardRasterizer().render(BoardDocument(name: "bad", layers: [GerberLayer(fileName: "bad.gtl", kind: .other, primitives: [arc])])) }
    }
    let source = Data("%FSLAX24Y24*%%MOMM*%%ADD10C,0.2*%D10*X100000Y0D02*G75*G03X0Y100000I-100000J0D01*G01X0Y0D01*X100000Y0D01*M02*".utf8)
    let board = try FabricationPackageLoader().load(files: [ZipEntry(name: "sector.gko", data: source)], name: "sector")
    #expect(board.bounds == Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
}
