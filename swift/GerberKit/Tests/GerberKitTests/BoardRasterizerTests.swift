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


@Test func renderingSessionReusesMasksAndUnchangedFaces() async throws {
    let session = FabricationWorkSession()
    let top = GerberLayer(fileName: "top.gtl", kind: .copper(side: .top, index: nil), primitives: [.flash(center: Point2D(x: 5, y: 5), shape: .circle(diameter: 2), polarity: .dark)])
    let bottom = GerberLayer(fileName: "bottom.gbl", kind: .copper(side: .bottom, index: nil), primitives: [.flash(center: Point2D(x: 8, y: 5), shape: .circle(diameter: 1), polarity: .dark)])
    let board = BoardDocument(name: "cache", layers: [top, bottom], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    let a = try await session.render(board, options: .init(maximumTextureDimension: 256))
    let b = try await session.render(board, options: .init(visibleLayerIDs: [bottom.id], maximumTextureDimension: 256))
    #expect(a.boardMask === b.boardMask)
    #expect(a.bottom === b.bottom)
    #expect(a.top !== b.top)
    let c = try await session.render(board, options: .init(visibleLayerIDs: [bottom.id], maximumTextureDimension: 256, solderMaskColor: .redMask))
    #expect(c.boardMask === b.boardMask)
    #expect(c.top !== b.top && c.bottom !== b.bottom)
}
