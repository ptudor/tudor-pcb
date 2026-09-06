import Foundation
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

@Test func parentDirectoriesCannotChangeLayerRolesOrGeometry() throws {
    let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let board = root.appending(path: "required-board")
    let entries = try ["board.gko", "board.gtl", "board.drl"].map { ZipEntry(name: $0, data: try Data(contentsOf: board.appending(path: $0))) }
    let baseline = try FabricationPackageLoader().load(files: entries, name: "board")
    for parent in ["neutral", "drill", "drawing", "outline"] {
        let prefixed = entries.map { ZipEntry(name: parent + "/" + $0.name, data: $0.data) }
        let document = try FabricationPackageLoader().load(files: prefixed, name: "board")
        #expect(document.layers.map(\.kind) == baseline.layers.map(\.kind))
        #expect(document.layers.map(\.primitives) == baseline.layers.map(\.primitives))
        #expect(document.drills == baseline.drills)
        #expect(document.bounds == baseline.bounds)
        #expect(document.warnings.isEmpty)
    }
}

@Test func structuredAttributesOverrideBasenamesAndReportConflicts() throws {
    let classification = LayerClassifier.classification(fileName: "drawing/board.gtl", contents: "%TF.FileFunction,Copper,L2,Bot*%%TO.N,top*%")
    #expect(classification.kind == .copper(side: .bottom, index: nil))
    #expect(classification.warnings.count == 1)
    #expect(LayerClassifier.classify(fileName: "neutral.gbr", contents: "%TF.FileFunction,Copper,L2,Inr*%%TO.N,top*%") == .copper(side: .none, index: 2))
    #expect(LayerClassifier.classify(fileName: "drillboard.gtl") == .copper(side: .top, index: nil))
    let source = "%FSLAX24Y24*%%MOMM*%%TF.FileFunction,Copper,L2,Bot*%%ADD10C,1*%D10*X0Y0D03*M02*"
    let board = try FabricationPackageLoader().load(files: [ZipEntry(name: "board.gtl", data: Data(source.utf8))], name: "conflict")
    #expect(board.layers[0].kind == .copper(side: .bottom, index: nil))
    #expect(board.warnings.contains { $0.contains("FileFunction overrides") })
    // A filename drill role must not send Gerber syntax to the Excellon parser.
    let gerberDrill = source.replacingOccurrences(of: "%TF.FileFunction,Copper,L2,Bot*%", with: "")
    let syntaxBoard = try FabricationPackageLoader().load(files: [ZipEntry(name: "Drill.gbr", data: Data(gerberDrill.utf8))], name: "syntax")
    #expect(syntaxBoard.layers[0].primitives.count == 1)
    #expect(syntaxBoard.warnings.isEmpty)
}
