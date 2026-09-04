import CoreGraphics
import Testing
@testable import GerberKit

@Test func rasterizesBothBoardFacesWithAnOutlineMask() throws {
    let bounds = Bounds2D(minimum: .zero, maximum: Point2D(x: 20, y: 10))
    let outline = GerberLayer(
        fileName: "outline.gko",
        kind: .outline,
        primitives: [
            .line(start: .zero, end: Point2D(x: 20, y: 0), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 20, y: 0), end: Point2D(x: 20, y: 10), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 20, y: 10), end: Point2D(x: 0, y: 10), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 0, y: 10), end: .zero, width: 0.1, polarity: .dark)
        ]
    )
    let topCopper = GerberLayer(
        fileName: "top.gtl",
        kind: .copper(side: .top, index: nil),
        primitives: [
            .flash(center: Point2D(x: 10, y: 5), shape: .circle(diameter: 3), polarity: .dark)
        ]
    )
    let board = BoardDocument(name: "fixture", layers: [outline, topCopper], bounds: bounds)
    let textures = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 512))

    #expect(textures.pixelWidth == 512)
    #expect(textures.pixelHeight == 256)
    #expect(textures.top.width == 512)
    #expect(textures.bottom.height == 256)
    #expect(textures.boardMask.bitsPerPixel == 32)
}

