import Testing
@testable import GerberKit

@Test func classifiesX2AndKiCadLayers() {
    #expect(LayerClassifier.classify(
        fileName: "anonymous.gbr",
        contents: "%TF.FileFunction,Copper,L1,Top*%"
    ) == .copper(side: .top, index: nil))
    #expect(LayerClassifier.classify(
        fileName: "anonymous.gbr",
        contents: "%TF.FileFunction,Copper,L4,Bot*%"
    ) == .copper(side: .bottom, index: nil))
    #expect(LayerClassifier.classify(
        fileName: "anonymous.gbr",
        contents: "%TF.FileFunction,Copper,L2,Inr*%"
    ) == .copper(side: .none, index: 2))
    #expect(LayerClassifier.classify(fileName: "radio-F_Silkscreen.gbr") == .silkscreen(side: .top))
    #expect(LayerClassifier.classify(fileName: "radio-Edge_Cuts.gbr") == .outline)
    #expect(LayerClassifier.classify(fileName: "panel.SMB") == .solderMask(side: .bottom))
}

@Test func keepsEasyEDAAuxiliaryColorFilesOutOfTheOutline() {
    #expect(LayerClassifier.classify(fileName: "Fabrication_ColorfulBoardOutlineLayer.FCBO") == .other)
    #expect(LayerClassifier.classify(fileName: "Fabrication_ColorfulBoardOutlineMark.FCBM") == .documentation)
}

@Test func classifiesExtensionlessJLCCamProductionLayers() {
    let header = "G04 -- output software:jlccam pro v3.4.8 *\n%FSLAX26Y26*%\n%MOIN*%"
    #expect(LayerClassifier.classify(fileName: "ok/tl", contents: header) == .copper(side: .top, index: nil))
    #expect(LayerClassifier.classify(fileName: "ok/l3", contents: header) == .copper(side: .none, index: 3))
    #expect(LayerClassifier.classify(fileName: "ok/bo", contents: header) == .silkscreen(side: .bottom))
    #expect(LayerClassifier.classify(fileName: "ok/ts", contents: header) == .solderMask(side: .top))
    #expect(LayerClassifier.classify(fileName: "ok/ko", contents: header) == .outline)
    #expect(LayerClassifier.classify(fileName: "ok/drl", contents: header) == .documentation)
    #expect(LayerClassifier.isGerber("ok/tl", contents: header))
}
