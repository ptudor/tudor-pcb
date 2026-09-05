import Foundation
import Testing
@testable import GerberKit

@Test(arguments: [
    "%ADD10*%", "%AMbad*4,1,-1,0,0,0,0*%", "%ADD10P,1Xinf*%",
    "%ADD10P,1Xnan*%", "%ADD10P,1X999999999999999999999999*%",
    "%ADD10C,nan*%", "%ADD10C,inf*%", "%ADD10C,-1*%", "%ADD10R,1*%",
    "%ADD10R,1XX2*%", "%ADD10P,1X3.5*%", "%ADD10C,1oops*%", "%ADD10unknown*%"
])
func malformedAperturesThrowWithCommandContext(definition: String) throws {
    do {
        _ = try GerberParser().parse(data: Data((definition + "D10*X0Y0D03*M02*").utf8), fileName: "malformed.gtl")
        Issue.record("Accepted malformed definition: \(definition)")
    } catch let GerberParseError.invalidDefinition(fileName, command, reason) {
        #expect(fileName == "malformed.gtl")
        #expect(!command.isEmpty)
        #expect(!reason.isEmpty)
    }
}

@Test func legalZeroCircleAndLiteralMacroRemainAccepted() throws {
    for definition in ["%ADD10C,0*%", "%AMtriangle*4,1,3,0,0,1,0,0,1,0,0,0*%%ADD10triangle*%"] {
        let layer = try GerberParser().parse(data: Data(("%FSLAX24Y24*%%MOMM*%" + definition + "D10*X0Y0D03*M02*").utf8), fileName: "valid.gtl")
        #expect(layer.primitives.count == 1)
    }
}
