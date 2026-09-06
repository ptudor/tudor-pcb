import CoreGraphics
import Foundation

/// Resolves region polarity and routed contour parity in millimeters, before
/// choosing a texture resolution. Input/intersection work and output stay bounded.
enum OutlineMaterialResolver {
    private struct Edge {
        let a: Point2D, b: Point2D
        let contour: Int, index: Int, count: Int
        var minX: Double { min(a.x, b.x) }
        var maxX: Double { max(a.x, b.x) }
        var minY: Double { min(a.y, b.y) }
        var maxY: Double { max(a.y, b.y) }
    }

    static func resolve(_ operations: [OutlineMaterialOperation]) throws -> [[Point2D]] {
        let all = operations.flatMap(\.contours)
        let intersects = try preflight(all)
        if operations.count == 1, operations[0].polarity == .dark, all.count == 1, !intersects { return all }
        var resolved: CGPath = CGMutablePath()
        var contours: [[Point2D]] = []
        for operation in operations where !operation.contours.isEmpty {
            try Task.checkCancellation()
            _ = try preflight(contours + operation.contours)
            let incoming = path(operation.contours).normalized(using: .evenOdd)
            resolved = operation.polarity == .dark ? resolved.union(incoming, using: .winding) : resolved.subtracting(incoming, using: .winding)
            contours = try extract(resolved)
        }
        // Normalize the global winding convention while retaining opposite hole
        // winding produced by the resolved material boundary.
        if let outer = contours.max(by: { abs(BoardOutlineExtractor.area($0)) < abs(BoardOutlineExtractor.area($1)) }), BoardOutlineExtractor.area(outer) < 0 {
            contours = contours.map { Array($0.reversed()) }
        }
        return contours
    }

    private static func path(_ contours: [[Point2D]]) -> CGPath {
        let path = CGMutablePath()
        for contour in contours where contour.count >= 3 {
            path.move(to: CGPoint(x: contour[0].x, y: contour[0].y))
            for point in contour.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
        return path
    }

    private static func preflight(_ contours: [[Point2D]]) throws -> Bool {
        var edges: [Edge] = []
        for (id, contour) in contours.enumerated() {
            try GeometryLimits.require(contour.count <= GeometryLimits.points - edges.count, "resolved outline points", "outline")
            for index in contour.indices.dropLast() {
                edges.append(Edge(a: contour[index], b: contour[index + 1], contour: id, index: index, count: contour.count - 1))
            }
        }
        edges.sort { $0.minX < $1.minX }
        var active: [Edge] = []
        var work = 0, possiblePoints = edges.count
        var intersects = false
        for edge in edges {
            try Task.checkCancellation()
            active.removeAll { $0.maxX < edge.minX }
            for prior in active {
                work += 1
                try GeometryLimits.require(work <= 8_000_000, "outline intersection work", "outline")
                guard prior.maxY >= edge.minY, edge.maxY >= prior.minY else { continue }
                if prior.contour == edge.contour,
                   abs(prior.index - edge.index) == 1 || abs(prior.index - edge.index) == edge.count - 1 { continue }
                possiblePoints += 2
                try GeometryLimits.require(possiblePoints <= GeometryLimits.points, "outline intersection output", "outline")
                intersects = true // Conservative candidate: native resolver handles exact intersection.
            }
            active.append(edge)
        }
        return intersects
    }

    private static func extract(_ path: CGPath) throws -> [[Point2D]] {
        var contours: [[Point2D]] = [], current: [Point2D] = []
        var count = 0, unsupported = false, tooLarge = false
        path.applyWithBlock { pointer in
            guard !tooLarge else { return }
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                if !current.isEmpty { contours.append(current) }
                current = [Point2D(x: element.points[0].x, y: element.points[0].y)]
            case .addLineToPoint:
                current.append(Point2D(x: element.points[0].x, y: element.points[0].y))
            case .closeSubpath:
                if let first = current.first, current.last != first { current.append(first); count += 1 }
                if !current.isEmpty { contours.append(current); current = [] }
            default: unsupported = true
            }
            count += 1
            tooLarge = count > GeometryLimits.points
        }
        if !current.isEmpty { contours.append(current) }
        try GeometryLimits.require(!tooLarge && !unsupported, "resolved linear outline output", "outline")
        return contours
    }
}
