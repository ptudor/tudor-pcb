import Foundation

public struct GeometryLimitError: Error, LocalizedError, Sendable, Equatable {
    public let resource: String
    public let context: String
    public var errorDescription: String? { "\(context): geometry limit exceeded (\(resource))." }
}

/// Supported geometry keeps the existing 0.1 mm outline / 0.15 mm region
/// tessellation. Limits reject entire operations rather than lowering accuracy.
public enum GeometryLimits {
    public static let repeats = 100_000
    public static let primitives = 1_000_000
    public static let points = 4_000_000
    public static let meshVertices = 2_000_000
    public static let polygonVertices = 5_000
    public static let segmentsPerArc = 250_000
    public static let coordinateMagnitude = 1_000_000.0

    static func require(_ condition: Bool, _ resource: String, _ context: String) throws {
        try Task.checkCancellation()
        guard condition else { throw GeometryLimitError(resource: resource, context: context) }
    }

    static func point(_ point: Point2D, context: String) throws {
        try require(point.x.isFinite && point.y.isFinite && abs(point.x) <= coordinateMagnitude && abs(point.y) <= coordinateMagnitude,
                    "finite supported coordinates", context)
    }

    static func length(_ value: Double, context: String) throws {
        try require(value.isFinite && value >= 0 && value <= coordinateMagnitude, "finite supported dimension", context)
    }

    static func arcParameters(start: Point2D, end: Point2D, center: Point2D, clockwise: Bool,
                              spacing: Double, minimum: Int, context: String) throws -> (Double, Double, Double, Int) {
        for p in [start, end, center] { try point(p, context: context) }
        let radius = hypot(start.x - center.x, start.y - center.y)
        let angle = atan2(start.y - center.y, start.x - center.x)
        var sweep = atan2(end.y - center.y, end.x - center.x) - angle
        if clockwise, sweep >= 0 { sweep -= 2 * .pi }
        if !clockwise, sweep <= 0 { sweep += 2 * .pi }
        if start == end { sweep = clockwise ? -2 * .pi : 2 * .pi }
        let count = ceil(abs(sweep) * radius / spacing)
        try require(count.isFinite && count <= Double(segmentsPerArc), "tessellated segments per arc", context)
        return (radius, angle, sweep, max(minimum, Int(count)))
    }

    static func flattenArc(start: Point2D, end: Point2D, center: Point2D, clockwise: Bool,
                           spacing: Double, minimum: Int, context: String) throws -> [Point2D] {
        let (radius, angle, sweep, count) = try arcParameters(start: start, end: end, center: center,
            clockwise: clockwise, spacing: spacing, minimum: minimum, context: context)
        if radius <= 0.000_001 { return [end] }
        var result: [Point2D] = []
        result.reserveCapacity(count)
        for i in 1...count {
            if i % 256 == 0 { try Task.checkCancellation() }
            let a = angle + sweep * Double(i) / Double(count)
            let p = Point2D(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            try point(p, context: context)
            result.append(p)
        }
        return result
    }

    static func shape(_ shape: ApertureShape, context: String) throws -> Int {
        let size = shape.dimensions
        try length(size.width, context: context)
        try length(size.height, context: context)
        switch shape {
        case let .polygon(_, vertices, rotation):
            try require((3...polygonVertices).contains(vertices) && rotation.isFinite, "polygon vertices/angle", context)
            return vertices
        case let .custom(vertices):
            try require(vertices.count <= polygonVertices, "custom aperture vertices", context)
            for p in vertices { try point(p, context: context) }
            return vertices.count
        default: return 1
        }
    }

    static func cost(_ primitive: GerberPrimitive, context: String) throws -> Int {
        switch primitive {
        case let .line(start, end, width, _):
            try point(start, context: context); try point(end, context: context); try length(width, context: context)
            return 2
        case let .arc(start, end, center, clockwise, width, _):
            try length(width, context: context)
            return try arcParameters(start: start, end: end, center: center, clockwise: clockwise,
                                     spacing: 0.1, minimum: 8, context: context).3 + 1
        case let .flash(center, shape, _):
            try point(center, context: context)
            return try self.shape(shape, context: context)
        case let .region(contours, _):
            var count = 0
            for contour in contours {
                try require(contour.count <= points - count, "contour points", context)
                count += contour.count
                for p in contour { try point(p, context: context) }
            }
            return count
        }
    }

    public static func validate(_ document: BoardDocument) throws {
        var objects = 0
        var pointCount = 0
        for layer in document.layers {
            try require(layer.primitives.count <= primitives - objects, "document primitives", layer.fileName)
            objects += layer.primitives.count
            for primitive in layer.primitives {
                let added = try cost(primitive, context: layer.fileName)
                try require(added <= points - pointCount, "document points/segments", layer.fileName)
                pointCount += added
            }
        }
        try require(document.drills.count <= primitives - objects, "document drills", document.name)
        for drill in document.drills {
            try point(drill.center, context: document.name)
            if let end = drill.end { try point(end, context: document.name) }
            try length(drill.diameter, context: document.name)
        }
    }
}
