import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GerberKit

private func proofData(type: String = "public.png", frames: Int = 1, orientation: Int = 1) throws -> Data {
    let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, frames, nil))
    for _ in 0..<frames { CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary) }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func proofDecodeRejectsOversizeFramesAndCorruptMetadataBeforeDecode() throws {
    let large = try #require(Bundle.module.url(forResource: "Fixtures/large-dimension", withExtension: "png"))
    #expect(throws: ImportLimitError.self) { try ProofImageDecoder.decode(Data(contentsOf: large), name: "large.png") }
    #expect(throws: ImportLimitError.self) { try ProofImageDecoder.decode(proofData(type: "public.tiff", frames: 2), name: "multi.tiff") }
    #expect(throws: ProofImageError.self) { try ProofImageDecoder.decode(Data("invalid".utf8), name: "bad.png") }
    let valid = try proofData()
    #expect(throws: ProofImageError.self) { try ProofImageDecoder.decode(Data(valid.prefix(16)), name: "truncated.png") }
    var limits = ImportLimits()
    limits.imageFileBytes = valid.count - 1
    #expect(throws: ImportLimitError.self) { try ProofImageDecoder.decode(valid, name: "large-file.png", limits: limits) }
}

@Test func proofThumbnailsPreserveAspectOrientationAndColor() throws {
    for type in ["public.png", "public.jpeg", "public.tiff"] {
        let image = try ProofImageDecoder.decode(proofData(type: type), name: "proof", maximumDimension: 32).cgImage
        #expect(image.width == 32)
        #expect(image.height == 16)
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[0] > 240 && bytes[1] < 15 && bytes[2] < 15 && bytes[3] == 255)
    }
    let rotated = try ProofImageDecoder.decode(proofData(type: "public.tiff", orientation: 6), name: "rotated.tiff", maximumDimension: 32)
    #expect(rotated.cgImage.width == 16)
    #expect(rotated.cgImage.height == 32)
}

@Test func coordinatedProofReadsAreBoundedAndCancellable() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
    try proofData().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let preview = try await ProofImageDecoder.read(url, side: .bottom)
    #expect(preview.side == .bottom)
    #expect(preview.validatedImage?.cgImage.width == 80)
    var limits = ImportLimits()
    limits.imageFileBytes = 1
    do { _ = try await ProofImageDecoder.read(url, side: .top, limits: limits); Issue.record("Accepted oversized local proof") }
    catch is ImportLimitError { }
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return try await ProofImageDecoder.read(url, side: .top)
    }
    task.cancel()
    do { _ = try await task.value; Issue.record("Ignored cancellation") }
    catch is CancellationError { }
}
