import Foundation

public struct ExcellonParser: Sendable {
    public init() { }

    public func parse(data: Data, fileName: String) throws -> [DrillHit] {
        var budget = ImportBudget(limits: .init())
        try budget.input(data.count, path: fileName)
        try budget.decodedText(data.count, path: fileName)
        return try parse(data: data, fileName: fileName, budget: &budget)
    }

    func parse(data: Data, fileName: String, budget: inout ImportBudget) throws -> [DrillHit] {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw GerberParseError.textEncoding
        }

        let kind = LayerClassifier.classify(fileName: fileName, contents: source)
        let plated: Bool?
        if case let .drill(value) = kind { plated = value } else { plated = nil }

        var format = ExcellonCoordinateFormat(fileName: fileName)
        var tools: [Int: Double] = [:]
        var selectedTool: Int?
        var current = Point2D.zero
        var result: [DrillHit] = []

        for sourceLine in source.split(whereSeparator: \.isNewline) {
            try Task.checkCancellation()
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !line.isEmpty else { continue }
            if try format.declaration(line) { continue }
            if line.hasPrefix(";") { continue }
            if line.hasPrefix("G90") { format.absolute = true }
            if line.hasPrefix("G91") { format.absolute = false }

            if line.hasPrefix("T"), let cIndex = line.firstIndex(of: "C") {
                let toolText = line[line.index(after: line.startIndex)..<cIndex]
                let diameterText = line[line.index(after: cIndex)...]
                    .prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
                guard let tool = Int(toolText), tool > 0, tool <= Int(Int32.max),
                      let scale = format.unitScale, let diameter = Double(diameterText),
                      diameter.isFinite, diameter > 0, diameter * scale <= GeometryLimits.coordinateMagnitude else {
                    throw format.error(line, "Invalid tool number, diameter or undeclared units.")
                }
                tools[tool] = diameter * scale
                continue
            }

            if line.hasPrefix("T"), let tool = Int(line.dropFirst()), !line.contains("X"), !line.contains("Y") {
                selectedTool = tool
                continue
            }

            let fields = coordinateFields(in: line)
            guard fields["X"] != nil || fields["Y"] != nil else { continue }
            let x = try fields["X"].map { try format.decode($0, line: line) }
            let y = try fields["Y"].map { try format.decode($0, line: line) }
            current = format.absolute
                ? Point2D(x: x ?? current.x, y: y ?? current.y)
                : Point2D(x: current.x + (x ?? 0), y: current.y + (y ?? 0))
            try GeometryLimits.point(current, context: fileName + ": " + line)
            let diameter = selectedTool.flatMap { tools[$0] } ?? 0.3
            try budget.charge("geometry objects", 1, maximum: budget.limits.geometryObjects, path: fileName)
            try budget.charge("geometry points", 1, maximum: budget.limits.geometryPoints, path: fileName)
            try budget.charge("allocations", 128, maximum: budget.limits.allocationBytes, path: fileName)
            result.append(DrillHit(center: current, diameter: diameter, plated: plated))
        }

        return result
    }

    private func coordinateFields(in line: String) -> [Character: String] {
        let characters = Array(line)
        var fields: [Character: String] = [:]
        var index = 0
        while index < characters.count {
            let key = characters[index]
            guard key == "X" || key == "Y" else {
                index += 1
                continue
            }
            index += 1
            let start = index
            while index < characters.count,
                  characters[index].isNumber || characters[index] == "." || characters[index] == "+" || characters[index] == "-" {
                index += 1
            }
            fields[key] = String(characters[start..<index])
        }
        return fields
    }

}
