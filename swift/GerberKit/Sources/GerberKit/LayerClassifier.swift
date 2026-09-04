import Foundation

public enum LayerClassifier {
    public static func classify(fileName: String, contents: String? = nil) -> GerberLayerKind {
        let name = fileName.lowercased()
        let ext = URL(fileURLWithPath: name).pathExtension

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
        if ["gko", "gm1", "gml"].contains(ext) || name.contains("outline") || name.contains("edge.cuts") {
            return .outline
        }
        if ext == "gtl" || name.contains("toplayer") || name.contains("top_copper") {
            return .copper(side: .top, index: nil)
        }
        if ext == "gbl" || name.contains("bottomlayer") || name.contains("bottom_copper") {
            return .copper(side: .bottom, index: nil)
        }
        if ext.range(of: #"^g\d+$"#, options: .regularExpression) != nil {
            return .copper(side: .none, index: Int(ext.dropFirst()))
        }
        if ext == "gto" || name.contains("topsilk") || name.contains("f.silkscreen") {
            return .silkscreen(side: .top)
        }
        if ext == "gbo" || name.contains("bottomsilk") || name.contains("b.silkscreen") {
            return .silkscreen(side: .bottom)
        }
        if ext == "gts" || name.contains("topsoldermask") || name.contains("f.mask") {
            return .solderMask(side: .top)
        }
        if ext == "gbs" || name.contains("bottomsoldermask") || name.contains("b.mask") {
            return .solderMask(side: .bottom)
        }
        if ext == "gtp" || name.contains("toppaste") || name.contains("f.paste") {
            return .paste(side: .top)
        }
        if ext == "gbp" || name.contains("bottompaste") || name.contains("b.paste") {
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
}
