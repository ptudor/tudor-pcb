import Foundation

public enum FabricationSyntax: Sendable { case gerber, excellon, unknown }

public enum LayerClassifier {
    public static func classify(fileName: String, contents: String? = nil) -> GerberLayerKind {
        classification(fileName: fileName, contents: contents).kind
    }

    /// Precedence: structured FileFunction, recognized JLCCam basename, strong
    /// extension, then basename keywords. Parent directories never assign roles.
    public static func classification(fileName: String, contents: String? = nil) -> (kind: GerberLayerKind, warnings: [String]) {
        let source = contents ?? ""
        let inferred = filenameKind(fileName, contents: source)
        let functions = fileFunctions(in: source)
        guard let first = functions.first else {
            if syntax(contents: source) == .excellon {
                if case .drill = inferred { return (inferred, []) }
                let warning = inferred == .other ? [] : [DiagnosticStrings.excellonSyntaxConflictsRole(fileName, role: inferred.displayName)]
                return (.drill(plated: nil), warning)
            }
            return (inferred, [])
        }
        guard functions.allSatisfy({ $0 == first }) else {
            return (.other, [DiagnosticStrings.conflictingFileFunctions(fileName)])
        }
        guard let explicit = attributeKind(first) else {
            return (.other, [DiagnosticStrings.unsupportedFileFunction(fileName, attribute: first.joined(separator: ","))])
        }
        var warnings: [String] = []
        if inferred != .other && !compatible(inferred, explicit) {
            warnings.append(DiagnosticStrings.fileFunctionOverridesRole(fileName, role: inferred.displayName))
        }
        return (explicit, warnings)
    }

