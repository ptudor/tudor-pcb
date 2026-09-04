import Foundation

public enum LayerClassifier {
    public static func classify(fileName: String, contents: String? = nil) -> GerberLayerKind {
        let name = fileName.lowercased()
        let ext = URL(fileURLWithPath: name).pathExtension
        let source = contents?.lowercased() ?? ""

        if ext == "fcts" { return .colorfulSilkscreen(side: .top) }
        if ext == "fcbs" { return .colorfulSilkscreen(side: .bottom) }
        if ext == "fcbo" { return .other }
        if ext == "fcbm" { return .documentation }
        if ["gdd", "gdl", "gbrjob"].contains(ext) || name.contains("document") || name.contains("drawing") {
            return .documentation
        }
        if ext == "drl" || ext == "xln" || name.contains("drill") {
            if name.contains("npth") || contents?.localizedCaseInsensitiveContains("TYPE=NON_PLATED") == true {
                return .drill(plated: false)
            }
            if name.contains("pth") || contents?.localizedCaseInsensitiveContains("TYPE=PLATED") == true {
                return .drill(plated: true)
            }
            return .drill(plated: nil)
        }
        if ["gko", "gm1", "gml", "oln"].contains(ext)
            || name.contains("outline") || name.contains("edge.cuts") || name.contains("edge_cuts")
            || source.contains("filefunction,profile") {
            return .outline
        }
        if ["gtl", "top"].contains(ext) || name.contains("toplayer") || name.contains("top_copper")
            || name.contains("f_cu")
            || (source.contains("filefunction,copper") && source.contains(",top")) {
            return .copper(side: .top, index: nil)
        }
        if ["gbl", "bot"].contains(ext) || name.contains("bottomlayer") || name.contains("bottom_copper")
            || name.contains("b_cu")
            || (source.contains("filefunction,copper") && (source.contains(",bot") || source.contains(",bottom"))) {
            return .copper(side: .bottom, index: nil)
        }
        if ext.range(of: #"^g\d+$"#, options: .regularExpression) != nil {
            return .copper(side: .none, index: Int(ext.dropFirst()))
        }
        if let index = x2CopperIndex(source) {
            return .copper(side: .none, index: index)
        }
        if ["gto", "sst"].contains(ext) || name.contains("topsilk") || name.contains("f.silkscreen")
            || name.contains("f_silk") || source.contains("filefunction,legend,top") {
            return .silkscreen(side: .top)
        }
        if ["gbo", "ssb"].contains(ext) || name.contains("bottomsilk") || name.contains("b.silkscreen")
            || name.contains("b_silk") || source.contains("filefunction,legend,bot") {
            return .silkscreen(side: .bottom)
        }
        if ["gts", "smt"].contains(ext) || name.contains("topsoldermask") || name.contains("f.mask")
            || name.contains("f_mask") || source.contains("filefunction,soldermask,top") {
            return .solderMask(side: .top)
        }
        if ["gbs", "smb"].contains(ext) || name.contains("bottomsoldermask") || name.contains("b.mask")
            || name.contains("b_mask") || source.contains("filefunction,soldermask,bot") {
            return .solderMask(side: .bottom)
        }
        if ext == "gtp" || name.contains("toppaste") || name.contains("f.paste")
            || name.contains("f_paste") || source.contains("filefunction,paste,top") {
            return .paste(side: .top)
        }
        if ext == "gbp" || name.contains("bottompaste") || name.contains("b.paste")
            || name.contains("b_paste") || source.contains("filefunction,paste,bot") {
            return .paste(side: .bottom)
        }
        return .other
    }

    public static func isGerber(_ fileName: String) -> Bool {
        let kind = classify(fileName: fileName)
        switch kind {
        case .drill, .colorfulSilkscreen, .other:
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            return ["gbr", "ger", "pho", "art"].contains(ext)
        default:
            return true
        }
    }

    private static func x2CopperIndex(_ source: String) -> Int? {
        guard let marker = source.range(of: "filefunction,copper,l") else { return nil }
        let suffix = source[marker.upperBound...]
        let digits = suffix.prefix(while: \.isNumber)
        return Int(digits)
    }
}
