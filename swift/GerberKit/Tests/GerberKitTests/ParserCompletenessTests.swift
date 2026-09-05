import Foundation
import Testing
@testable import GerberKit

private let completenessHeader = "%FSLAX24Y24*%%MOMM*%%ADD10C,1*%D10*"

@Test(arguments: [
    "X0Y0D03*%LMX*%X10000Y0D03*M02*",
    "X0Y0D03*%LR90*%M02*", "X0Y0D03*%LS2*%M02*",
    "%ABD11*%X0Y0D03*%AB*%D11*X10000Y0D03*M02*",
    "X0Y0D03*%IPNEG*%M02*", "X0Y0D03*D99*X10000Y0D03*M02*",
    "X0Y0D03*XoopsY0D03*M02*", "X0Y0D03*X1..2D03*M02*",
    "X0Y0D03*G36*X0Y0D02*X10000Y0D01*M02*",
    "X0Y0D03*", "X0Y0D03*M02*X10000Y0D03*",
    "X0Y0D03*%LPD*", "X0Y0D03*G37*M02*",
    "X0Y0D03*%SRX2Y2I1J1*%X0Y0D03*M02*"
])
func unsupportedOrIncompleteLayersCannotReportSuccess(body: String) throws {
    do {
        _ = try GerberParser().parse(data: Data((completenessHeader + body).utf8), fileName: "incomplete.gtl")
        Issue.record("Accepted unsupported/incomplete layer")
    } catch let GerberParseError.invalidCommand(fileName, command, reason) {
        #expect(fileName == "incomplete.gtl")
        #expect(!command.isEmpty && !reason.isEmpty)
    }
}

@Test func metadataIdentityTransformsAndEmptyAuxiliaryLayersRemainHarmless() throws {
    let layer = try GerberParser().parse(data: Data((completenessHeader + "G04 human comment*%TF.FileFunction,Copper,L1,Top*%%TA.AperFunction,ComponentPad*%%TO.N,GND*%%TD*%%LMN*%%LR0*%%LS1*%%IPPOS*%X0Y0D03*M02*").utf8), fileName: "valid.gtl")
    #expect(layer.primitives.count == 1)
    let board = try FabricationPackageLoader().load(files: [
        ZipEntry(name: "valid.gtl", data: Data((completenessHeader + "X0Y0D03*M02*").utf8)),
        ZipEntry(name: "empty.gdd", data: Data("G04 intentionally empty documentation*M02*".utf8)),
        ZipEntry(name: "unsupported.gbl", data: Data((completenessHeader + "%LR45*%X0Y0D03*M02*").utf8))
    ], name: "partial")
    #expect(board.layers.count == 1)
    #expect(board.warnings.count == 1)
    #expect(board.warnings[0].contains("unsupported.gbl") && board.warnings[0].contains("LR45"))
}

@Test func operationsRequireDeclaredFormatUnitsAndSelectedAperture() throws {
    for source in ["%ADD10C,1*%D10*X1Y1D03*M02*", "%FSLAX24Y24*%%MOMM*%X0Y0D03*M02*"] {
        #expect(throws: GerberParseError.self) { try GerberParser().parse(data: Data(source.utf8), fileName: "state.gtl") }
    }
}
