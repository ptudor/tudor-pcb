import Foundation

public struct ExcellonParseError: Error, LocalizedError, Sendable {
    public let fileName: String
    public let command: String
    public let reason: String
    public var errorDescription: String? { "\(fileName): \(command): \(reason)" }
}

/// Recognized dialects: explicit-decimal coordinates (including EasyEDA/XNC),
/// CNC-7/KiCad retained-zero LZ/TZ, Altium FILE_FORMAT and KiCad FORMAT comments.
struct ExcellonCoordinateFormat {
    var unitScale: Double?
    var precision: (integer: Int, fractional: Int)?
    var retainLeading: Bool?
    var absolute = true
    let fileName: String

    func error(_ line: String, _ reason: String) -> ExcellonParseError {
        ExcellonParseError(fileName: fileName, command: line, reason: reason)
    }
    mutating func setPrecision(_ integer: Int, _ fractional: Int, line: String) throws {
        guard (1...6).contains(integer), (0...6).contains(fractional) else { throw error(line, "Unsupported coordinate precision.") }
        if let old = precision, old.integer != integer || old.fractional != fractional { throw error(line, "Conflicting coordinate format declarations.") }
        precision = (integer, fractional)
    }
    mutating func declaration(_ line: String) throws -> Bool {
        if line.hasPrefix(";FILE_FORMAT=") {
            let parts = line.dropFirst(13).split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { throw error(line, "Malformed FILE_FORMAT declaration.") }
            try setPrecision(a, b, line: line)
            return true
        }
        if line.hasPrefix("; FORMAT={") || line.hasPrefix(";FORMAT={") {
            guard let begin = line.firstIndex(of: "{"), line.hasSuffix("}") else { throw error(line, "Malformed FORMAT comment.") }
            let fields = line[line.index(after: begin)..<line.index(before: line.endIndex)].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 4 else { throw error(line, "Malformed FORMAT comment.") }
            if fields[0] != "-:-" {
                let digits = fields[0].split(separator: ":")
                guard digits.count == 2, let a = Int(digits[0]), let b = Int(digits[1]) else { throw error(line, "Malformed FORMAT precision.") }
                try setPrecision(a, b, line: line)
            }
            guard ["ABSOLUTE", "INCREMENTAL"].contains(fields[1]), ["METRIC", "INCH"].contains(fields[2]) else { throw error(line, "Unsupported FORMAT mode/units.") }
            absolute = fields[1] == "ABSOLUTE"
            unitScale = fields[2] == "METRIC" ? 1 : 25.4
            switch fields[3] {
            case "SUPPRESS LEADING ZEROS": retainLeading = false
            case "SUPPRESS TRAILING ZEROS": retainLeading = true
            case "KEEP ZEROS", "DECIMAL": retainLeading = nil
            default: throw error(line, "Unsupported FORMAT zero convention.")
            }
            return true
        }
        if line.hasPrefix("METRIC") || line.hasPrefix("INCH") || line == "M71" || line == "M72" {
            unitScale = line.hasPrefix("METRIC") || line == "M71" ? 1 : 25.4
            for field in line.split(separator: ",").dropFirst() {
                switch field {
                case "LZ", "TZ":
                    let leading = field == "LZ"
                    if let old = retainLeading, old != leading { throw error(line, "Conflicting zero conventions.") }
                    retainLeading = leading
                default:
                    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
                    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 == "0" } }) else { throw error(line, "Unsupported units/format declaration.") }
                    try setPrecision(parts[0].count, parts[1].count, line: line)
                }
            }
            return true
        }
        if line == "G90" || line == "G91" || line == "ICI,ON" || line == "ICI,OFF" {
            absolute = line == "G90" || line == "ICI,OFF"
            return true
        }
        if line.hasPrefix("ICI") { throw error(line, "Malformed incremental mode declaration.") }
        return false
    }
    func decode(_ text: String, line: String) throws -> Double {
        guard let scale = unitScale else { throw error(line, "Declare drill units before coordinates/tools.") }
        guard text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil else { throw error(line, "Malformed coordinate.") }
        var value: Double
        if text.contains(".") {
            value = Double(text) ?? .nan
        } else {
            guard let precision else { throw error(line, "Ambiguous integer coordinates: declare precision using FILE_FORMAT or a units format, or export explicit decimals.") }
            var digits = text
            let negative = digits.hasPrefix("-")
            if negative || digits.hasPrefix("+") { digits.removeFirst() }
            let total = precision.integer + precision.fractional
            guard digits.count <= total else { throw error(line, "Coordinate exceeds declared precision.") }
            if digits.count < total {
                guard let retainLeading else { throw error(line, "Ambiguous zero convention: declare retained LZ/TZ or export explicit decimals.") }
                if retainLeading { digits += String(repeating: "0", count: total - digits.count) }
            }
            value = (Double(digits) ?? .nan) / pow(10, Double(precision.fractional))
            if negative { value = -value }
        }
        value *= scale
        guard value.isFinite, abs(value) <= GeometryLimits.coordinateMagnitude else { throw error(line, "Nonfinite or out-of-range coordinate.") }
        return value
    }
}
