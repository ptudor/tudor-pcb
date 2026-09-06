import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GerberKit

private func landmarkProof() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 60, y: 20, width: 30, height: 20))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func revisionMatchingAndDuplicateProofsStayExplicit() throws {
    #expect(FabricationPackageLoader.matchesSidecar("rev1_top.png", archiveName: "rev1.zip"))
    #expect(FabricationPackageLoader.matchesSidecar("rev1-artwork-top.jpg", archiveName: "rev1_Gerbers.zip"))
    #expect(!FabricationPackageLoader.matchesSidecar("rev10_top.png", archiveName: "rev1.zip"))
    #expect(!FabricationPackageLoader.matchesSidecar("rev1_old_top.png", archiveName: "rev1.zip"))
    let bytes = try landmarkProof()
    let gerber = Data("%FSLAX24Y24*%%MOMM*%%ADD10C,1*%D10*X10000Y10000D03*M02*".utf8)
    let document = try FabricationPackageLoader().load(files: [
        ZipEntry(name: "rev1.gtl", data: gerber),
        ZipEntry(name: "rev1_top.png", data: bytes),
        ZipEntry(name: "rev1-artwork-top.png", data: bytes)
    ], name: "rev1")
    #expect(document.sidePreviews.count == 2)
    #expect(document.sidePreviews.allSatisfy { $0.purpose == .galleryProof && $0.mapping == nil })
    #expect(document.activeArtwork(for: .top) == nil)
}

@Test func explicitBoundsAndOrientationAlignAsymmetricLandmarksOnPanels() throws {
    let bytes = try landmarkProof()
    let bounds = Bounds2D(minimum: .zero, maximum: Point2D(x: 20, y: 10))
    let mapping = BoardArtworkMapping(bounds: Bounds2D(minimum: Point2D(x: 2, y: 2), maximum: Point2D(x: 8, y: 8)), orientation: .boardCoordinates)
    var top = BoardSidePreview(side: .top, fileName: "screenshot_top.png", imageData: bytes, purpose: .boardArtwork, mapping: mapping)
    var bottom = BoardSidePreview(side: .bottom, fileName: "art_bottom.png", imageData: bytes, purpose: .boardArtwork, mapping: mapping)
    var board = BoardDocument(name: "panel rails", bounds: bounds, sidePreviews: [top, bottom])
    let rasterizer = BoardRasterizer()
    func blue(_ image: CGImage, x: Int, y: Int) throws -> Bool { let p = try rgba(image, x: x, y: y); return p[2] > 240 && p[0] < 20 }
    let same = try rasterizer.render(board, options: .init(maximumTextureDimension: 1000))
    #expect(try blue(same.top, x: 325, y: 310))
    #expect(try blue(same.bottom, x: 325, y: 310))
    #expect(try rgba(same.top, x: 50, y: 250)[0] < 20) // Panel rail is not stretched artwork.
    bottom.mapping?.orientation = .viewedFromBottom
    board.sidePreviews = [top, bottom]
    let mirrored = try rasterizer.render(board, options: .init(maximumTextureDimension: 1000))
    #expect(try blue(mirrored.bottom, x: 175, y: 310))
    #expect(try !blue(mirrored.bottom, x: 325, y: 310))
    #expect(try blue(mirrored.top, x: 325, y: 310))
    top.mapping = BoardArtworkMapping(bounds: bounds, orientation: .boardCoordinates)
    board.sidePreviews = [top]
    let fullPanel = try rasterizer.render(board, options: .init(maximumTextureDimension: 1000))
    #expect(try blue(fullPanel.top, x: 750, y: 350))
    let invalid = BoardArtworkMapping(bounds: Bounds2D(minimum: .zero, maximum: .zero), orientation: .boardCoordinates)
    #expect(throws: GeometryLimitError.self) { try invalid.validate() }
}
