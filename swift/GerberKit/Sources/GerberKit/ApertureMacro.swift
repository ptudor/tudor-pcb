import Foundation

/// Definitions retain raw expressions until an ADD provides dimensionless parameters.
struct ApertureMacro {
    let statements: [String]

    func instantiate(parameters: [Double], scale: Double, fileName: String, command: String) throws -> ApertureShape {
        try GeometryLimits.require(parameters.count <= 10_000, "macro parameters", command)
        var variables = Dictionary(uniqueKeysWithValues: parameters.enumerated().map { ($0.offset + 1, $0.element) })
        var objects: [GerberPrimitive] = []
        var points = 0
        func invalid(_ reason: String) -> GerberParseError { .invalidDefinition(fileName: fileName, command: command, reason: reason) }
        func integer(_ value: Double, range: ClosedRange<Int>) throws -> Int {
            guard value.isFinite, value.rounded() == value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else { throw invalid("Invalid macro integer/count.") }
            return Int(value)
        }
        func length(_ value: Double, positive: Bool = false) throws -> Double {
            let result = value * scale
            guard result.isFinite, result >= 0, !positive || result > 0 else { throw invalid("Invalid macro dimension.") }
            try GeometryLimits.length(result, context: command)
            return result
        }
        func rotated(_ p: Point2D, by degrees: Double) throws -> Point2D {
            let a = degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
            let result = Point2D(x: (p.x * cos(a) - p.y * sin(a)) * scale, y: (p.x * sin(a) + p.y * cos(a)) * scale)
            try GeometryLimits.point(result, context: command)
            return result
        }
        func polygon(_ points: [Point2D], rotation: Double) throws -> ApertureShape {
            .custom(points: try points.map { try rotated($0, by: rotation) })
        }
        for statement in statements {
            try Task.checkCancellation()
            let text = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("0 ") || text == "0" { continue }
            if text.hasPrefix("$") {
                let pair = text.split(separator: "=", omittingEmptySubsequences: false)
                guard pair.count == 2, let id = Int(pair[0].dropFirst()), (1...10_000).contains(id), variables[id] == nil else {
                    throw invalid("Invalid or redefined macro variable.")
                }
                variables[id] = try MacroExpression(String(pair[1]), variables: variables).evaluate()
                continue
            }
            let fields = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let first = fields.first, let code = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw invalid("Malformed macro primitive.") }
            if code == 0 { continue }
            let v = try fields.dropFirst().map { try MacroExpression($0, variables: variables).evaluate() }
            let primitive: GerberPrimitive
            switch code {
            case 1:
                guard (4...5).contains(v.count) else { throw invalid("Circle macro requires exposure, diameter, center and optional rotation.") }
                let exposure = try integer(v[0], range: 0...1)
                let center = try rotated(Point2D(x: v[2], y: v[3]), by: v.count == 5 ? v[4] : 0)
                primitive = .flash(center: center, shape: .circle(diameter: try length(v[1])), polarity: exposure == 1 ? .dark : .clear)
            case 4:
                guard v.count >= 2 else { throw invalid("Incomplete outline macro.") }
                let exposure = try integer(v[0], range: 0...1)
                let count = try integer(v[1], range: 3...5000)
                guard v.count == 5 + 2 * count else { throw invalid("Incomplete outline coordinates/rotation.") }
                var contour: [Point2D] = []
                for i in 0...count { contour.append(Point2D(x: v[2 + i * 2], y: v[3 + i * 2])) }
                guard contour.first == contour.last else { throw invalid("Macro outline is not closed.") }
                primitive = .flash(center: .zero, shape: try polygon(Array(contour.dropLast()), rotation: v.last!), polarity: exposure == 1 ? .dark : .clear)
            case 5:
                guard v.count == 6 else { throw invalid("Incomplete polygon macro.") }
                let exposure = try integer(v[0], range: 0...1)
                let count = try integer(v[1], range: 3...12)
                primitive = .flash(center: try rotated(Point2D(x: v[2], y: v[3]), by: v[5]),
                    shape: .polygon(diameter: try length(v[4]), vertices: count, rotationDegrees: v[5].truncatingRemainder(dividingBy: 360)), polarity: exposure == 1 ? .dark : .clear)
            case 20, 2:
                guard v.count == 7 else { throw invalid("Incomplete vector-line macro.") }
                let exposure = try integer(v[0], range: 0...1)
                _ = try length(v[1])
                let dx = v[4] - v[2], dy = v[5] - v[3]
                let span = hypot(dx, dy)
                guard span.isFinite else { throw invalid("Invalid vector-line endpoints.") }
                let divisor = span == 0 ? 1 : span
                let nx = -dy / divisor * v[1] / 2, ny = dx / divisor * v[1] / 2
                let contour = [Point2D(x: v[2] + nx, y: v[3] + ny), Point2D(x: v[4] + nx, y: v[5] + ny),
                    Point2D(x: v[4] - nx, y: v[5] - ny), Point2D(x: v[2] - nx, y: v[3] - ny)]
                primitive = .flash(center: .zero, shape: try polygon(contour, rotation: v[6]), polarity: exposure == 1 ? .dark : .clear)
            case 21, 22:
                guard v.count == 6 else { throw invalid("Incomplete rectangle macro.") }
                let exposure = try integer(v[0], range: 0...1)
                _ = try length(v[1]); _ = try length(v[2])
                let x = v[3] - (code == 21 ? v[1] / 2 : 0), y = v[4] - (code == 21 ? v[2] / 2 : 0)
                let contour = [Point2D(x: x, y: y), Point2D(x: x + v[1], y: y), Point2D(x: x + v[1], y: y + v[2]), Point2D(x: x, y: y + v[2])]
                primitive = .flash(center: .zero, shape: try polygon(contour, rotation: v[5]), polarity: exposure == 1 ? .dark : .clear)
            case 7:
                guard v.count == 6, v[2] > v[3], v[4] >= 0, v[4] < v[2] / sqrt(2) else { throw invalid("Invalid thermal dimensions/gap.") }
                let outer = try length(v[2]), inner = try length(v[3]), gap = try length(v[4])
                let a = v[5].truncatingRemainder(dividingBy: 360) * .pi / 180
                func gapRectangle(_ width: Double, _ height: Double) -> ApertureShape {
                    .custom(points: [Point2D(x: -width / 2, y: -height / 2), Point2D(x: width / 2, y: -height / 2),
                        Point2D(x: width / 2, y: height / 2), Point2D(x: -width / 2, y: height / 2)].map {
                            Point2D(x: $0.x * cos(a) - $0.y * sin(a), y: $0.x * sin(a) + $0.y * cos(a))
                        })
                }
                // The thermal's holes are local to that primitive, so they also
                // preserve earlier primitives within the enclosing macro.
                let thermal = ApertureShape.compound(primitives: [
                    .flash(center: .zero, shape: .circle(diameter: outer), polarity: .dark),
                    .flash(center: .zero, shape: .circle(diameter: inner), polarity: .clear),
                    .flash(center: .zero, shape: gapRectangle(outer, gap), polarity: .clear),
                    .flash(center: .zero, shape: gapRectangle(gap, outer), polarity: .clear)
                ])
                primitive = .flash(center: try rotated(Point2D(x: v[0], y: v[1]), by: v[5]), shape: thermal, polarity: .dark)
            default: throw invalid("Unsupported macro primitive \\(code); layer rejected.")
            }
            let added = try GeometryLimits.cost(primitive, context: command)
            try GeometryLimits.require(added <= GeometryLimits.points - points && objects.count < 5000, "macro geometry", command)
            points += added
            objects.append(primitive)
        }
        guard !objects.isEmpty else { throw invalid("Macro contains no geometry.") }
        return .compound(primitives: objects)
    }
}

