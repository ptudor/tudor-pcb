import Testing
@testable import GerberKit

@Test func everyLayerRoleCanBeInspectedWithoutChangingOtherLayersOrPhysicalHoles() throws {
    let kinds: [GerberLayerKind] = [.copper(side: .top, index: nil), .copper(side: .bottom, index: nil), .copper(side: .none, index: 2), .solderMask(side: .top), .silkscreen(side: .bottom), .paste(side: .top), .outline, .drill(plated: true), .colorfulSilkscreen(side: .top), .documentation, .other]
    let rasterizer = BoardRasterizer()
    for kind in kinds {
        let layer = GerberLayer(fileName: "selected", kind: kind, primitives: [.flash(center: Point2D(x: 3, y: 5), shape: .circle(diameter: 1), polarity: .dark)])
        let other = GerberLayer(fileName: "other", kind: .documentation, primitives: [.line(start: Point2D(x: 7, y: 1), end: Point2D(x: 7, y: 9), width: 0.2, polarity: .dark)])
        let board = BoardDocument(name: "inspection", layers: [layer, other], drills: [DrillHit(center: Point2D(x: 5, y: 5), diameter: 1, plated: nil)], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
        let selected = try rasterizer.renderInspection(board, layerIDs: [layer.id], showDrills: false, maximumTextureDimension: 1000)
        #expect(try rgba(selected.image, x: 300, y: 500)[3] == 255)
        #expect(try rgba(selected.image, x: 700, y: 500)[3] == 0)
        #expect(try rgba(selected.image, x: 500, y: 500)[3] == 0)
        let drills = try rasterizer.renderInspection(board, layerIDs: [layer.id], showDrills: true, maximumTextureDimension: 1000)
        #expect(try rgba(drills.image, x: 500, y: 500)[3] == 255)
        #expect(try rgba(drills.image, x: 300, y: 500) == rgba(selected.image, x: 300, y: 500))
        let vcut = try rasterizer.renderInspection(board, layerIDs: [other.id], showDrills: false, maximumTextureDimension: 1000)
        #expect(try rgba(vcut.image, x: 700, y: 500)[3] == 255)
        #expect(try rgba(vcut.image, x: 300, y: 500)[3] == 0)
        #expect(selected.millimetersPerPixel == 0.01)
        #expect(board.drills.count == 1)
    }
    #expect(!GerberLayerKind.outline.hasPhysicalAppearanceControl)
    #expect(!GerberLayerKind.copper(side: .none, index: 2).hasPhysicalAppearanceControl)
    let physical = BoardDocument(name: "physical", drills: [DrillHit(center: Point2D(x: 5, y: 5), diameter: 1, plated: nil)], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
    let textures = try rasterizer.render(physical, options: .init(maximumTextureDimension: 1000))
    #expect(try rgba(textures.boardMask, x: 500, y: 500)[3] == 0)
}


@Test func zoomedSourceInspectionResolvesKnownPadsAndGapsAtEveryBoardEdge() throws {
    let rasterizer = BoardRasterizer()
    for center in [Point2D(x: 0.03, y: 50), Point2D(x: 99.97, y: 50), Point2D(x: 50, y: 0.03), Point2D(x: 50, y: 99.97)] {
        let layer = GerberLayer(fileName: "edge pads", kind: .copper(side: .none, index: 2), primitives: [-0.0125, 0.0125].map {
            .flash(center: Point2D(x: center.x + $0, y: center.y), shape: .circle(diameter: 0.02), polarity: .dark)
        })
        let board = BoardDocument(name: "100 mm board", layers: [layer], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 100, y: 100)))
        let overview = try rasterizer.renderInspection(board, layerIDs: [layer.id], showDrills: false, maximumTextureDimension: 1000)
        let viewport = Bounds2D(minimum: Point2D(x: center.x - 0.05, y: center.y - 0.05), maximum: Point2D(x: center.x + 0.05, y: center.y + 0.05))
        let detail = try rasterizer.renderInspection(board, layerIDs: [layer.id], showDrills: false, viewport: viewport, maximumTextureDimension: 1000)
        #expect(overview.millimetersPerPixel == 0.1)
        #expect(abs(detail.millimetersPerPixel - 0.0001) < 1e-10)
        #expect(try rgba(detail.image, x: 375, y: 500)[3] == 255)
        #expect(try rgba(detail.image, x: 625, y: 500)[3] == 255)
        // The 0.005 mm gap is 50 freshly rasterized pixels, independent of the overview texture.
        for x in 480...520 { #expect(try rgba(detail.image, x: x, y: 500)[3] == 0) }
        #expect(board.layers[0].primitives == layer.primitives)
        #expect(detail.bounds == viewport)
    }
}
