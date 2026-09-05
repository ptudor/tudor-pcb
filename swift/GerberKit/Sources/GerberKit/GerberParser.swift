import Foundation

public enum GerberParseError: Error, LocalizedError, Sendable {
    case textEncoding
    case missingGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .textEncoding:
            "The layer is not an ASCII or UTF-8 Gerber file."
        case let .missingGeometry(fileName):
            "No drawable Gerber geometry was found in \(fileName)."
        }
    }
}

public struct GerberParser: Sendable {
    public init() { }

    public func parse(data: Data, fileName: String) throws -> GerberLayer {
        var budget = ImportBudget(limits: .init())
        try budget.input(data.count, path: fileName)
        try budget.decodedText(data.count, path: fileName)
        return try parse(data: data, fileName: fileName, budget: &budget)
    }

    func parse(data: Data, fileName: String, budget: inout ImportBudget) throws -> GerberLayer {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw GerberParseError.textEncoding
        }

        var machine = ParserMachine(fileName: fileName, source: source)
        machine.maximumObjects = min(budget.remaining("geometry objects", maximum: budget.limits.geometryObjects), budget.remaining("allocations", maximum: budget.limits.allocationBytes) / 256)
        machine.maximumPoints = min(budget.remaining("geometry points", maximum: budget.limits.geometryPoints), budget.remaining("allocations", maximum: budget.limits.allocationBytes) / 32)
        machine.consume(source)
        if let failure = machine.failure { throw failure }
        try budget.charge("geometry objects", machine.primitives.count, maximum: budget.limits.geometryObjects, path: fileName)
        try budget.charge("geometry points", machine.pointCount, maximum: budget.limits.geometryPoints, path: fileName)
        try budget.charge("allocations", machine.primitives.count * 128, maximum: budget.limits.allocationBytes, path: fileName)
        try budget.charge("allocations", machine.pointCount * 16, maximum: budget.limits.allocationBytes, path: fileName)
        guard !machine.primitives.isEmpty else {
            throw GerberParseError.missingGeometry(fileName)
        }
        return GerberLayer(
            fileName: fileName,
            kind: LayerClassifier.classify(fileName: fileName, contents: source),
            primitives: machine.primitives,
            sourceGenerator: Self.generator(in: source)
        )
    }

    private static func generator(in source: String) -> String? {
        for line in source.split(whereSeparator: \.isNewline).prefix(24) {
            let text = String(line)
            for marker in ["EasyEDA", "KiCad", "EAGLE", "Altium", "jlccam", "JLCPCB"] where text.localizedCaseInsensitiveContains(marker) {
                return text
                    .replacingOccurrences(of: "G04", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}

private struct CoordinateFormat {
    var integerDigits = 3
    var decimalDigits = 6
    var leadingZerosOmitted = true
    var unitScale = 1.0

    func decode(_ raw: String) -> Double? {
        if raw.contains(".") {
            return Double(raw).map { $0 * unitScale }
        }

        let isNegative = raw.hasPrefix("-")
        let isPositive = raw.hasPrefix("+")
        var digits = raw
        if isNegative || isPositive { digits.removeFirst() }
        guard !digits.isEmpty else { return nil }

        let totalDigits = integerDigits + decimalDigits
        if !leadingZerosOmitted, digits.count < totalDigits {
            digits += String(repeating: "0", count: totalDigits - digits.count)
        }
        guard let integer = Double(digits) else { return nil }
        let signed = isNegative ? -integer : integer
        return signed / pow(10, Double(decimalDigits)) * unitScale
    }
}

private enum Interpolation {
    case linear
    case clockwise
    case counterclockwise
}

private struct StepRepeat {
    var xCount = 1
    var yCount = 1
    var xStep = 0.0
    var yStep = 0.0
}

private struct ParserMachine {
    let fileName: String
    let source: String
    var format = CoordinateFormat()
    var apertures: [Int: ApertureShape] = [:]
    var macros: [String: ApertureShape] = [:]
    var currentAperture: Int?
    var currentPoint = Point2D.zero
    var interpolation = Interpolation.linear
    var polarity = GerberPolarity.dark
    var absoluteCoordinates = true
    var lastOperation = 2
    var stepRepeat = StepRepeat()
    var primitives: [GerberPrimitive] = []
    var regionContours: [[Point2D]]?
    var failure: (any Error)?
    var maximumObjects = 1_000_000
    var maximumPoints = 4_000_000
    var pointCount = 0

    init(fileName: String, source: String) {
        self.fileName = fileName
        self.source = source
    }

    mutating func consume(_ source: String) {
        var buffer = ""
        var isExtended = false

        func cleaned(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for character in source {
            if failure != nil { return }
            if Task.isCancelled { failure = CancellationError(); return }
            if character == "%" {
                if isExtended {
                    consumeExtended(cleaned(buffer))
                    buffer.removeAll(keepingCapacity: true)
                    isExtended = false
                } else {
                    let pending = cleaned(buffer)
                    if !pending.isEmpty { consumeStandard(pending) }
                    buffer.removeAll(keepingCapacity: true)
                    isExtended = true
                }
            } else if character == "*", !isExtended {
                let command = cleaned(buffer)
                if !command.isEmpty { consumeStandard(command) }
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(character)
            }
        }

        let trailing = cleaned(buffer)
        if !trailing.isEmpty {
            if isExtended { consumeExtended(trailing) } else { consumeStandard(trailing) }
        }
    }

    mutating func consumeExtended(_ block: String) {
        let commands = block.split(separator: "*", omittingEmptySubsequences: true).map(String.init)
        guard let first = commands.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        if first.hasPrefix("FS") {
            parseFormat(first)
        } else if first == "MOMM" {
            format.unitScale = 1
        } else if first == "MOIN" {
            format.unitScale = 25.4
        } else if first.hasPrefix("AM") {
            parseMacro(commands)
        } else if first.hasPrefix("ADD") {
            parseAperture(first)
        } else if first == "LPD" {
            polarity = .dark
        } else if first == "LPC" {
            polarity = .clear
        } else if first.hasPrefix("SR") {
            parseStepRepeat(first)
        }
    }

    mutating func parseFormat(_ command: String) {
        format.leadingZerosOmitted = !command.contains("T")
        absoluteCoordinates = !command.contains("I")
        guard let xIndex = command.firstIndex(of: "X") else { return }
        let suffix = command[command.index(after: xIndex)...]
        let digits = suffix.prefix(while: \.isNumber)
        guard digits.count >= 2 else { return }
        format.integerDigits = Int(String(digits.prefix(1))) ?? format.integerDigits
        format.decimalDigits = Int(String(digits.dropFirst().prefix(1))) ?? format.decimalDigits
    }

    mutating func parseMacro(_ commands: [String]) {
        let name = String(commands[0].dropFirst(2))
        var points: [Point2D] = []
        var fallbackDiameter = 0.2

        for primitive in commands.dropFirst() {
            let values = primitive.split(separator: ",").map(String.init)
            guard let code = Int(values.first ?? "") else { continue }
            if code == 4, values.count >= 7 {
                let count = Int(values[2]) ?? 0
                for index in 0..<count {
                    let xIndex = 3 + index * 2
                    let yIndex = xIndex + 1
                    guard yIndex < values.count,
                          let x = Double(values[xIndex]),
                          let y = Double(values[yIndex]) else { continue }
                    points.append(Point2D(x: x * format.unitScale, y: y * format.unitScale))
                }
            } else if code == 1, values.count >= 5, let diameter = Double(values[2]) {
                fallbackDiameter = max(fallbackDiameter, diameter * format.unitScale)
            }
        }

        macros[name] = points.isEmpty ? .circle(diameter: fallbackDiameter) : .custom(points: points)
    }

    mutating func parseAperture(_ command: String) {
        var tail = command.dropFirst(3)
        let codeDigits = tail.prefix(while: \.isNumber)
        guard let code = Int(codeDigits) else { return }
        tail = tail.dropFirst(codeDigits.count)
        let definition = String(tail)
        let pieces = definition.split(separator: ",", maxSplits: 1).map(String.init)
        let shapeName = pieces[0]
        let modifiers = pieces.count > 1
            ? pieces[1].split(separator: "X").compactMap { Double($0).map { $0 * format.unitScale } }
            : []

        switch shapeName {
        case "C":
            apertures[code] = .circle(diameter: modifiers.first ?? 0.2)
        case "R":
            apertures[code] = .rectangle(
                width: modifiers.first ?? 0.2,
                height: modifiers.dropFirst().first ?? modifiers.first ?? 0.2
            )
        case "O":
            apertures[code] = .obround(
                width: modifiers.first ?? 0.2,
                height: modifiers.dropFirst().first ?? modifiers.first ?? 0.2
            )
        case "P":
            apertures[code] = .polygon(
                diameter: modifiers.first ?? 0.2,
                vertices: Int(modifiers.dropFirst().first ?? 6),
                rotationDegrees: modifiers.dropFirst(2).first ?? 0
            )
        default:
            apertures[code] = macros[shapeName] ?? .circle(diameter: modifiers.first ?? 0.2)
        }
    }

    mutating func parseStepRepeat(_ command: String) {
        if command == "SR" {
            stepRepeat = StepRepeat()
            return
        }
        let fields = Self.fields(in: String(command.dropFirst(2)))
        stepRepeat.xCount = max(1, fields.firstValue(for: "X").flatMap(Int.init) ?? 1)
        stepRepeat.yCount = max(1, fields.firstValue(for: "Y").flatMap(Int.init) ?? 1)
        stepRepeat.xStep = Double(fields.firstValue(for: "I") ?? "0").map { $0 * format.unitScale } ?? 0
        stepRepeat.yStep = Double(fields.firstValue(for: "J") ?? "0").map { $0 * format.unitScale } ?? 0
    }

    mutating func consumeStandard(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.hasPrefix("G04"), command != "M02", command != "M00" else { return }
        let fields = Self.fields(in: command)

        for gText in fields.values(for: "G") {
            switch Int(gText) {
            case 1: interpolation = .linear
            case 2: interpolation = .clockwise
            case 3: interpolation = .counterclockwise
            case 36:
                regionContours = []
            case 37:
                finishRegion()
            case 90: absoluteCoordinates = true
            case 91: absoluteCoordinates = false
            default: break
            }
        }

        let dCode = fields.values(for: "D").last.flatMap(Int.init)
        if let dCode, dCode >= 10 {
            currentAperture = dCode
            if fields.firstValue(for: "X") == nil, fields.firstValue(for: "Y") == nil { return }
        }

        let hasCoordinate = fields.firstValue(for: "X") != nil || fields.firstValue(for: "Y") != nil
        guard hasCoordinate else { return }

        let decodedX = fields.firstValue(for: "X").flatMap(format.decode)
        let decodedY = fields.firstValue(for: "Y").flatMap(format.decode)
        let target: Point2D
        if absoluteCoordinates {
            target = Point2D(x: decodedX ?? currentPoint.x, y: decodedY ?? currentPoint.y)
        } else {
            target = Point2D(x: currentPoint.x + (decodedX ?? 0), y: currentPoint.y + (decodedY ?? 0))
        }

        let operation = (dCode != nil && dCode! <= 3) ? dCode! : lastOperation
        let iOffset = fields.firstValue(for: "I").flatMap(format.decode) ?? 0
        let jOffset = fields.firstValue(for: "J").flatMap(format.decode) ?? 0

        switch operation {
        case 1:
            draw(to: target, iOffset: iOffset, jOffset: jOffset)
        case 2:
            if regionContours != nil { regionContours?.append([target]) }
        case 3:
            let shape = currentAperture.flatMap { apertures[$0] } ?? .circle(diameter: 0.2)
            append(.flash(center: target, shape: shape, polarity: polarity))
        default:
            break
        }

        currentPoint = target
        if operation <= 3 { lastOperation = operation }
    }

    mutating func draw(to target: Point2D, iOffset: Double, jOffset: Double) {
        let width = currentAperture
            .flatMap { apertures[$0] }
            .map { max($0.dimensions.width, $0.dimensions.height) } ?? 0.2

        if regionContours != nil {
            if regionContours?.isEmpty == true { regionContours?.append([currentPoint]) }
            guard let contourIndex = regionContours?.indices.last else { return }
            if interpolation == .linear {
                regionContours?[contourIndex].append(target)
            } else {
                let center = Point2D(x: currentPoint.x + iOffset, y: currentPoint.y + jOffset)
                let points = Self.flattenArc(
                    start: currentPoint,
                    end: target,
                    center: center,
                    clockwise: interpolation == .clockwise
                )
                regionContours?[contourIndex].append(contentsOf: points)
            }
            return
        }

        switch interpolation {
        case .linear:
            append(.line(start: currentPoint, end: target, width: width, polarity: polarity))
        case .clockwise, .counterclockwise:
            append(.arc(
                start: currentPoint,
                end: target,
                center: Point2D(x: currentPoint.x + iOffset, y: currentPoint.y + jOffset),
                clockwise: interpolation == .clockwise,
                width: width,
                polarity: polarity
            ))
        }
    }

    mutating func finishRegion() {
        guard let contours = regionContours, !contours.isEmpty else {
            regionContours = nil
            return
        }
        append(.region(contours: contours.filter { $0.count >= 3 }, polarity: polarity))
        regionContours = nil
    }

    mutating func append(_ primitive: GerberPrimitive) {
        let (copies, overflow) = stepRepeat.xCount.multipliedReportingOverflow(by: stepRepeat.yCount)
        guard !overflow, copies <= maximumObjects - primitives.count else {
            failure = ImportLimitError(resource: "geometry objects", path: fileName); return
        }
        let points: Int
        switch primitive {
        case .line: points = 2
        case .arc: points = 3
        case let .flash(_, shape, _):
            if case let .custom(vertices) = shape { points = vertices.count } else { points = 1 }
        case let .region(contours, _): points = contours.reduce(0) { $0 + $1.count }
        }
        let (addedPoints, pointOverflow) = copies.multipliedReportingOverflow(by: points)
        guard !pointOverflow, addedPoints <= maximumPoints - pointCount else {
            failure = ImportLimitError(resource: "geometry points", path: fileName); return
        }
        pointCount += addedPoints
        for x in 0..<stepRepeat.xCount {
            for y in 0..<stepRepeat.yCount {
                if Task.isCancelled { failure = CancellationError(); return }
                primitives.append(Self.translate(
                    primitive,
                    by: Point2D(x: Double(x) * stepRepeat.xStep, y: Double(y) * stepRepeat.yStep)
                ))
            }
        }
    }

    static func fields(in command: String) -> [(key: Character, value: String)] {
        let characters = Array(command.uppercased())
        var result: [(Character, String)] = []
        var index = 0
        while index < characters.count {
            let key = characters[index]
            guard key.isLetter else {
                index += 1
                continue
            }
            index += 1
            let start = index
            while index < characters.count, !characters[index].isLetter { index += 1 }
            if index > start {
                result.append((key, String(characters[start..<index])))
            }
        }
        return result
    }

    static func flattenArc(
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
        let segmentCount = max(4, Int(ceil(abs(sweep) * radius / 0.15)))
        return (1...segmentCount).map { step in
            let angle = startAngle + sweep * Double(step) / Double(segmentCount)
            return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    static func translate(_ primitive: GerberPrimitive, by offset: Point2D) -> GerberPrimitive {
        guard offset != .zero else { return primitive }
        switch primitive {
        case let .line(start, end, width, polarity):
            return .line(start: start + offset, end: end + offset, width: width, polarity: polarity)
        case let .arc(start, end, center, clockwise, width, polarity):
            return .arc(
                start: start + offset,
                end: end + offset,
                center: center + offset,
                clockwise: clockwise,
                width: width,
                polarity: polarity
            )
        case let .flash(center, shape, polarity):
            return .flash(center: center + offset, shape: shape, polarity: polarity)
        case let .region(contours, polarity):
            return .region(contours: contours.map { $0.map { $0 + offset } }, polarity: polarity)
        }
    }
}

private extension Array where Element == (key: Character, value: String) {
    func values(for key: Character) -> [String] {
        compactMap { $0.key == key ? $0.value : nil }
    }

    func firstValue(for key: Character) -> String? {
        first { $0.key == key }?.value
    }
}