private struct MacroExpression {
    let characters: [Character]
    let variables: [Int: Double]
    var index = 0
    init(_ source: String, variables: [Int: Double]) {
        characters = Array(source.filter { !$0.isWhitespace })
        self.variables = variables
    }
    func evaluate() throws -> Double {
        guard characters.count <= 4096 else { throw GeometryLimitError(resource: "macro expression length", context: "AM") }
        var parser = self
        let result = try parser.sum(depth: 0)
        guard parser.index == characters.count else { throw MacroEvaluationError.invalidExpression }
        return try checked(result)
    }
    private func checked(_ value: Double) throws -> Double {
        guard value.isFinite else { throw MacroEvaluationError.invalidExpression }
        return value
    }
    mutating func sum(depth: Int) throws -> Double {
        var value = try product(depth: depth)
        while index < characters.count, characters[index] == "+" || characters[index] == "-" {
            let op = characters[index]; index += 1
            let rhs = try product(depth: depth)
            value = try checked(op == "+" ? value + rhs : value - rhs)
        }
        return value
    }
    mutating func product(depth: Int) throws -> Double {
        var value = try atom(depth: depth)
        while index < characters.count, [Character("x"), "X", "/"].contains(characters[index]) {
            let op = characters[index]; index += 1
            let rhs = try atom(depth: depth)
            guard op != "/" || rhs != 0 else { throw MacroEvaluationError.invalidExpression }
            value = try checked(op == "/" ? value / rhs : value * rhs)
        }
        return value
    }
    mutating func atom(depth: Int) throws -> Double {
        try GeometryLimits.require(depth < 64, "macro expression depth", "AM")
        guard index < characters.count else { throw MacroEvaluationError.invalidExpression }
        let character = characters[index]
        if character == "+" || character == "-" {
            index += 1
            return try checked((character == "-" ? -1 : 1) * atom(depth: depth + 1))
        }
        if character == "(" {
            index += 1
            let value = try sum(depth: depth + 1)
            guard index < characters.count, characters[index] == ")" else { throw MacroEvaluationError.invalidExpression }
            index += 1; return value
        }
        if character == "$" {
            index += 1
            let start = index
            while index < characters.count, characters[index].isNumber { index += 1 }
            guard let id = Int(String(characters[start..<index])), (1...10_000).contains(id) else { throw MacroEvaluationError.invalidExpression }
            return variables[id, default: 0]
        }
        let start = index
        while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
        guard start < index, let value = Double(String(characters[start..<index])) else { throw MacroEvaluationError.invalidExpression }
        return try checked(value)
    }
}

private enum MacroEvaluationError: Error, LocalizedError {
    case invalidExpression
    var errorDescription: String? { "Invalid, nonfinite, or division-by-zero macro expression." }
}
