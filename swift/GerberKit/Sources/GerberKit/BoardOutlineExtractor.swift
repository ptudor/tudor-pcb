import Foundation

public struct OutlineMaterialOperation: Sendable {
    public var contours: [[Point2D]]
    public var polarity: GerberPolarity
    var usesWinding: Bool = false
}

public struct BoardOutlineTopology: Sendable {
    public var closedContours: [[Point2D]] = []
    public var openPaths: [[Point2D]] = []
    public var ambiguousPaths: [[Point2D]] = []
    public var warnings: [String] = []
    public var materialOperations: [OutlineMaterialOperation] = []
    public var materialContours: [[Point2D]] = []
    public var requiresInference: Bool { !openPaths.isEmpty || !ambiguousPaths.isEmpty || !warnings.isEmpty }
    public var paths: [[Point2D]] { materialContours + openPaths + ambiguousPaths }
}

public enum BoardOutlineExtractor {
    /// Canonically directed edge segments from the same topology used for masks.
    public static func edgePaths(in document: BoardDocument) throws -> [[Point2D]] {
        try topology(in: document).paths.flatMap { path in
            path.indices.dropLast().map { [path[$0], path[$0 + 1]] }
        }
    }

    public static func contours(in document: BoardDocument, tolerance: Double = 0.08) throws -> [[Point2D]] {
        try topology(in: document, tolerance: tolerance).materialContours
    }

    public static func topology(in document: BoardDocument, tolerance: Double = 0.08) throws -> BoardOutlineTopology {
        try GeometryLimits.validate(document)
        try GeometryLimits.require(tolerance.isFinite && tolerance >= 1e-9 && tolerance <= 1, "outline endpoint tolerance", document.name)
        var result = BoardOutlineTopology()
        for layer in document.layers where layer.kind == .outline {
            var edges: [[Point2D]] = []
            var polarity = GerberPolarity.dark
            func flush() throws {
                guard !edges.isEmpty else { return }
                var batch = BoardOutlineTopology()
                try assemble(edges, tolerance: tolerance, source: layer.fileName, into: &batch)
                result.closedContours += batch.closedContours
                result.openPaths += batch.openPaths
                result.ambiguousPaths += batch.ambiguousPaths
                result.warnings += batch.warnings
                result.materialOperations.append(.init(contours: batch.closedContours, polarity: polarity))
                edges.removeAll(keepingCapacity: true)
            }
            for primitive in layer.primitives {
                try Task.checkCancellation()
                if primitive.polarity != polarity { try flush(); polarity = primitive.polarity }
                switch primitive {
                case let .line(start, end, _, _):
                    if start != end { edges.append([start, end]) }
                case let .arc(start, end, center, clockwise, _, _):
                    var path = try [start] + GeometryLimits.flattenArc(start: start, end: end, center: center, clockwise: clockwise, spacing: 0.1, minimum: 8, context: layer.fileName)
                    path[path.count - 1] = end
                    edges.append(path)
                case let .region(contours, _):
                    try flush()
                    var region: [[Point2D]] = []
                    for contour in contours where contour.count >= 3 {
                        var closed = contour
                        if closed.last != closed.first { closed.append(closed[0]) }
                        if abs(area(closed)) > 1e-12 {
                            region.append(canonical(closed, closed: true))
                        } else {
                            result.ambiguousPaths.append(canonical(closed, closed: false))
                            result.warnings.append(DiagnosticStrings.degenerateRegionContour(layer.fileName))
                        }
                    }
                    result.closedContours += region
                    result.materialOperations.append(.init(contours: region, polarity: polarity))
                case .flash:
                    result.warnings.append(DiagnosticStrings.flashedOutlineUnsupported(layer.fileName))
                }
            }
            try flush()
        }
        result.materialContours = try OutlineMaterialResolver.resolve(result.materialOperations)
        result.closedContours.sort(by: pathLess)
        result.openPaths.sort(by: pathLess)
        result.ambiguousPaths.sort(by: pathLess)
        result.warnings = Array(Set(result.warnings)).sorted()
        return result
    }

    private struct Cell: Hashable { let x: Int; let y: Int }

