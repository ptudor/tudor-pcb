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

@Test func standardHolesAreLocalAndPreserveExistingGeometry() throws {
    let trace = "%ADD11C,0.2*%D11*X-50000Y0D02*X50000Y0D01*"
    let reference = try standardImage(standardLayer("", body: trace))
    for add in ["C,2X1", "R,2X3X1", "O,2X3X1", "P,2X6X30X1"] {
        for polarity in ["LPD", "LPC"] {
            let layer = try standardLayer("%ADD10\(add)*%", body: trace + "%\(polarity)*%D10*X0Y0D03*")
            guard case let .flash(_, .compound(parts), _) = try #require(layer.primitives.last) else { Issue.record("Missing hole"); continue }
            #expect(parts.count == 2)
            #expect(parts[1] == .flash(center: .zero, shape: .circle(diameter: 1), polarity: .clear))
            if add.hasPrefix("C") { #expect(parts[0] == .flash(center: .zero, shape: .circle(diameter: 2), polarity: .dark)) }
            let image = try standardImage(layer)
            #expect(try rgba(image, x: 128, y: 128) == rgba(reference, x: 128, y: 128))
            #expect(try rgba(image, x: 128, y: 135) == rgba(reference, x: 128, y: 135))
            if polarity == "LPC" { #expect(try rgba(image, x: 146, y: 128) != rgba(reference, x: 146, y: 128)) }
            else { #expect(try rgba(image, x: 128, y: 146) != rgba(reference, x: 128, y: 146)) }
        }
    }
    let metric = try standardLayer("%ADD10P,2.54X6X30X1.27*%")
    let inch = try standardLayer("%ADD10P,0.1X6X30X0.05*%", units: "IN")
    #expect(metric.primitives == inch.primitives)
    #expect(try JSONDecoder().decode(GerberLayer.self, from: JSONEncoder().encode(inch)) == inch)
    for add in ["C,2X1X0.5", "R,2X3X1X0.5", "O,2X3X1X0.5", "P,2X6X30X1X0.5"] {
        #expect(throws: GerberParseError.self) { try standardLayer("%ADD10\(add)*%") }
    }
}
