import Foundation

public enum GerberParseError: Error, LocalizedError, Sendable {
    case textEncoding
    case missingGeometry(String)
    case invalidDefinition(fileName: String, command: String, reason: String)
    case invalidCommand(fileName: String, command: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .textEncoding:
            "The layer is not an ASCII or UTF-8 Gerber file."
        case let .invalidDefinition(fileName, command, reason), let .invalidCommand(fileName, command, reason):
            "\(fileName): \(command): \(reason)"
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
    var macros: [String: ApertureMacro] = [:]
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
    var pendingRegionPoints = 0
    var terminated = false
    var repeatOpen = false
    var singleQuadrant = false
    var hasFormat = false
    var hasUnits = false
    var commandContext = ""

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
                    if !pending.isEmpty { invalidCommand(pending, "Missing command delimiter before extended block."); return }
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

        guard failure == nil else { return }
        let trailing = cleaned(buffer)
        guard !isExtended, trailing.isEmpty else { invalidCommand(trailing, "Unterminated command or extended block."); return }
        guard regionContours == nil, !repeatOpen else { invalidCommand("EOF", "Unterminated region or repeat block."); return }
        guard terminated else { invalidCommand("EOF", "Missing M02 end-of-file command."); return }
    }

    mutating func invalidCommand(_ command: String, _ reason: String) {
        failure = GerberParseError.invalidCommand(fileName: fileName, command: command, reason: reason)
    }

