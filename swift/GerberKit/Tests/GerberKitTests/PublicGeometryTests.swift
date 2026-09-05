import CoreGraphics
import Foundation
import Testing
@testable import GerberKit

func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data) as Data
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<(offset + 4)])
}

@Test func publicRenderingRejectsInvalidBoundsAndThickness() throws {
    for bounds in [
        Bounds2D(minimum: .zero, maximum: Point2D(x: .nan, y: 1)),
        Bounds2D(minimum: .zero, maximum: Point2D(x: .infinity, y: 1)),
        Bounds2D(minimum: Point2D(x: 2, y: 2), maximum: Point2D(x: 1, y: 1)),
        Bounds2D(minimum: .zero, maximum: .zero)
    ] {
        #expect(throws: BoardGeometryError.self) { try BoardRasterizer().render(BoardDocument(name: "invalid", bounds: bounds)) }
    }
    for thickness in [Double.nan, .infinity, 0, -1] {
        #expect(throws: BoardGeometryError.self) { try BoardRasterizer().render(BoardDocument(name: "invalid", thicknessMillimeters: thickness)) }
    }
}

@Test func offCenterCustomFlashBoundsAndPixelsUseLocalCoordinates() throws {
    let primitive = GerberPrimitive.flash(center: Point2D(x: 2, y: 3), shape: .custom(points: [
        Point2D(x: 5, y: 7), Point2D(x: 7, y: 7), Point2D(x: 7, y: 8), Point2D(x: 5, y: 8)
    ]), polarity: .dark)
    let bounds = try #require(primitive.bounds)
    #expect(bounds == Bounds2D(minimum: Point2D(x: 7, y: 10), maximum: Point2D(x: 9, y: 11)))
    let layer = GerberLayer(fileName: "custom.gtl", kind: .copper(side: .top, index: nil), primitives: [primitive])
    let board = BoardDocument(name: "custom", layers: [layer], bounds: bounds)
    let texture = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 256))
    let empty = try BoardRasterizer().render(BoardDocument(name: "empty", bounds: bounds), options: .init(maximumTextureDimension: 256))
    #expect(try rgba(texture.top, x: 128, y: 64) != rgba(empty.top, x: 128, y: 64))
    #expect(texture.pixelWidth == 256 && texture.pixelHeight == 128)
}

@Test func zeroSizeCopperDoesNotAcquirePresentationWidth() throws {
    let bounds = Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10))
    let layer = GerberLayer(fileName: "zero.gtl", kind: .copper(side: .top, index: nil), primitives: [
        .line(start: Point2D(x: 1, y: 5), end: Point2D(x: 9, y: 5), width: 0, polarity: .dark),
        .flash(center: Point2D(x: 5, y: 5), shape: .circle(diameter: 0), polarity: .dark)
    ])
    let texture = try BoardRasterizer().render(BoardDocument(name: "zero", layers: [layer], bounds: bounds), options: .init(maximumTextureDimension: 256))
    let empty = try BoardRasterizer().render(BoardDocument(name: "empty", bounds: bounds), options: .init(maximumTextureDimension: 256))
    #expect(texture.top.dataProvider?.data == empty.top.dataProvider?.data)
}
