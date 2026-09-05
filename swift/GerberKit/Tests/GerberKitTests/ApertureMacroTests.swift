import CoreGraphics
import Foundation
import Testing
@testable import GerberKit

private func macroLayer(_ definition: String, add: String, body: String = "D10*X50000Y50000D03*") throws -> GerberLayer {
    try GerberParser().parse(data: Data(("%FSLAX24Y24*%%MOMM*%" + definition + add + body + "M02*").utf8), fileName: "macro.gtl")
}
private func macroImage(_ layer: GerberLayer) throws -> CGImage {
    try BoardRasterizer().render(BoardDocument(name: "macro", layers: [layer], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10))), options: .init(maximumTextureDimension: 256)).top
}

@Test func macroParametersExpressionsOffsetsAndRotationsMatchReferenceSemantics() throws {
    let layer = try macroLayer("%AMpad*$4=($1+2)x3/2*1,1,$4,$2,$3*%", add: "%ADD10pad,2X3X5*%", body: "D10*X0Y0D03*")
    guard case let .flash(_, .compound(primitives), _) = try #require(layer.primitives.first),
          case let .flash(center, .circle(diameter), _) = try #require(primitives.first) else { Issue.record("Missing composed macro"); return }
    #expect(center == Point2D(x: 3, y: 5))
    #expect(diameter == 6)
    let rotated = try macroLayer("%AMrot*4,1,4,1,0,3,0,3,1,1,1,1,0,90*%", add: "%ADD10rot*%", body: "D10*X0Y0D03*")
    let bounds = try #require(rotated.bounds)
    #expect(abs(bounds.minimum.x + 1) < 0.000001)
    #expect(abs(bounds.maximum.x) < 0.000001)
    #expect(abs(bounds.minimum.y - 1) < 0.000001)
    #expect(abs(bounds.maximum.y - 3) < 0.000001)
    let circle = try macroLayer("%AMcircle*1,1,2,2,0,90*%", add: "%ADD10circle*%", body: "D10*X0Y0D03*")
    #expect(abs(try #require(circle.bounds).center.x) < 0.000001)
    #expect(abs(try #require(circle.bounds).center.y - 2) < 0.000001)
}

@Test func macroHolesPreserveUnderlyingTracesForBothLayerPolarities() throws {
    let trace = "%ADD11C,0.4*%D11*X0Y50000D02*X100000Y50000D01*"
    let definition = "%AMdonut*1,1,4,0,0*1,0,2,0,0*%"
    let traceOnly = try macroLayer("", add: "", body: trace)
    let reference = try macroImage(traceOnly)
    for polarity in ["LPD", "LPC"] {
        let layer = try macroLayer(definition, add: "%ADD10donut*%", body: trace + "%\(polarity)*%D10*X50000Y50000D03*")
        let image = try macroImage(layer)
        #expect(try rgba(image, x: 128, y: 128) == rgba(reference, x: 128, y: 128))
        #expect(try rgba(image, x: 128, y: 145) == rgba(reference, x: 128, y: 145))
        if polarity == "LPC" { #expect(try rgba(image, x: 166, y: 128) != rgba(reference, x: 166, y: 128)) }
    }
}

@Test func thermalAndOrderedMacroSubprimitivesKeepTheirLocalTransparency() throws {
    let empty = try macroImage(GerberLayer(fileName: "empty.gtl", kind: .copper(side: .top, index: nil), primitives: []))
    let thermal = try macroImage(macroLayer("%AMthermal*7,0,0,4,2,0.4,0*%", add: "%ADD10thermal*%"))
    #expect(try rgba(thermal, x: 128, y: 128) == rgba(empty, x: 128, y: 128))
    #expect(try rgba(thermal, x: 166, y: 128) == rgba(empty, x: 166, y: 128))
    #expect(try rgba(thermal, x: 159, y: 159) != rgba(empty, x: 159, y: 159))
    let underThermal = try macroImage(macroLayer("%AMthermal*1,1,0.6,0,0*7,0,0,4,2,0.4,0*%", add: "%ADD10thermal*%"))
    #expect(try rgba(underThermal, x: 128, y: 128) != rgba(empty, x: 128, y: 128))
    let ordered = try macroImage(macroLayer("%AMordered*1,1,2,-1,0*1,0,1,-1,0*1,1,1,1,0*%", add: "%ADD10ordered*%"))
    #expect(try rgba(ordered, x: 102, y: 128) == rgba(empty, x: 102, y: 128))
    #expect(try rgba(ordered, x: 154, y: 128) != rgba(empty, x: 154, y: 128))
}

@Test func literalMultilineMacrosAndCodableRemainCompatible() throws {
    let layer = try macroLayer("%AMoutline*\n4,1,4,\n0,0,1.82,0,1.82,1.25,0,1.25,0,0,0*%", add: "%ADD10outline*%", body: "D10*X0Y0D03*")
    #expect(abs(try #require(layer.bounds).width - 1.82) < 0.000001)
    #expect(abs(try #require(layer.bounds).height - 1.25) < 0.000001)
    let old = try JSONDecoder().decode(ApertureShape.self, from: Data(#"{"circle":{"diameter":2}}"#.utf8))
    #expect(old == .circle(diameter: 2))
    #expect(try JSONDecoder().decode(GerberLayer.self, from: JSONEncoder().encode(layer)) == layer)
}

@Test func malformedMacroArithmeticAndUnsupportedInstantiationsThrow() throws {
    for definition in ["%AMbad*1,1,1/0,0,0*%", "%AMbad*$1=2*1,1,$1,0,0*%", "%AMbad*6,0,0,1,1,1,1,1,1,0*%"] {
        #expect(throws: GerberParseError.self) { try macroLayer(definition, add: "%ADD10bad,1*%") }
    }
    let huge = String(repeating: "9", count: 200)
    #expect(throws: GerberParseError.self) { try macroLayer("%AMbad*1,1,$1x$1,0,0*%", add: "%ADD10bad,\(huge)*%") }
    // An unused exporter macro must not change the geometry or reject the layer.
    let unused = try macroLayer("%AMOC8*5,1,8,0,0,1.08239X$1,22.5*%", add: "%ADD10C,1*%")
    #expect(unused.primitives.count == 1)
}


@Test func zeroWidthMacroPrimitivesRemainEmpty() throws {
    let layer = try macroLayer("%AMzero*21,1,0,2,0,0,0*20,1,0,0,0,2,0,0*%", add: "%ADD10zero*%")
    let image = try macroImage(layer)
    let empty = try macroImage(GerberLayer(fileName: "empty.gtl", kind: .copper(side: .top, index: nil), primitives: []))
    #expect(image.dataProvider?.data == empty.dataProvider?.data)
}
