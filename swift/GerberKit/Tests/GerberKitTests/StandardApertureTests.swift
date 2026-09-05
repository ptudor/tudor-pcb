import CoreGraphics
import Foundation
import Testing
@testable import GerberKit

private func standardLayer(_ add: String, units: String = "MM", body: String = "D10*X0Y0D03*") throws -> GerberLayer {
    try GerberParser().parse(data: Data(("%FSLAX24Y24*%%MO\(units)*%" + add + body + "M02*").utf8), fileName: "standard.gtl")
}
private func standardImage(_ layer: GerberLayer) throws -> CGImage {
    try BoardRasterizer().render(BoardDocument(name: "standard", layers: [layer], bounds: Bounds2D(minimum: Point2D(x: -5, y: -5), maximum: Point2D(x: 5, y: 5))), options: .init(maximumTextureDimension: 256)).top
}

@Test func inchPolygonRetainsDimensionlessModifiers() throws {
    let metric = try standardLayer("%ADD10P,2.54X6X30*%")
    let inch = try standardLayer("%ADD10P,0.1X6X30*%", units: "IN")
    #expect(metric.primitives == inch.primitives)
    #expect(metric.bounds == inch.bounds)
    guard case let .flash(_, shape, _) = try #require(inch.primitives.first) else { Issue.record("Missing flash"); return }
    #expect(shape == .polygon(diameter: 2.54, vertices: 6, rotationDegrees: 30))
    let a = try standardImage(metric), b = try standardImage(inch)
    #expect(a.dataProvider?.data == b.dataProvider?.data)
    // Radius 1.27 at 30 degrees: right corner is near (1.10, 0.635).
    let empty = try standardImage(GerberLayer(fileName: "empty.gtl", kind: metric.kind, primitives: []))
    #expect(try rgba(a, x: 154, y: 112) != rgba(empty, x: 154, y: 112))
    #expect(try rgba(a, x: 160, y: 128) == rgba(empty, x: 160, y: 128))
}
