import Foundation
import Testing
@testable import GerberKit

@Test func legacyRectanglesSweepSquareCornersWithoutRoundCaps() throws {
    let source = "%FSLAX24Y24*%%MOMM*%%ADD10R,1X2*%D10*X0Y0D02*X10000Y0D01*M02*"
    let layer = try GerberParser().parse(data: Data(source.utf8), fileName: "legacy.gtl")
    #expect(layer.bounds == Bounds2D(minimum: Point2D(x: -0.5, y: -1), maximum: Point2D(x: 1.5, y: 1)))
    guard case let .region(contours, _) = try #require(layer.primitives.first) else { Issue.record("Missing rectangle sweep"); return }
    #expect(Set(contours[0]) == Set([Point2D(x: -0.5, y: -1), Point2D(x: 1.5, y: -1), Point2D(x: 1.5, y: 1), Point2D(x: -0.5, y: 1)]))
    let bounds = Bounds2D(minimum: Point2D(x: -2, y: -2), maximum: Point2D(x: 2, y: 2))
    let image = try BoardRasterizer().render(BoardDocument(name: "legacy", layers: [layer], bounds: bounds), options: .init(maximumTextureDimension: 256)).top
    let empty = try BoardRasterizer().render(BoardDocument(name: "empty", bounds: bounds), options: .init(maximumTextureDimension: 256)).top
    #expect(try rgba(image, x: 99, y: 67) != rgba(empty, x: 99, y: 67))
    #expect(try rgba(image, x: 90, y: 128) == rgba(empty, x: 90, y: 128))
}

@Test func unsupportedLegacyArcsAndDrawAperturesProduceVisibleWarnings() throws {
    let header = "%FSLAX24Y24*%%MOMM*%%ADD10C,0.2*%D10*"
    let quadrants = [(1,0,0,1,-1,0),(0,1,-1,0,0,-1),(-1,0,0,-1,1,0),(0,-1,1,0,0,1)]
    for (sx,sy,ex,ey,i,j) in quadrants {
        let start = "X\(sx*10000)Y\(sy*10000)D02*"
        let arc = "G03X\(ex*10000)Y\(ey*10000)I\(i*10000)J\(j*10000)D01*M02*"
        let equivalent = try GerberParser().parse(data: Data((header + start + "G75*" + arc).utf8), fileName: "multi.gtl")
        #expect(equivalent.primitives.count == 1)
        #expect(throws: GerberParseError.self) { try GerberParser().parse(data: Data((header + start + "G74*" + arc).utf8), fileName: "single.gtl") }
    }
    let unsupported = ["%ADD11O,1X2*%D11*G01X10000Y0D01*", "%ADD11P,1X6*%D11*G01X10000Y0D01*", "%ADD11R,1X2*%D11*G75*G03X10000Y10000I0J10000D01*", "G74*G03X10000Y10000I0J10000D01*"]
    let files = [ZipEntry(name: "valid.gtl", data: Data((header + "X0Y0D03*M02*").utf8))] + unsupported.enumerated().map { index, body in
        ZipEntry(name: "unsupported\(index).gbl", data: Data((header + "X0Y0D02*" + body + "M02*").utf8))
    }
    let document = try FabricationPackageLoader().load(files: files, name: "legacy")
    #expect(document.warnings.count == 4)
    #expect(document.warnings.allSatisfy { $0.contains("Unsupported") && $0.contains("unsupported") })
}
