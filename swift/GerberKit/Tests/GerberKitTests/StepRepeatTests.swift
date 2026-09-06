import Foundation
import Testing
@testable import GerberKit

@Test func repeatsCompositeBlocksInYThenXOrder() throws {
    let header = "%FSLAX24Y24*%%MOMM*%%ADD10C,0.4*%D10*"
    for (repeatCommand, clearX, clearY) in [("SRX2Y1I1J0", 1, 0), ("SRX1Y2I0J1", 0, 1), ("SRX2Y2I1J1", 1, 0)] {
        let body = "%\(repeatCommand)*%X0Y0D03*%LPC*%X\(clearX * 10000)Y\(clearY * 10000)D03*%SR*%M02*"
        let layer = try GerberParser().parse(data: Data((header + body).utf8), fileName: "repeat.gtl")
        #expect(layer.primitives[0].polarity == .dark)
        #expect(layer.primitives[1].polarity == .clear)
        #expect(layer.primitives[2].polarity == .dark)
        let image = try BoardRasterizer().render(BoardDocument(name: "repeat", layers: [layer], bounds: Bounds2D(minimum: Point2D(x: -1, y: -1), maximum: Point2D(x: 3, y: 3))), options: .init(maximumTextureDimension: 256)).top
        let reference = try BoardRasterizer().render(BoardDocument(name: "empty", bounds: Bounds2D(minimum: Point2D(x: -1, y: -1), maximum: Point2D(x: 3, y: 3))), options: .init(maximumTextureDimension: 256)).top
        #expect(try rgba(image, x: 64 + clearX * 64, y: 191 - clearY * 64) != rgba(reference, x: 64 + clearX * 64, y: 191 - clearY * 64))
        if repeatCommand == "SRX2Y2I1J1" {
            guard case let .flash(center, _, _) = layer.primitives[2] else { Issue.record("Missing copy"); return }
            #expect(center == Point2D(x: 0, y: 1))
        }
    }
    #expect(throws: GerberParseError.self) {
        try GerberParser().parse(data: Data((header + "%SRX2Y2I1J1*%%SRX2Y2I1J1*%X0Y0D03*%SR*%%SR*%M02*").utf8), fileName: "nested.gtl")
    }
}
