import Foundation
import Testing
@testable import GerberKit

private func modalLayer(_ body: String) throws -> GerberLayer {
    try GerberParser().parse(data: Data(("%FSLAX24Y24*%%MOMM*%%ADD10C,0.2*%D10*" + body + "M02*").utf8), fileName: "modal.gtl")
}

@Test func omittedCoordinatesAndStandaloneOperationsRetainTheirMeaning() throws {
    let flash = try modalLayer("X10000Y10000D02*D03*G01*G75*")
    #expect(flash.primitives == [.flash(center: Point2D(x: 1, y: 1), shape: .circle(diameter: 0.2), polarity: .dark)])
    let circle = try modalLayer("X10000Y0D02*G75*G03I-10000J0D01*")
    #expect(circle.primitives == [.arc(start: Point2D(x: 1, y: 0), end: Point2D(x: 1, y: 0), center: .zero, clockwise: false, width: 0.2, polarity: .dark)])
    let lines = try modalLayer("X0Y0D02*D01*X10000Y0*Y10000*D02*X20000*D01*Y20000*G01*G75*")
    #expect(lines.primitives.last == .line(start: Point2D(x: 2, y: 1), end: Point2D(x: 2, y: 2), width: 0.2, polarity: .dark))
    #expect(lines.primitives.contains(.line(start: .zero, end: Point2D(x: 1, y: 0), width: 0.2, polarity: .dark)))
    #expect(!lines.primitives.contains(.line(start: Point2D(x: 1, y: 1), end: Point2D(x: 2, y: 1), width: 0.2, polarity: .dark)))
}

@Test func coordinateFreeOperationsInsideRegionsRespectContourBoundaries() throws {
    let layer = try modalLayer("G36*X0Y0D02*D01*X10000*Y10000*X0*Y0*D02*X-10000Y0D01*Y-10000*X0*Y0*G01*G75*G37*")
    guard case let .region(contours, _) = try #require(layer.primitives.first) else { Issue.record("Missing region"); return }
    #expect(contours.count == 2)
    #expect(contours[1].first == .zero)
    let circle = try modalLayer("G36*X10000Y0D02*G75*G03I-10000J0D01*G37*")
    guard case let .region(arcs, _) = try #require(circle.primitives.first) else { Issue.record("Missing circular region"); return }
    #expect(arcs[0].count > 20)
    #expect(arcs[0].contains { $0.x < -0.9 })
    #expect(throws: GerberParseError.self) { try modalLayer("G36*D03*G37*") }
}
