import Foundation

public struct ExcellonParser: Sendable {
    public init() { }

    public func parse(data: Data, fileName: String) throws -> [DrillHit] {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw GerberParseError.textEncoding
        }

        let kind = LayerClassifier.classify(fileName: fileName, contents: source)
        let plated: Bool?
        if case let .drill(value) = kind { plated = value } else { plated = nil }

        var unitScale = 1.0
        var decimalDigits = 3
        var leadingZerosOmitted = true
        var tools: [Int: Double] = [:]
        var selectedTool: Int?
        var current = Point2D.zero
        var result: [DrillHit] = []

        for sourceLine in source.split(whereSeparator: \.isNewline) {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !line.isEmpty, !line.hasPrefix(";") else { continue }

            if line.hasPrefix("METRIC") || line == "M71" {
                unitScale = 1
                leadingZerosOmitted = line.contains("LZ") || !line.contains("TZ")
                if let pattern = line.split(separator: ",").last, pattern.contains(".") {
                    decimalDigits = pattern.split(separator: ".").last?.count ?? decimalDigits
                }
                continue
            }
            if line.hasPrefix("INCH") || line == "M72" {
                unitScale = 25.4
                leadingZerosOmitted = line.contains("LZ") || !line.contains("TZ")
                if let pattern = line.split(separator: ",").last, pattern.contains(".") {
                    decimalDigits = pattern.split(separator: ".").last?.count ?? 4
                } else {
                    decimalDigits = 4
                }
                continue
            }

            if line.hasPrefix("T"), let cIndex = line.firstIndex(of: "C") {
                let toolText = line[line.index(after: line.startIndex)..<cIndex]
                let diameterText = line[line.index(after: cIndex)...]
                    .prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
                if let tool = Int(toolText), let diameter = Double(diameterText) {
                    tools[tool] = diameter * unitScale
                }
                continue
            }

            if line.hasPrefix("T"), let tool = Int(line.dropFirst()), !line.contains("X"), !line.contains("Y") {
                selectedTool = tool
                continue
            }

            let fields = coordinateFields(in: line)
            guard fields["X"] != nil || fields["Y"] != nil else { continue }
            let x = fields["X"].flatMap {
                decode($0, decimalDigits: decimalDigits, leadingZerosOmitted: leadingZerosOmitted)
            }.map { $0 * unitScale } ?? current.x
            let y = fields["Y"].flatMap {
                decode($0, decimalDigits: decimalDigits, leadingZerosOmitted: leadingZerosOmitted)
            }.map { $0 * unitScale } ?? current.y
            current = Point2D(x: x, y: y)
            let diameter = selectedTool.flatMap { tools[$0] } ?? 0.3
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

    private func decode(_ text: String, decimalDigits: Int, leadingZerosOmitted: Bool) -> Double? {
        if text.contains(".") { return Double(text) }
        var value = text
        let negative = value.hasPrefix("-")
        if negative || value.hasPrefix("+") { value.removeFirst() }
        if !leadingZerosOmitted {
            let totalDigits = decimalDigits + 3
            value += String(repeating: "0", count: max(0, totalDigits - value.count))
        }
        guard let integer = Double(value) else { return nil }
        return (negative ? -integer : integer) / pow(10, Double(decimalDigits))
    }
}

