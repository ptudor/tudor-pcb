import CoreGraphics
import Foundation
import Testing
@testable import GerberKit

private func materialAlpha(_ image: CGImage, at point: Point2D) throws -> UInt8 {
    let x = min(image.width - 1, Int(point.x / 10 * Double(image.width)))
    let y = min(image.height - 1, Int((10 - point.y) / 10 * Double(image.height)))
    return try rgba(image, x: x, y: y)[3]
}

@Test func nestedMaterialParityAndStrokeWidthAreResolutionIndependent() throws {
    for count in [3, 4] {
        for dimension in [256, 2048, 4096] {
            var reference: CFData?
            for width in [0.0, 0.1, 2.0] {
                let edges = (0..<count).flatMap { outlineSegments(squarePoints(Double($0), 10 - Double($0)), width: width) }
                let document = topologyBoard(edges)
                let rendered = try BoardRasterizer().render(document, options: .init(maximumTextureDimension: dimension))
                #expect(rendered.warnings.isEmpty)
                for depth in 0..<count {
                    let point = Point2D(x: Double(depth) + 0.5, y: 5)
                    #expect(try materialAlpha(rendered.boardMask, at: point) == (depth.isMultiple(of: 2) ? 255 : 0))
                }
                #expect(try materialAlpha(rendered.boardMask, at: Point2D(x: 5, y: 5)) == (count.isMultiple(of: 2) ? 0 : 255))
                if let reference { #expect(rendered.boardMask.dataProvider?.data == reference) }
                else { reference = rendered.boardMask.dataProvider?.data }
            }
        }
    }
}

@Test func clearRegionsAndSubsequentIslandsProduceSharedMaterialBoundaries() throws {
    let document = topologyBoard([
        .region(contours: [squarePoints(0, 10)], polarity: .dark),
        .region(contours: [squarePoints(2, 8)], polarity: .clear),
        .region(contours: [squarePoints(4, 6)], polarity: .dark)
    ])
    let topology = try BoardOutlineExtractor.topology(in: document)
    #expect(topology.materialContours.count == 3)
    #expect(topology.materialContours.filter { BoardOutlineExtractor.area($0) < 0 }.count == 1)
    for dimension in [256, 2048, 4096] {
        let mask = try BoardRasterizer().render(document, options: .init(maximumTextureDimension: dimension)).boardMask
        #expect(try materialAlpha(mask, at: Point2D(x: 1, y: 5)) == 255)
        #expect(try materialAlpha(mask, at: Point2D(x: 3, y: 5)) == 0)
        #expect(try materialAlpha(mask, at: Point2D(x: 5, y: 5)) == 255)
    }
    let overlapping = topologyBoard([
        .region(contours: [squarePoints(0, 6)], polarity: .dark),
        .region(contours: [squarePoints(4, 10)], polarity: .dark)
    ])
    let boundary = try BoardOutlineExtractor.contours(in: overlapping)
    #expect(boundary.count == 1)
    let image = try BoardRasterizer().render(overlapping, options: .init(maximumTextureDimension: 256)).boardMask
    #expect(try materialAlpha(image, at: Point2D(x: 5, y: 5)) == 255)
}

@Test func narrowChannelsStayPhysicalAndUnresolvedOutlinesStayDiagnostic() throws {
    let channel = [Point2D(x: 4.9, y: 1), Point2D(x: 5.1, y: 1), Point2D(x: 5.1, y: 9), Point2D(x: 4.9, y: 9)]
    for dimension in [256, 2048, 4096] {
        let document = topologyBoard(outlineSegments(squarePoints(0, 10), width: 2) + outlineSegments(channel, width: 2))
        let rendered = try BoardRasterizer().render(document, options: .init(maximumTextureDimension: dimension))
        #expect(rendered.warnings.isEmpty)
        #expect(try materialAlpha(rendered.boardMask, at: Point2D(x: 5, y: 5)) == 0)
        #expect(try materialAlpha(rendered.boardMask, at: Point2D(x: 4.5, y: 5)) == 255)
        var gap = outlineSegments(squarePoints(0, 10))
        gap[3] = .line(start: Point2D(x: 0, y: 10), end: Point2D(x: 0, y: 0.2), width: 0.1, polarity: .dark)
        let unresolved = try BoardRasterizer().render(topologyBoard(gap), options: .init(maximumTextureDimension: dimension))
        #expect(unresolved.warnings.contains { $0.contains("open routed") })
    }
}
