import Foundation
import Testing
@testable import GerberKit

func squarePoints(_ low: Double, _ high: Double, offset: Point2D = .zero) -> [Point2D] {
    [Point2D(x: low, y: low), Point2D(x: high, y: low), Point2D(x: high, y: high), Point2D(x: low, y: high)].map { $0 + offset }
}
func outlineSegments(_ points: [Point2D], width: Double = 0.1) -> [GerberPrimitive] {
    points.indices.map { .line(start: points[$0], end: points[($0 + 1) % points.count], width: width, polarity: .dark) }
}
func topologyBoard(_ primitives: [GerberPrimitive]) -> BoardDocument {
    BoardDocument(name: "topology", layers: [GerberLayer(fileName: "board.gko", kind: .outline, primitives: primitives)], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
}

@Test func outlinePermutationAndReversalPreserveMasksAndSidewallEdges() throws {
    let segments = outlineSegments(squarePoints(0, 10)) + outlineSegments(squarePoints(3, 7))
    let original = topologyBoard(segments)
    let reference = try BoardRasterizer().render(original, options: .init(maximumTextureDimension: 256)).boardMask
    let edges = try BoardOutlineExtractor.edgePaths(in: original)
    for order in [[7,2,5,0,6,1,4,3], Array((0..<8).reversed())] {
        let changed = topologyBoard(order.enumerated().map { index, id in
            guard case let .line(start, end, width, polarity) = segments[id] else { return segments[id] }
            return index.isMultiple(of: 2) ? .line(start: end, end: start, width: width, polarity: polarity) : segments[id]
        })
        #expect(try BoardOutlineExtractor.edgePaths(in: changed) == edges)
        let mask = try BoardRasterizer().render(changed, options: .init(maximumTextureDimension: 256)).boardMask
        #expect(mask.dataProvider?.data == reference.dataProvider?.data)
        #expect(try rgba(mask, x: 128, y: 128)[3] == 0)
    }
}

@Test func everyRegionContourIncludesItsImplicitClosingEdge() throws {
    let document = topologyBoard([.region(contours: [squarePoints(0, 10), squarePoints(3, 7)], polarity: .dark)])
    let topology = try BoardOutlineExtractor.topology(in: document)
    #expect(topology.closedContours.count == 2)
    #expect(topology.closedContours.allSatisfy { $0.count == 5 && $0.first == $0.last })
    #expect(try BoardOutlineExtractor.edgePaths(in: document).count == 8)
    let mask = try BoardRasterizer().render(document, options: .init(maximumTextureDimension: 256)).boardMask
    #expect(try rgba(mask, x: 128, y: 128)[3] == 0)
    let disconnected = topologyBoard(outlineSegments(squarePoints(0, 2)) + outlineSegments(squarePoints(0, 2, offset: Point2D(x: 7, y: 7))))
    #expect(try BoardOutlineExtractor.contours(in: disconnected).count == 2)
    let sector = topologyBoard([
        .arc(start: Point2D(x: 10, y: 0), end: Point2D(x: 0, y: 10), center: .zero, clockwise: false, width: 0.1, polarity: .dark),
        .line(start: .zero, end: Point2D(x: 0, y: 10), width: 0.1, polarity: .dark),
        .line(start: Point2D(x: 10, y: 0), end: .zero, width: 0.1, polarity: .dark)])
    #expect(try BoardOutlineExtractor.contours(in: sector).count == 1)
}

@Test func outlineDiagnosticsDistinguishOpenInferredAndNonmanifoldPaths() throws {
    let open = topologyBoard([.line(start: .zero, end: Point2D(x: 10, y: 0), width: 0.1, polarity: .dark)])
    #expect(try BoardOutlineExtractor.topology(in: open).openPaths.count == 1)
    let branch = topologyBoard([Point2D(x: 10, y: 0), Point2D(x: 0, y: 10), Point2D(x: 10, y: 10)].map { .line(start: .zero, end: $0, width: 0.1, polarity: .dark) })
    let topology = try BoardOutlineExtractor.topology(in: branch)
    #expect(topology.closedContours.isEmpty && topology.ambiguousPaths.count == 3)
    #expect(topology.warnings.contains { $0.contains("nonmanifold") })
    let degenerate = topologyBoard([.region(contours: [[.zero, Point2D(x: 1, y: 0), Point2D(x: 2, y: 0)]], polarity: .dark)])
    #expect(try BoardOutlineExtractor.topology(in: degenerate).warnings.contains { $0.contains("degenerate region") })
    var gap = outlineSegments(squarePoints(0, 10))
    gap[3] = .line(start: Point2D(x: 0, y: 10), end: Point2D(x: 0, y: 0.01), width: 0.1, polarity: .dark)
    #expect(try BoardOutlineExtractor.topology(in: topologyBoard(gap)).warnings.contains { $0.contains("inferred") })
    let data = Data("%FSLAX24Y24*%%MOMM*%%ADD10C,0.1*%D10*X0Y0D02*X100000Y0D01*M02*".utf8)
    let loaded = try FabricationPackageLoader().load(files: [ZipEntry(name: "board.gko", data: data)], name: "open")
    #expect(loaded.warnings.contains { $0.contains("open routed") })
}