    private static func assemble(_ input: [[Point2D]], tolerance: Double, source: String, into result: inout BoardOutlineTopology) throws {
        guard !input.isEmpty else { return }
        let endpoints = input.flatMap { [$0.first!, $0.last!] }
        let counts = Dictionary(endpoints.map { ($0, 1) }, uniquingKeysWith: +)
        let nodes = counts.keys.sorted(by: pointLess)
        let nodeIDs = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element, $0.offset) })
        var representative = Array(nodes.indices)
        // Preserve exact junctions even if a fine outline has vertices closer
        // than tolerance. Only unpaired endpoints may be joined approximately.
        let orphans = nodes.indices.filter { counts[nodes[$0]] == 1 }
        var cells: [Cell: [Int]] = [:]
        func cell(_ point: Point2D) -> Cell { Cell(x: Int(floor(point.x / tolerance)), y: Int(floor(point.y / tolerance))) }
        for id in orphans {
            let key = cell(nodes[id])
            try GeometryLimits.require(cells[key, default: []].count < 64, "unresolved outline endpoint density", source)
            cells[key, default: []].append(id)
        }
        var neighbors: [Int: [Int]] = [:]
        for id in orphans {
            try Task.checkCancellation()
            let key = cell(nodes[id])
            for x in (key.x - 1)...(key.x + 1) {
                for y in (key.y - 1)...(key.y + 1) {
                    for other in cells[Cell(x: x, y: y), default: []] where other != id {
                        if distance(nodes[id], nodes[other]) <= tolerance { neighbors[id, default: []].append(other) }
                    }
                }
            }
        }
        for id in orphans {
            if let near = neighbors[id], near.count == 1, neighbors[near[0]]?.count == 1 {
                representative[id] = min(id, near[0])
                result.warnings.append(DiagnosticStrings.inferredEndpointJoin(source, tolerance: tolerance.formatted()))
            } else if (neighbors[id]?.count ?? 0) > 1 {
                result.warnings.append(DiagnosticStrings.ambiguousEndpointsUnjoined(source))
            }
        }
        var edges = input
        var ends: [(Int, Int)] = []
        var adjacency: [Int: [Int]] = [:]
        for index in edges.indices {
            let a = representative[nodeIDs[edges[index].first!]!], b = representative[nodeIDs[edges[index].last!]!]
            edges[index][0] = nodes[a]
            edges[index][edges[index].count - 1] = nodes[b]
            ends.append((a, b))
            adjacency[a, default: []].append(index)
            adjacency[b, default: []].append(index)
        }
        var visited = Set<Int>()
        for seed in nodes.indices where adjacency[seed] != nil {
            guard adjacency[seed]!.contains(where: { !visited.contains($0) }) else { continue }
            var componentNodes = Set<Int>(), componentEdges = Set<Int>(), queue = [seed]
            while let node = queue.popLast() {
                try Task.checkCancellation()
                guard componentNodes.insert(node).inserted else { continue }
                for edge in adjacency[node, default: []] {
                    componentEdges.insert(edge)
                    let pair = ends[edge]
                    queue.append(pair.0 == node ? pair.1 : pair.0)
                }
            }
            visited.formUnion(componentEdges)
            if componentNodes.contains(where: { adjacency[$0]!.count > 2 }) {
                result.ambiguousPaths += componentEdges.map { canonical(edges[$0], closed: false) }
                result.warnings.append(DiagnosticStrings.nonmanifoldJunction(source))
                continue
            }
            let openEnds = componentNodes.filter { adjacency[$0]!.count == 1 }.sorted()
            let start = openEnds.first ?? componentNodes.min()!
            var node = start, used = Set<Int>(), path: [Point2D] = []
            while let edge = adjacency[node, default: []].first(where: { !used.contains($0) }) {
                used.insert(edge)
                let forward = ends[edge].0 == node
                let segment = forward ? edges[edge] : Array(edges[edge].reversed())
                path.append(contentsOf: path.isEmpty ? segment : Array(segment.dropFirst()))
                node = forward ? ends[edge].1 : ends[edge].0
            }
            if openEnds.isEmpty, path.count >= 4, abs(area(path)) > 1e-12 {
                result.closedContours.append(canonical(path, closed: true))
            } else if !openEnds.isEmpty {
                result.openPaths.append(canonical(path, closed: false))
                result.warnings.append(DiagnosticStrings.openRoutedPaths(source))
            } else {
                result.ambiguousPaths.append(canonical(path, closed: false))
                result.warnings.append(DiagnosticStrings.degenerateRoutedContour(source))
            }
        }
    }

    static func area(_ points: [Point2D]) -> Double {
        guard points.count >= 3 else { return 0 }
        // Translation avoids cancellation on boards far from the coordinate origin.
        let origin = points[0]
        return points.indices.reduce(0) { sum, index in
            let a = points[index], b = points[(index + 1) % points.count]
            return sum + (a.x - origin.x) * (b.y - origin.y) - (b.x - origin.x) * (a.y - origin.y)
        } / 2
    }
    private static func canonical(_ input: [Point2D], closed: Bool) -> [Point2D] {
        guard input.count >= 2 else { return input }
        if !closed { return pointLess(input.last!, input[0]) ? Array(input.reversed()) : input }
        var points = input
        if points.last == points.first { points.removeLast() }
        if area(points) < 0 { points.reverse() }
        let first = points.indices.min { pointLess(points[$0], points[$1]) }!
        points = Array(points[first...]) + Array(points[..<first])
        points.append(points[0])
        return points
    }
    private static func pointLess(_ a: Point2D, _ b: Point2D) -> Bool { a.x == b.x ? a.y < b.y : a.x < b.x }
    private static func pathLess(_ a: [Point2D], _ b: [Point2D]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return pointLess(x, y) }
        return a.count < b.count
    }
    private static func distance(_ a: Point2D, _ b: Point2D) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
