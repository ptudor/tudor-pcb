import Foundation

public enum GerberSide: String, Sendable, Codable, CaseIterable {
    case top
    case bottom
    case none
}

public enum GerberLayerKind: Sendable, Hashable, Codable {
    case copper(side: GerberSide, index: Int?)
    case solderMask(side: GerberSide)
    case silkscreen(side: GerberSide)
    case paste(side: GerberSide)
    case outline
    case drill(plated: Bool?)
    case colorfulSilkscreen(side: GerberSide)
    case documentation
    case other

    public var side: GerberSide {
        switch self {
        case let .copper(side, _), let .solderMask(side), let .silkscreen(side),
             let .paste(side), let .colorfulSilkscreen(side):
            side
        default:
            .none
        }
    }

    public var displayName: String {
        switch self {
        case let .copper(side, index):
            if let index { return BoardStrings.innerCopper(index) }
            return side == .top ? BoardStrings.topCopper : BoardStrings.bottomCopper
        case let .solderMask(side): return side == .top ? BoardStrings.topSolderMask : BoardStrings.bottomSolderMask
        case let .silkscreen(side): return side == .top ? BoardStrings.topSilkscreen : BoardStrings.bottomSilkscreen
        case let .paste(side): return side == .top ? BoardStrings.topPaste : BoardStrings.bottomPaste
        case .outline: return BoardStrings.boardOutline
        case let .drill(plated):
            switch plated {
            case true: return BoardStrings.platedDrills
            case false: return BoardStrings.nonPlatedDrills
            case nil: return BoardStrings.drills
            }
        case let .colorfulSilkscreen(side):
            return side == .top ? BoardStrings.easyEDAColorTop : BoardStrings.easyEDAColorBottom
        case .documentation: return BoardStrings.documentation
        case .other: return BoardStrings.other
        }
    }
}

public enum GerberPolarity: String, Sendable, Hashable, Codable {
    case dark
    case clear
}

public indirect enum ApertureShape: Sendable, Hashable, Codable {
    case circle(diameter: Double)
    case rectangle(width: Double, height: Double)
    case obround(width: Double, height: Double)
    case polygon(diameter: Double, vertices: Int, rotationDegrees: Double)
    case custom(points: [Point2D])
    case compound(primitives: [GerberPrimitive])

    public var dimensions: (width: Double, height: Double) {
        switch self {
        case let .circle(diameter): return (diameter, diameter)
        case let .rectangle(width, height), let .obround(width, height): return (width, height)
        case let .polygon(diameter, _, _): return (diameter, diameter)
        case .compound:
            guard let bounds = localBounds else { return (0, 0) }
            return (bounds.width, bounds.height)
        case let .custom(points):
            guard let bounds = Bounds2D.containing(points) else { return (0, 0) }
            return (bounds.width, bounds.height)
        }
    }

    var localBounds: Bounds2D? {
        switch self {
        case let .custom(points): return Bounds2D.containing(points)
        case let .compound(primitives):
            return primitives.filter { $0.polarity == .dark }.compactMap(\.bounds).reduce(nil) { $0?.union($1) ?? $1 }
        default:
            let size = dimensions
            return Bounds2D(minimum: Point2D(x: -size.width / 2, y: -size.height / 2), maximum: Point2D(x: size.width / 2, y: size.height / 2))
        }
    }

}

public enum GerberPrimitive: Sendable, Hashable, Codable {
    case line(start: Point2D, end: Point2D, width: Double, polarity: GerberPolarity)
    case arc(start: Point2D, end: Point2D, center: Point2D, clockwise: Bool, width: Double, polarity: GerberPolarity)
    case flash(center: Point2D, shape: ApertureShape, polarity: GerberPolarity)
    case region(contours: [[Point2D]], polarity: GerberPolarity)

    public var polarity: GerberPolarity {
        switch self {
        case let .line(_, _, _, polarity), let .arc(_, _, _, _, _, polarity),
             let .flash(_, _, polarity), let .region(_, polarity):
            polarity
        }
    }

    public var bounds: Bounds2D? {
        switch self {
        case let .line(start, end, width, _):
            return Bounds2D.containing([start, end])?.expanded(by: width / 2)
        case let .arc(start, end, center, clockwise, width, _):
            return ArcSweep(start: start, end: end, center: center, clockwise: clockwise)?.bounds.expanded(by: width / 2)
        case let .flash(center, shape, _):
            guard let local = shape.localBounds else { return nil }
            return Bounds2D(minimum: local.minimum + center, maximum: local.maximum + center)
        case let .region(contours, _):
            return Bounds2D.containing(contours.flatMap { $0 })
        }
    }
}

public struct GerberLayer: Sendable, Hashable, Codable, Identifiable {
    public var id: String { fileName }
    public var fileName: String
    public var kind: GerberLayerKind
    public var primitives: [GerberPrimitive]
    public var sourceGenerator: String?

    public init(
        fileName: String,
        kind: GerberLayerKind,
        primitives: [GerberPrimitive],
        sourceGenerator: String? = nil
    ) {
        self.fileName = fileName
        self.kind = kind
        self.primitives = primitives
        self.sourceGenerator = sourceGenerator
    }

    public var bounds: Bounds2D? {
        primitives.compactMap(\.bounds).reduce(nil) { partial, next in
            partial?.union(next) ?? next
        }
    }

    /// Geometry bounds without aperture stroke expansion. Board houses route on
    /// an outline's centerline, so this is the dimension users expect to review.
    var centerlineBounds: Bounds2D? {
        primitives.compactMap { primitive -> Bounds2D? in
            switch primitive {
            case let .line(start, end, _, _):
                return Bounds2D.containing([start, end])
            case let .arc(start, end, center, clockwise, _, _):
                return ArcSweep(start: start, end: end, center: center, clockwise: clockwise)?.bounds
            case .flash, .region:
                return primitive.bounds
            }
        }.reduce(nil) { partial, next in partial?.union(next) ?? next }
    }
}

public struct DrillLayerSpan: Sendable, Hashable, Codable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
}

public struct DrillHit: Sendable, Hashable, Codable {
    public var center: Point2D
    public var end: Point2D?
    public var diameter: Double
    public var plated: Bool?
    public var layerSpan: DrillLayerSpan?

    public init(center: Point2D, end: Point2D? = nil, diameter: Double, plated: Bool?, layerSpan: DrillLayerSpan? = nil) {
        self.center = center
        self.end = end
        self.diameter = diameter
        self.plated = plated
        self.layerSpan = layerSpan
    }
}

extension GerberLayerKind {
    public var hasPhysicalAppearanceControl: Bool {
        switch self {
        case let .copper(side, index): index == nil && (side == .top || side == .bottom)
        case let .solderMask(side), let .silkscreen(side): side == .top || side == .bottom
        default: false
        }
    }
}
