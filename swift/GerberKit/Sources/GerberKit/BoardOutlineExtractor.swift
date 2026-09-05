import Foundation

public enum BoardOutlineExtractor {
    /// Every routed edge as a polyline, including open panel-rail paths.
    public static func edgePaths(in document: BoardDocument) throws -> [[Point2D]] {
        try GeometryLimits.validate(document)
        return try document.layers
            .filter { $0.kind == .outline }
            .flatMap { layer in
                try layer.primitives.compactMap { primitive -> [Point2D]? in
                    guard primitive.polarity == .dark else { return nil }
                    switch primitive {
                    case let .line(start, end, _, _):
                        return [start, end]
                    case let .arc(start, end, center, clockwise, _, _):
                        return try [start] + GeometryLimits.flattenArc(
                            start: start,
                            end: end,
                            center: center,
                            clockwise: clockwise, spacing: 0.1, minimum: 8, context: layer.fileName
                        )
                    case let .region(contours, _):
                        return contours.first
                    case .flash:
                        return nil
                    }
                }
            }
    }

    /// Returns every closed routed contour in document order. Disconnected
    /// panel rails remain separate solids; nested contours become cutouts when
    /// the rasterizer fills them with the even/odd rule.
    public static func contours(in document: BoardDocument, tolerance: Double = 0.08) throws -> [[Point2D]] {
        var closedContours: [[Point2D]] = []
        for layer in document.layers where layer.kind == .outline {
            var current: [Point2D] = []
            func finish() {
                guard current.count >= 3,
                      let first = current.first,
                      let last = current.last,
                      distance(first, last) < tolerance,
                      abs(polygonArea(current)) > tolerance * tolerance else {
                    current.removeAll(keepingCapacity: true)
                    return
                }
                closedContours.append(current)
                current.removeAll(keepingCapacity: true)
            }

            for segment in try edgePaths(in: BoardDocument(name: "outline", layers: [layer])) {
                if current.isEmpty {
                    current = segment
                } else if let last = current.last,
                          let first = segment.first,
                          distance(last, first) < tolerance {
                    current.append(contentsOf: segment.dropFirst())
                    if let chainFirst = current.first,
                       let chainLast = current.last,
                       distance(chainFirst, chainLast) < tolerance {
                        finish()
                    }
                } else {
                    finish()
                    current = segment
                }
            }
            finish()
        }
        return closedContours
    }

    private static func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func polygonArea(_ points: [Point2D]) -> Double {
        guard points.count >= 3 else { return 0 }
        var area = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        return area / 2
    }
}
