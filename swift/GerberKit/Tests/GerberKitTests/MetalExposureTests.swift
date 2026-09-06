import CoreGraphics
import Testing
@testable import GerberKit

@Test func exposedMetalRequiresBothCopperAndMask() throws {
    func flash(_ x: Double, _ diameter: Double) -> GerberPrimitive {
        .flash(center: Point2D(x: x, y: 5), shape: .circle(diameter: diameter), polarity: .dark)
    }
    let copper = GerberLayer(fileName: "top.gtl", kind: .copper(side: .top, index: nil), primitives: [flash(2, 2), flash(6, 2)])
    let mask = GerberLayer(fileName: "top.gts", kind: .solderMask(side: .top), primitives: [flash(2, 2), flash(4, 2), flash(8, 2)])
    let board = BoardDocument(name: "exposure", layers: [copper, mask], drills: [
        DrillHit(center: Point2D(x: 6, y: 5), diameter: 1, plated: true),
        DrillHit(center: Point2D(x: 8, y: 5), diameter: 1, plated: false)
    ], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    func pixel(_ image: CGImage, _ x: Double) throws -> [UInt8] { try rgba(image, x: Int(x * 100), y: 500) }
    let rasterizer = BoardRasterizer()
    let textures = try rasterizer.render(board, options: .init(maximumTextureDimension: 1000))
    #expect(try pixel(textures.top, 2) == [212, 148, 46, 255])
    #expect(try pixel(textures.top, 4) == [92, 71, 38, 255]) // Deliberately absent pad.
    #expect(try pixel(textures.top, 8.65) == pixel(textures.top, 4)) // NPTH clearance is bare substrate.
    #expect(try pixel(textures.top, 6.65) != pixel(textures.top, 2)) // Tented via has no exposed metal.
    let hiddenCopper = try rasterizer.render(board, options: .init(visibleLayerIDs: [mask.id], maximumTextureDimension: 1000))
    #expect(try pixel(hiddenCopper.top, 2) == pixel(textures.top, 4))
    let hiddenMask = try rasterizer.render(board, options: .init(visibleLayerIDs: [copper.id], maximumTextureDimension: 1000))
    #expect(try pixel(hiddenMask.top, 2) == pixel(textures.top, 6.65))
    for plated in [false, true] {
        let missingRing = BoardDocument(name: "missing ring", layers: [], drills: [DrillHit(center: Point2D(x: 5, y: 5), diameter: 1, plated: plated)], bounds: board.bounds)
        let result = try rasterizer.render(missingRing, options: .init(maximumTextureDimension: 1000))
        #expect(try pixel(result.top, 5.65) == pixel(result.top, 3))
    }
}