    mutating func consumeExtended(_ block: String) {
        guard !terminated else { invalidCommand(block, "Data after end-of-file."); return }
        guard block.hasSuffix("*") else { invalidCommand(block, "Missing extended-command delimiter."); return }
        let commands = block.split(separator: "*", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = commands.first else { invalidCommand(block, "Empty extended block."); return }
        if first.hasPrefix("AM") { parseMacro(commands); return }
        for command in commands {
            if failure != nil { return }
            commandContext = command
            if command.hasPrefix("FS") { parseFormat(command) }
            else if command == "MOMM" { format.unitScale = 1; hasUnits = true }
            else if command == "MOIN" { format.unitScale = 25.4; hasUnits = true }
            else if command.hasPrefix("ADD") { parseAperture(command) }
            else if command == "LPD" { polarity = .dark }
            else if command == "LPC" { polarity = .clear }
            else if command.hasPrefix("SR") { parseStepRepeat(command) }
            else if ["TF", "TA", "TO", "TD", "IN", "LN"].contains(where: command.hasPrefix) { continue }
            else if ["LMN", "IPPOS", "ASAXBY", "MIA0B0", "OFA0B0", "SFA1B1", "IR0"].contains(command) { continue }
            else if command.hasPrefix("LR"), Self.decimal(String(command.dropFirst(2))) == 0 { continue }
            else if command.hasPrefix("LS"), Self.decimal(String(command.dropFirst(2))) == 1 { continue }
            else { invalidCommand(command, "Unsupported or malformed geometry command; layer rejected.") }
        }
    }

    mutating func parseFormat(_ command: String) {
        guard command.range(of: #"^FS[LT][AI]X[0-6][0-6]Y[0-6][0-6]$"#, options: .regularExpression) != nil else {
            invalidCommand(command, "Unsupported or malformed coordinate format."); return
        }
        let chars = Array(command)
        guard chars[5] == chars[8], chars[6] == chars[9], chars[5] != "0" || chars[6] != "0" else {
            invalidCommand(command, "X/Y precision must match and contain digits."); return
        }
        format.leadingZerosOmitted = chars[2] == "L"
        absoluteCoordinates = chars[3] == "A"
        format.integerDigits = Int(String(chars[5]))!
        format.decimalDigits = Int(String(chars[6]))!
        hasFormat = true
    }

    mutating func invalidDefinition(_ command: String, _ reason: String) {
        failure = GerberParseError.invalidDefinition(fileName: fileName, command: command, reason: reason)
    }

    // Gerber decimals do not have exponent, infinity, or NaN spellings.
    static func decimal(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Double(text), value.isFinite else { return nil }
        return value
    }

    mutating func parseMacro(_ commands: [String]) {
        guard let first = commands.first else { return }
        let name = String(first.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, macros[name] == nil, commands.count > 1, commands.count <= 10_000 else { invalidDefinition(first, "Empty or oversized macro definition."); return }
        // A literal illegal count is invalid even if the macro is never used.
        // Parameter expressions and geometry are evaluated only at ADD.
        for statement in commands.dropFirst() {
            let fields = statement.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if fields.first == "4", fields.count >= 3, let count = Self.decimal(fields[2]) {
                guard count.rounded() == count, (3.0...5000.0).contains(count) else { invalidDefinition(statement, "Invalid literal macro vertex count."); return }
            }
        }
        macros[name] = ApertureMacro(statements: Array(commands.dropFirst()))
    }

    mutating func parseAperture(_ command: String) {
        var tail = command.dropFirst(3)
        let codeDigits = tail.prefix(while: \.isNumber)
        guard let code = Int(codeDigits), code >= 10, code <= Int(Int32.max) else {
            invalidDefinition(command, "Invalid aperture number."); return
        }
        tail = tail.dropFirst(codeDigits.count)
        let pieces = tail.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first, !first.isEmpty else { invalidDefinition(command, "Missing aperture template."); return }
        let shapeName = String(first)
        let texts = pieces.count > 1 ? pieces[1].split(separator: "X", omittingEmptySubsequences: false).map(String.init) : []
        let raw = texts.compactMap(Self.decimal)
        guard raw.count == texts.count, raw.allSatisfy({ ($0 * format.unitScale).isFinite }) else {
            invalidDefinition(command, "Malformed, nonfinite, or out-of-range modifier."); return
        }
        func dimension(_ index: Int) -> Double { raw[index] * format.unitScale }
        func withHole(_ shape: ApertureShape, at index: Int) -> ApertureShape {
            guard raw.count > index, raw[index] > 0 else { return shape }
            return .compound(primitives: [
                .flash(center: .zero, shape: shape, polarity: .dark),
                .flash(center: .zero, shape: .circle(diameter: dimension(index)), polarity: .clear)
            ])
        }
        switch shapeName {
        case "C":
            guard (1...2).contains(raw.count), raw.allSatisfy({ $0 >= 0 }) else {
                invalidDefinition(command, "Circle requires a nonnegative diameter and optional round hole; legacy rectangular holes are unsupported."); return
            }
            apertures[code] = withHole(.circle(diameter: dimension(0)), at: 1)
        case "R", "O":
            guard (2...3).contains(raw.count), raw.allSatisfy({ $0 >= 0 }), raw[0] > 0, raw[1] > 0 else {
                invalidDefinition(command, "Rectangle/obround requires positive width and height and optional round hole; legacy rectangular holes are unsupported."); return
            }
            apertures[code] = withHole(shapeName == "R"
                ? .rectangle(width: dimension(0), height: dimension(1))
                : .obround(width: dimension(0), height: dimension(1)), at: 2)
        case "P":
            guard (2...4).contains(raw.count), raw[0] > 0,
                  let vertices = Int(texts[1]), (3...12).contains(vertices),
                  raw.dropFirst(3).allSatisfy({ $0 >= 0 }) else {
                invalidDefinition(command, "Polygon requires a positive diameter, 3...12 integer vertices, finite rotation and optional round hole; legacy rectangular holes are unsupported."); return
            }
            apertures[code] = withHole(.polygon(diameter: dimension(0), vertices: vertices, rotationDegrees: raw.count > 2 ? raw[2] : 0), at: 3)
        default:
            guard let macro = macros[shapeName] else { invalidDefinition(command, "Undefined aperture macro \(shapeName)."); return }
            do {
                let shape = try macro.instantiate(parameters: raw, scale: format.unitScale, fileName: fileName, command: command)
                let cost = try GeometryLimits.shape(shape, context: command)
                guard cost <= maximumPoints - pointCount else { failure = GeometryLimitError(resource: "macro geometry points", context: command); return }
                pointCount += cost
                apertures[code] = shape
            } catch let error as GeometryLimitError { failure = error }
              catch let error as GerberParseError { failure = error }
              catch { invalidDefinition(command, error.localizedDescription) }
        }
    }

    mutating func parseStepRepeat(_ command: String) {
        if command == "SR" {
            guard repeatOpen else { invalidCommand(command, "Repeat close without an open block."); return }
            stepRepeat = StepRepeat(); repeatOpen = false; return
        }
        guard !repeatOpen else { invalidCommand(command, "Nested step-repeat is not supported; layer rejected."); return }
        let fields = Self.fields(in: String(command.dropFirst(2)))
        guard let x = Int(fields.firstValue(for: "X") ?? "1"),
              let y = Int(fields.firstValue(for: "Y") ?? "1"), x > 0, y > 0,
              x <= GeometryLimits.repeats, y <= GeometryLimits.repeats,
              x <= GeometryLimits.repeats / y,
              let i = Self.decimal(fields.firstValue(for: "I") ?? "0"),
              let j = Self.decimal(fields.firstValue(for: "J") ?? "0") else {
            failure = GeometryLimitError(resource: "step-repeat count/spacing", context: fileName + ": " + command); return
        }
        let offset = Point2D(x: Double(x - 1) * i * format.unitScale, y: Double(y - 1) * j * format.unitScale)
        do { try GeometryLimits.point(offset, context: command) }
        catch { failure = error; return }
        repeatOpen = true
        stepRepeat = StepRepeat(xCount: x, yCount: y, xStep: i * format.unitScale, yStep: j * format.unitScale)
    }

    mutating func consumeStandard(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        commandContext = command
        guard !terminated else { invalidCommand(command, "Data after end-of-file."); return }
        if command.hasPrefix("G04") || command.hasPrefix("G4 ") { return }
        if command == "M02" || command == "M00" {
            guard regionContours == nil, !repeatOpen else { invalidCommand(command, "Unterminated region or repeat block."); return }
            terminated = true; return
        }
        if command == "M01" { return } // Supported deprecated no-op.
        guard command.range(of: #"^(?:[GD][0-9]+|[XYIJ][+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))+$"#, options: .regularExpression) != nil else {
            invalidCommand(command, "Malformed coordinate or unsupported standard command."); return
        }
        let fields = Self.fields(in: command)
        for key: Character in ["X", "Y", "I", "J", "D"] {
            guard fields.values(for: key).count <= 1 else { invalidCommand(command, "Repeated field \(key)."); return }
        }
        for field in fields where field.key == "G" || field.key == "D" {
            guard Int(field.value) != nil else { invalidCommand(command, "Out-of-range command number."); return }
        }

        for gText in fields.values(for: "G") {
            switch Int(gText) {
            case 1: interpolation = .linear
            case 2: interpolation = .clockwise
            case 3: interpolation = .counterclockwise
            case 36:
                guard regionContours == nil else { invalidCommand(command, "Nested region."); return }
                regionContours = []
                pendingRegionPoints = 0
            case 37:
                guard regionContours != nil else { invalidCommand(command, "Region end without start."); return }
                finishRegion()
            case 54, 55: break
            case 70: format.unitScale = 25.4; hasUnits = true
            case 71: format.unitScale = 1; hasUnits = true
            case 74: singleQuadrant = true
            case 75: singleQuadrant = false
            case 90: absoluteCoordinates = true
            case 91: absoluteCoordinates = false
            default: invalidCommand(command, "Unsupported G command."); return
            }
        }
        guard failure == nil else { return }

        let dCode = fields.values(for: "D").last.flatMap(Int.init)
        if let dCode, !(1...3).contains(dCode), dCode < 10 { invalidCommand(command, "Invalid D operation."); return }
        if let dCode, dCode >= 10 {
            guard apertures[dCode] != nil else { invalidCommand(command, "Undefined aperture D\(dCode)."); return }
            currentAperture = dCode
            if fields.firstValue(for: "X") == nil, fields.firstValue(for: "Y") == nil { return }
        }

        let hasCoordinate = fields.firstValue(for: "X") != nil || fields.firstValue(for: "Y") != nil
        guard hasCoordinate else { return }
        guard hasFormat, hasUnits else { invalidCommand(command, "Declare coordinate format and units before operations."); return }
        for field in fields where [Character("X"), "Y", "I", "J"].contains(field.key) {
            guard format.decode(field.value) != nil else { invalidCommand(command, "Malformed coordinate."); return }
        }

        let decodedX = fields.firstValue(for: "X").flatMap(format.decode)
        let decodedY = fields.firstValue(for: "Y").flatMap(format.decode)
        let target: Point2D
        if absoluteCoordinates {
            target = Point2D(x: decodedX ?? currentPoint.x, y: decodedY ?? currentPoint.y)
        } else {
            target = Point2D(x: currentPoint.x + (decodedX ?? 0), y: currentPoint.y + (decodedY ?? 0))
        }

        do { try GeometryLimits.point(target, context: fileName + ": " + command) }
        catch { failure = error; return }

        let operation = (dCode != nil && dCode! <= 3) ? dCode! : lastOperation
        let iOffset = fields.firstValue(for: "I").flatMap(format.decode) ?? 0
        let jOffset = fields.firstValue(for: "J").flatMap(format.decode) ?? 0

        switch operation {
        case 1:
            draw(to: target, iOffset: iOffset, jOffset: jOffset)
        case 2:
            if regionContours != nil {
                guard reserveRegionPoints(1) else { return }
                regionContours?.append([target])
            }
        case 3:
            guard regionContours == nil else { invalidCommand(command, "Flash inside region."); return }
            guard let shape = currentAperture.flatMap({ apertures[$0] }) else { invalidCommand(command, "Flash without a selected aperture."); return }
            append(.flash(center: target, shape: shape, polarity: polarity))
        default:
            break
        }

        currentPoint = target
        if operation <= 3 { lastOperation = operation }
    }

    mutating func draw(to target: Point2D, iOffset: Double, jOffset: Double) {
        if interpolation != .linear, singleQuadrant { invalidCommand(commandContext, "Unsupported G74 arc; layer rejected."); return }
        let shape = currentAperture.flatMap { apertures[$0] }
        if regionContours == nil, shape == nil { invalidCommand(commandContext, "Draw without a selected aperture."); return }
        let width = shape.map { max($0.dimensions.width, $0.dimensions.height) } ?? 0

        if regionContours != nil {
            if regionContours?.isEmpty == true {
                guard reserveRegionPoints(1) else { return }
                regionContours?.append([currentPoint])
            }
            guard let contourIndex = regionContours?.indices.last else { return }
            if interpolation == .linear {
                guard reserveRegionPoints(1) else { return }
                regionContours?[contourIndex].append(target)
            } else {
                let center = Point2D(x: currentPoint.x + iOffset, y: currentPoint.y + jOffset)
                let points: [Point2D]
                do { points = try GeometryLimits.flattenArc(
                    start: currentPoint,
                    end: target,
                    center: center,
                    clockwise: interpolation == .clockwise,
                    spacing: 0.15, minimum: 4, context: fileName
                ) } catch { failure = error; return }
                guard reserveRegionPoints(points.count) else { return }
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

    mutating func reserveRegionPoints(_ count: Int) -> Bool {
        guard count <= maximumPoints - pointCount - pendingRegionPoints else {
            failure = GeometryLimitError(resource: "contour points", context: fileName); return false
        }
        pendingRegionPoints += count
        return true
    }

    mutating func finishRegion() {
        guard let contours = regionContours, !contours.isEmpty, contours.allSatisfy({ $0.count >= 3 }) else {
            invalidCommand(commandContext, "Region has an empty or incomplete contour."); return
        }
        append(.region(contours: contours, polarity: polarity))
        regionContours = nil
    }

    mutating func append(_ primitive: GerberPrimitive) {
        let (copies, overflow) = stepRepeat.xCount.multipliedReportingOverflow(by: stepRepeat.yCount)
        guard !overflow, copies <= maximumObjects - primitives.count else {
            failure = ImportLimitError(resource: "geometry objects", path: fileName); return
        }
        let points: Int
        do { points = try GeometryLimits.cost(primitive, context: fileName) }
        catch { failure = error; return }
        let (addedPoints, pointOverflow) = copies.multipliedReportingOverflow(by: points)
        guard !pointOverflow, addedPoints <= maximumPoints - pointCount else {
            failure = ImportLimitError(resource: "geometry points", path: fileName); return
        }
        pointCount += addedPoints
        for x in 0..<stepRepeat.xCount {
            for y in 0..<stepRepeat.yCount {
                if Task.isCancelled { failure = CancellationError(); return }
                let translated = Self.translate(
                    primitive,
                    by: Point2D(x: Double(x) * stepRepeat.xStep, y: Double(y) * stepRepeat.yStep)
                )
                do { _ = try GeometryLimits.cost(translated, context: fileName) }
                catch { failure = error; return }
                primitives.append(translated)
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
