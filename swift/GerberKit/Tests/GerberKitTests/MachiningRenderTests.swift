import CoreGraphics
import Testing
@testable import GerberKit

@Test func throughBoresAndSlotsExposeBackgroundOnBothFaces() throws {
    let board = BoardDocument(name: "machining", drills: [
        DrillHit(center: Point2D(x: 2, y: 5), diameter: 2, plated: true),
        DrillHit(center: Point2D(x: 5, y: 5), end: Point2D(x: 8, y: 5), diameter: 1, plated: false)
    ], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    let textures = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 1000))
    for source in [textures.top, textures.bottom, textures.boardMask] {
        #expect(try rgba(source, x: 200, y: 500)[3] == 0)
        #expect(try rgba(source, x: 480, y: 500)[3] == 0)
        #expect(try rgba(source, x: 820, y: 500)[3] == 0)
        #expect(try rgba(source, x: 650, y: 500)[3] == 0)
        #expect(try rgba(source, x: 650, y: 440)[3] == 255)
        let context = try #require(CGContext(data: nil, width: 1000, height: 1000, bitsPerComponent: 8, bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        context.draw(source, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let composed = try #require(context.makeImage())
        #expect(try rgba(composed, x: 200, y: 500) == [255, 0, 255, 255])
        #expect(try rgba(composed, x: 650, y: 500) == [255, 0, 255, 255])
    }
    let walls = try BoardMachiningExtractor.wallPaths(in: board)
    let metal = walls.filter(\.plated).flatMap(\.points)
    let metalBounds = try #require(Bounds2D.containing(metal))
    #expect(abs(metalBounds.width - 2) < 1e-8 && abs(metalBounds.height - 2) < 1e-8)
    let slotWalls = walls.filter { !$0.plated && $0.points.allSatisfy { $0.x > 4 && $0.x < 9 } }.flatMap(\.points)
    let slotBounds = try #require(Bounds2D.containing(slotWalls))
    #expect(abs(slotBounds.width - 4) < 1e-8 && abs(slotBounds.height - 1) < 1e-8)
}

@Test func overlappingAndOffBoardDrillsDoNotLeaveInternalWalls() throws {
    let board = BoardDocument(name: "overlap", drills: [
        DrillHit(center: Point2D(x: 5, y: 5), diameter: 2, plated: false),
        DrillHit(center: Point2D(x: 5.5, y: 5), diameter: 2, plated: true),
        DrillHit(center: Point2D(x: 20, y: 20), diameter: 2, plated: true)
    ], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    let walls = try BoardMachiningExtractor.wallPaths(in: board)
    for wall in walls {
        #expect(wall.points.allSatisfy { $0.x <= 10 && $0.y <= 10 })
        let midpoint = Point2D(x: (wall.points[0].x + wall.points[1].x) / 2, y: (wall.points[0].y + wall.points[1].y) / 2)
        #expect(hypot(midpoint.x - 5, midpoint.y - 5) > 0.99)
        #expect(hypot(midpoint.x - 5.5, midpoint.y - 5) > 0.99)
    }
}
