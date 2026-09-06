import Foundation

struct MachiningMetadata {
    var plated: Bool?
    var span: DrillLayerSpan?

    init(source: String, fileName: String, plated: Bool?) throws {
        self.plated = plated
        let functions = LayerClassifier.fileFunctions(in: source)
        guard let fields = functions.first(where: { ["plated", "nonplated"].contains($0.first ?? "") }) else { return }
        func error(_ reason: String) -> ExcellonParseError { .init(fileName: fileName, command: "FileFunction," + fields.joined(separator: ","), reason: reason) }
        guard functions.allSatisfy({ $0 == fields }), (4...5).contains(fields.count),
              let start = Int(fields[1]), let end = Int(fields[2]), (1...256).contains(start), (1...256).contains(end), start != end else { throw error("Invalid or conflicting drill layer span.") }
        guard fields[3] == (fields[0] == "plated" ? "pth" : "npth") else { throw error("Blind/buried or unknown drill spans cannot be rendered as through holes.") }
        if fields.count == 5, !["drill", "rout", "mixed"].contains(fields[4]) { throw error("Unsupported machining label.") }
        self.plated = fields[0] == "plated"
        span = DrillLayerSpan(start: min(start, end), end: max(start, end))
    }
}

enum GerberMachiningConverter {
    static func convert(_ layer: GerberLayer, source: String, budget: inout ImportBudget) throws -> [DrillHit] {
        let plating: Bool?
        if case let .drill(value) = layer.kind { plating = value } else { plating = nil }
        let metadata = try MachiningMetadata(source: source, fileName: layer.fileName, plated: plating)
        var hits: [DrillHit] = []
        func error(_ reason: String) -> ExcellonParseError { .init(fileName: layer.fileName, command: "Gerber machining geometry", reason: reason) }
        for primitive in layer.primitives {
            try Task.checkCancellation()
            guard primitive.polarity == .dark else { throw error("Clear machining operations are unsupported; the entire drill layer was rejected.") }
            let center: Point2D, end: Point2D?, diameter: Double
            switch primitive {
            case let .flash(point, .circle(size), _):
                center = point; end = nil; diameter = size
            case let .flash(point, .obround(width, height), _):
                diameter = min(width, height)
                let offset = Point2D(x: max(0, width - height) / 2, y: max(0, height - width) / 2)
                center = Point2D(x: point.x - offset.x, y: point.y - offset.y)
                end = point + offset
            case let .line(start, finish, width, _):
                center = start; end = finish; diameter = width
            default: throw error("Unsupported machining shape or curved route; the entire drill layer was rejected.")
            }
            guard diameter > 0 else { throw error("Machining diameter must be positive.") }
            try budget.charge("geometry objects", 1, maximum: budget.limits.geometryObjects, path: layer.fileName)
            try budget.charge("geometry points", end == nil ? 1 : 2, maximum: budget.limits.geometryPoints, path: layer.fileName)
            try budget.charge("allocations", 128, maximum: budget.limits.allocationBytes, path: layer.fileName)
            hits.append(DrillHit(center: center, end: end, diameter: diameter, plated: metadata.plated, layerSpan: metadata.span))
        }
        return hits
    }
}
