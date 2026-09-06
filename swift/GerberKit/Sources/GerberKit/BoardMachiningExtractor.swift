import Foundation

public struct BoardWallPath: Sendable {
    public var points: [Point2D]
    public var plated: Bool
}

/// Through-machining boundaries at their actual diameter. Layer-span imports
/// reject blind/buried operations; retained spans describe through-stack layers.
public enum BoardMachiningExtractor {
    public static func wallPaths(in document: BoardDocument) throws -> [BoardWallPath] {
        let topology = try BoardOutlineExtractor.topology(in: document)
        guard !document.drills.isEmpty else {
            return topology.paths.map { BoardWallPath(points: $0, plated: false) }
        }
        struct Bore {
            let drill: DrillHit
            let bounds: Bounds2D
            let innerRadius: Double
        }
        var bores: [Bore] = [], holes: [[Point2D]] = []
        var pointCount = 0
        for drill in document.drills where drill.diameter > 0 {
            try Task.checkCancellation()
            let radius = drill.diameter / 2
            let stepsValue = ceil(.pi * radius / 0.05)
            try GeometryLimits.require(stepsValue <= Double(GeometryLimits.segmentsPerArc / 2), "bore tessellation", document.name)
            let steps = max(16, ((Int(stepsValue) + 1) / 2) * 2)
            try GeometryLimits.require(steps * 2 + 3 <= GeometryLimits.meshVertices / 4 - pointCount, "bore wall points", document.name)
            let end = drill.end ?? drill.center
            let angle = atan2(end.y - drill.center.y, end.x - drill.center.x)
            var contour: [Point2D] = []
            // Two semicircles and their common tangents form a capsule; a
            // zero-length slot is exactly the circular case.
            for (center, start) in [(end, angle - .pi / 2), (drill.center, angle + .pi / 2)] {
                for index in 0...steps {
                    let a = start + .pi * Double(index) / Double(steps)
                    contour.append(Point2D(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
                }
            }
            contour.append(contour[0])
            pointCount += contour.count
            holes.append(contour)
            bores.append(Bore(drill: drill, bounds: Bounds2D.containing([drill.center, end])!.expanded(by: radius), innerRadius: radius * cos(.pi / Double(steps) / 2)))
        }
        var material = topology.materialContours
        if material.isEmpty && (!document.layers.contains { $0.kind == .outline } || topology.requiresInference) {
            let a = document.bounds.minimum, b = document.bounds.maximum
            material = [[a, Point2D(x: b.x, y: a.y), b, Point2D(x: a.x, y: b.y), a]]
        }
        let contours = try OutlineMaterialResolver.resolve([
            .init(contours: material, polarity: .dark),
            .init(contours: holes, polarity: .clear, usesWinding: true)
        ])
        struct Edge { let points: [Point2D]; let midpoint: Point2D }
        var edges = contours.flatMap { path in
            path.indices.dropLast().map { index in
                Edge(points: [path[index], path[index + 1]], midpoint: Point2D(x: (path[index].x + path[index + 1].x) / 2, y: (path[index].y + path[index + 1].y) / 2))
            }
        }
        try GeometryLimits.require(edges.count <= GeometryLimits.meshVertices / 4 - 2, "machined wall mesh", document.name)
        edges.sort { $0.midpoint.x < $1.midpoint.x }
        bores.sort { $0.bounds.minimum.x < $1.bounds.minimum.x }
        var next = 0, work = 0
        var active: [Bore] = [], result: [BoardWallPath] = []
        for edge in edges {
            try Task.checkCancellation()
            let p = edge.midpoint
            while next < bores.count && bores[next].bounds.minimum.x <= p.x + 1e-8 { active.append(bores[next]); next += 1 }
            active.removeAll { $0.bounds.maximum.x < p.x - 1e-8 }
            var plated = false
            for bore in active {
                work += 1
                try GeometryLimits.require(work <= 8_000_000, "bore wall material work", document.name)
                guard p.y >= bore.bounds.minimum.y - 1e-8 && p.y <= bore.bounds.maximum.y + 1e-8 else { continue }
                let a = bore.drill.center, b = bore.drill.end ?? a
                let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
                let t = length2 > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2)) : 0
                let distance = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if distance >= bore.innerRadius - 1e-8 && distance <= bore.drill.diameter / 2 + 1e-8 {
                    plated = plated || bore.drill.plated == true
                }
            }
            result.append(BoardWallPath(points: edge.points, plated: plated))
        }
        result += (topology.openPaths + topology.ambiguousPaths).map { BoardWallPath(points: $0, plated: false) }
        return result
    }
}
