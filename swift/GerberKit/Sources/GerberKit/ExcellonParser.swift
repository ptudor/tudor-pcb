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

        var machine = ExcellonMachine(fileName: fileName, plated: plated)
        for sourceLine in source.split(whereSeparator: \.isNewline) {
            try Task.checkCancellation()
            try machine.consume(sourceLine.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), budget: &budget)
        }
        guard machine.terminated else { throw machine.format.error("EOF", "Missing drill end-of-program command.") }
        return machine.result
    }
}

private struct ExcellonMachine {
    enum Mode { case drill, rapid, linear }
    var format: ExcellonCoordinateFormat
    let plated: Bool?
    var tools: [Int: Double] = [:]
    var selectedTool: Int?
    var current = Point2D.zero
    var result: [DrillHit] = []
    var mode = Mode.drill
    var toolDown = false
    var terminated = false
    var canRepeat = false

    init(fileName: String, plated: Bool?) {
        format = ExcellonCoordinateFormat(fileName: fileName)
        self.plated = plated
    }

    mutating func consume(_ source: String, budget: inout ImportBudget) throws {
        guard !source.isEmpty else { return }
        if source.hasPrefix(";") {
            if !terminated { _ = try format.declaration(source) }
            return
        }
        guard !terminated else { throw format.error(source, "Data after drill end-of-program.") }
        if try format.declaration(source) { return }
        if ["M48", "M95", "%", "FMAT,2", "VER,1"].contains(source) { return }
        if source.hasPrefix("M47,") { return }
        if source == "M30" || source == "M00" {
            guard !toolDown else { throw format.error(source, "Unterminated tool-down route.") }
            terminated = true; return
        }
        if source == "M15" {
            _ = try diameter(source)
            guard mode != .drill, !toolDown else { throw format.error(source, "Invalid route tool-down state.") }
            toolDown = true; canRepeat = false; return
        }
        if source == "M16" || source == "M17" { toolDown = false; return }
        if source.hasPrefix("T") {
            guard !toolDown else { throw format.error(source, "Tool change while routing.") }
            let digits = source.dropFirst().prefix(while: \.isNumber)
            guard let tool = Int(digits), tool <= Int(Int32.max) else { throw format.error(source, "Invalid tool number.") }
            let suffix = String(source.dropFirst(1 + digits.count))
            if suffix.isEmpty {
                if tool == 0 { selectedTool = nil }
                else {
                    guard tools[tool] != nil else { throw format.error(source, "Undefined tool T\(tool).") }
                    selectedTool = tool
                }
            } else {
                let fields = try numericFields(suffix, allowed: "CFSBH", line: source)
                guard tool > 0, let text = fields["C"], let scale = format.unitScale,
                      let value = Double(text), value.isFinite, value > 0,
                      value * scale <= GeometryLimits.coordinateMagnitude else { throw format.error(source, "Invalid tool definition or undeclared units.") }
                guard tools[tool] == nil else { throw format.error(source, "Redefined tool T\(tool).") }
                tools[tool] = value * scale
            }
            canRepeat = false; return
        }
        var line = source
        while line.hasPrefix("G") && !line.hasPrefix("G85") {
            let digits = line.dropFirst().prefix(while: \.isNumber)
            guard let code = Int(digits) else { throw format.error(source, "Malformed G command.") }
            line.removeFirst(1 + digits.count)
            switch code {
            case 90: format.absolute = true
            case 91: format.absolute = false
            case 0:
                guard !toolDown else { throw format.error(source, "Rapid positioning with tool down is unsupported.") }
                mode = .rapid; canRepeat = false
            case 1: mode = .linear; canRepeat = false
            case 5:
                guard !toolDown else { throw format.error(source, "Drill mode while routing.") }
                mode = .drill
            case 2, 3: throw format.error(source, "Unsupported arc route; drill layer rejected.")
            default: throw format.error(source, "Unsupported Excellon G command.")
            }
        }
        if line.isEmpty { return }
        if line.contains("G85") {
            guard !toolDown else { throw format.error(source, "G85 during a tool-down route.") }
            let parts = line.components(separatedBy: "G85")
            guard parts.count == 2, !parts[1].isEmpty else { throw format.error(source, "Malformed G85 slot.") }
            let start = parts[0].isEmpty ? current : try target(parts[0], from: current, line: source)
            let end = try target(parts[1], from: start, line: source)
            try append(start, end: end, line: source, budget: &budget)
            current = end; canRepeat = false; return
        }
        if line.hasPrefix("R") {
            let digits = line.dropFirst().prefix(while: \.isNumber)
            guard mode == .drill, canRepeat, let count = Int(digits), count > 0,
                  count <= GeometryLimits.repeats else { throw format.error(source, "Invalid or unsupported drill repeat.") }
            let fields = try numericFields(String(line.dropFirst(1 + digits.count)), allowed: "XY", line: source)
            let dx = try fields["X"].map { try format.decode($0, line: source) } ?? 0
            let dy = try fields["Y"].map { try format.decode($0, line: source) } ?? 0
            let origin = current
            try GeometryLimits.point(Point2D(x: origin.x + Double(count) * dx, y: origin.y + Double(count) * dy), context: source)
            try reserve(count, pointsPerHit: 1, line: source, budget: &budget)
            let size = try diameter(source)
            for index in 1...count {
                try Task.checkCancellation()
                current = Point2D(x: origin.x + Double(index) * dx, y: origin.y + Double(index) * dy)
                result.append(DrillHit(center: current, diameter: size, plated: plated))
            }
            return
        }
        let next = try target(line, from: current, line: source)
        switch mode {
        case .drill:
            try append(next, end: nil, line: source, budget: &budget)
            canRepeat = true
        case .rapid: break
        case .linear:
            if toolDown { try append(current, end: next, line: source, budget: &budget) }
        }
        current = next
    }

