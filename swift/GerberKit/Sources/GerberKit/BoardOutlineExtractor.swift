import Foundation

public enum BoardOutlineExtractor {
    /// Every routed edge as a polyline, including open panel-rail paths.
    public static func edgePaths(in document: BoardDocument) -> [[Point2D]] {
        document.layers
            .filter { $0.kind == .outline }
            .flatMap { layer in
                layer.primitives.compactMap { primitive -> [Point2D]? in
                    guard primitive.polarity == .dark else { return nil }
                    switch primitive {
                    case let .line(start, end, _, _):
                        return [start, end]
                    case let .arc(start, end, center, clockwise, _, _):
                        return [start] + flattenArc(
                            start: start,
                            end: end,
                            center: center,
                            clockwise: clockwise
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
    public static func contours(in document: BoardDocument, tolerance: Double = 0.08) -> [[Point2D]] {
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

            for segment in edgePaths(in: BoardDocument(name: "outline", layers: [layer])) {
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

    private static func flattenArc(
        start: Point2D,
        end: Point2D,
        center: Point2D,
        clockwise: Bool
    ) -> [Point2D] {
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.000_001 else { return [end] }
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        var sweep = atan2(end.y - center.y, end.x - center.x) - startAngle
        if clockwise, sweep >= 0 { sweep -= 2 * .pi }
        if !clockwise, sweep <= 0 { sweep += 2 * .pi }
        if start == end { sweep = clockwise ? -2 * .pi : 2 * .pi }
        let count = max(8, Int(ceil(abs(sweep) * radius / 0.1)))
        return (1...count).map { index in
            let angle = startAngle + sweep * Double(index) / Double(count)
            return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
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