    static func fileFunctions(in source: String) -> [[String]] {
        // Attributes belong to extended commands, never unrelated comment text.
        let gerber = source.components(separatedBy: "%").enumerated().filter { $0.offset % 2 == 1 }.flatMap { _, block in
            block.components(separatedBy: "*").compactMap { command -> [String]? in
                let text = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard text.hasPrefix("tf.filefunction,") else { return nil }
                return text.dropFirst(16).split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        let drillComments = source.split(whereSeparator: \.isNewline).compactMap { line -> [String]? in
            let text = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard text.hasPrefix(";"), let marker = text.range(of: #"^;\s*#[@!]*\s*tf\.filefunction,"#, options: .regularExpression) else { return nil }
            return text[marker.upperBound...].split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return gerber + drillComments
    }

    private static func attributeKind(_ fields: [String]) -> GerberLayerKind? {
        guard let role = fields.first else { return nil }
        func side(_ index: Int) -> GerberSide? {
            guard fields.count > index else { return nil }
            switch fields[index] { case "top": return .top; case "bot", "bottom": return .bottom; case "inr": return GerberSide.none; default: return nil }
        }
        switch role {
        case "copper":
            guard fields.count >= 3, fields[1].hasPrefix("l"), let index = Int(fields[1].dropFirst()), index > 0, let face = side(2) else { return nil }
            return .copper(side: face, index: face == .none ? index : nil)
        case "profile": return .outline
        case "plated", "nonplated":
            guard fields.count >= 4 else { return nil }
            return .drill(plated: role == "plated")
        case "drillmap": return .documentation
        case "legend": return side(1).map { .silkscreen(side: $0) }
        case "soldermask": return side(1).map { .solderMask(side: $0) }
        case "paste": return side(1).map { .paste(side: $0) }
        case "assemblydrawing", "fabricationdrawing", "otherdrawing": return .documentation
        default: return nil
        }
    }

    private static func compatible(_ a: GerberLayerKind, _ b: GerberLayerKind) -> Bool {
        if case let .drill(pa) = a, case let .drill(pb) = b { return pa == nil || pb == nil || pa == pb }
        if case let .copper(sa, ia) = a, case let .copper(sb, ib) = b { return sa == sb && (ia == nil || ib == nil || ia == ib) }
        return a == b
    }

    private static func filenameKind(_ fileName: String, contents: String) -> GerberLayerKind {
        let name = URL(fileURLWithPath: fileName).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: name).pathExtension
        if contents.localizedCaseInsensitiveContains("output software:jlccam"), let kind = jlccamKind(for: name) { return kind }
        func plating() -> Bool? {
            if name.contains("npth") || contents.localizedCaseInsensitiveContains("TYPE=NON_PLATED") { return false }
            if name.contains("pth") || contents.localizedCaseInsensitiveContains("TYPE=PLATED") { return true }
            return nil
        }
        switch ext {
        case "fcts": return .colorfulSilkscreen(side: .top)
        case "fcbs": return .colorfulSilkscreen(side: .bottom)
        case "fcbo": return .other
        case "fcbm", "gdd", "gdl", "gbrjob": return .documentation
        case "drl", "xln": return .drill(plated: plating())
        case "gko", "gm1", "gml", "oln": return .outline
        case "gtl", "top": return .copper(side: .top, index: nil)
        case "gbl", "bot": return .copper(side: .bottom, index: nil)
        case "gto", "sst": return .silkscreen(side: .top)
        case "gbo", "ssb": return .silkscreen(side: .bottom)
        case "gts", "smt": return .solderMask(side: .top)
        case "gbs", "smb": return .solderMask(side: .bottom)
        case "gtp": return .paste(side: .top)
        case "gbp": return .paste(side: .bottom)
        default: break
        }
        if ext.range(of: #"^g\d+$"#, options: .regularExpression) != nil { return .copper(side: .none, index: Int(ext.dropFirst())) }
        if name.contains("document") || name.contains("drawing") { return .documentation }
        if name.contains("drill") { return .drill(plated: plating()) }
        if ["outline", "edge.cuts", "edge_cuts"].contains(where: name.contains) { return .outline }
        if ["toplayer", "top_copper", "f_cu"].contains(where: name.contains) { return .copper(side: .top, index: nil) }
        if ["bottomlayer", "bottom_copper", "b_cu"].contains(where: name.contains) { return .copper(side: .bottom, index: nil) }
        if ["topsilk", "f.silkscreen", "f_silk"].contains(where: name.contains) { return .silkscreen(side: .top) }
        if ["bottomsilk", "b.silkscreen", "b_silk"].contains(where: name.contains) { return .silkscreen(side: .bottom) }
        if ["topsoldermask", "f.mask", "f_mask"].contains(where: name.contains) { return .solderMask(side: .top) }
        if ["bottomsoldermask", "b.mask", "b_mask"].contains(where: name.contains) { return .solderMask(side: .bottom) }
        if ["toppaste", "f.paste", "f_paste"].contains(where: name.contains) { return .paste(side: .top) }
        if ["bottompaste", "b.paste", "b_paste"].contains(where: name.contains) { return .paste(side: .bottom) }
        return .other
    }

    public static func syntax(contents: String) -> FabricationSyntax {
        let source = contents.uppercased()
        if source.range(of: #"%(?:FS|MO|ADD|AM)"#, options: .regularExpression) != nil { return .gerber }
        if source.split(whereSeparator: \.isNewline).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "M48" }) { return .excellon }
        return .unknown
    }

    public static func isGerber(_ fileName: String, contents: String? = nil) -> Bool {
        switch syntax(contents: contents ?? "") {
        case .gerber: return true
        case .excellon: return false
        case .unknown: break
        }
        switch classify(fileName: fileName, contents: contents) {
        case .drill, .colorfulSilkscreen, .other:
            return ["gbr", "ger", "pho", "art"].contains(URL(fileURLWithPath: fileName).pathExtension.lowercased())
        default: return true
        }
    }

    private static func jlccamKind(for base: String) -> GerberLayerKind? {
        switch base {
        case "tl": return .copper(side: .top, index: nil)
        case "bl": return .copper(side: .bottom, index: nil)
        case "to", "qrt": return .silkscreen(side: .top)
        case "bo", "qrb": return .silkscreen(side: .bottom)
        case "ts": return .solderMask(side: .top)
        case "bs": return .solderMask(side: .bottom)
        case "ko": return .outline
        case "drl", "vcut", "sk", "color_mark": return .documentation
        default:
            guard base.first == "l", let index = Int(base.dropFirst()), index > 1 else { return nil }
            return .copper(side: .none, index: index)
        }
    }
}