    func diameter(_ line: String) throws -> Double {
        guard let selectedTool, let value = tools[selectedTool] else { throw format.error(line, "Machining requires a defined selected tool.") }
        return value
    }
    func numericFields(_ text: String, allowed: String, line: String) throws -> [Character: String] {
        let number = #"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)"#
        guard !text.isEmpty, text.range(of: "^(?:[" + allowed + "]" + number + ")+$", options: .regularExpression) != nil else {
            throw format.error(line, "Malformed coordinates or unsupported Excellon command.")
        }
        var fields: [Character: String] = [:]
        var rest = text[...]
        while let key = rest.first {
            rest.removeFirst()
            let value = rest.prefix { !$0.isLetter }
            guard fields[key] == nil else { throw format.error(line, "Repeated coordinate/modifier \(key).") }
            fields[key] = String(value)
            rest.removeFirst(value.count)
        }
        return fields
    }
    func target(_ text: String, from current: Point2D, line: String) throws -> Point2D {
        let fields = try numericFields(text, allowed: "XY", line: line)
        let x = try fields["X"].map { try format.decode($0, line: line) }
        let y = try fields["Y"].map { try format.decode($0, line: line) }
        let target = format.absolute
            ? Point2D(x: x ?? current.x, y: y ?? current.y)
            : Point2D(x: current.x + (x ?? 0), y: current.y + (y ?? 0))
        try GeometryLimits.point(target, context: format.fileName + ": " + line)
        return target
    }
    func reserve(_ count: Int, pointsPerHit: Int, line: String, budget: inout ImportBudget) throws {
        try budget.charge("geometry objects", count, maximum: min(GeometryLimits.primitives, budget.limits.geometryObjects), path: format.fileName)
        try budget.charge("geometry points", count * pointsPerHit, maximum: min(GeometryLimits.points, budget.limits.geometryPoints), path: format.fileName)
        try budget.charge("allocations", count * 128, maximum: budget.limits.allocationBytes, path: format.fileName)
    }
    mutating func append(_ center: Point2D, end: Point2D?, line: String, budget: inout ImportBudget) throws {
        let size = try diameter(line)
        try reserve(1, pointsPerHit: end == nil ? 1 : 2, line: line, budget: &budget)
        result.append(DrillHit(center: center, end: end, diameter: size, plated: plated))
    }
}
