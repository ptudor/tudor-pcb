import XCTest
import GerberKit
import MetalKit
@testable import TudorPCB

final class AppSmokeTests: XCTestCase {
    func testHistoryMergePreservesFirstVisitAndIncrementsCount() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tudor-pcb-history-test-\(UUID().uuidString).gbr")
        try Data("M02*".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = BoardDocument(name: "Review A")
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let first = PackageHistoryEntry.capture(url: url, document: document, now: firstDate)
        let second = PackageHistoryEntry.capture(url: url, document: document, now: secondDate)

        let once = PackageHistoryStore.merging(first, into: [])
        let twice = PackageHistoryStore.merging(second, into: once)

        XCTAssertEqual(twice.count, 1)
        XCTAssertEqual(twice[0].id, first.id)
        XCTAssertEqual(twice[0].firstOpenedAt, firstDate)
        XCTAssertEqual(twice[0].lastOpenedAt, secondDate)
        XCTAssertEqual(twice[0].openedCount, 2)
    }
}


private actor DelayedProofReader {
    private var continuation: CheckedContinuation<BoardSidePreview, any Error>?
    var entered = false
    func read() async throws -> BoardSidePreview {
        try await withCheckedThrowingContinuation {
            entered = true
            continuation = $0
        }
    }
    func fail() {
        continuation?.resume(throwing: ProofImageError.invalid("delayed.png"))
        continuation = nil
    }
}

extension AppSmokeTests {
    @MainActor
    func testDelayedProofReadKeepsMainActorResponsiveAndRetainsPreviousDocumentOnFailure() async throws {
        let reader = DelayedProofReader()
        let model = WorkspaceModel(readProof: { _, _ in try await reader.read() })
        let original = BoardDocument(name: "original")
        model.document = original
        model.attachColorProof(URL(fileURLWithPath: "/delayed.png"), side: .top)
        for _ in 0..<1000 {
            if await reader.entered { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let entered = await reader.entered
        XCTAssertTrue(entered)
        // This main-actor continuation executes while the provider is suspended.
        XCTAssertEqual(model.document, original)
        await reader.fail()
        for _ in 0..<1000 {
            if model.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(model.errorMessage?.contains("delayed.png") == true)
        XCTAssertEqual(model.document, original)
    }
}


extension AppSmokeTests {
    @MainActor
    func testMeshPreservesPhysicalThicknessAcrossBoardSizes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float)
        let textures = try BoardRasterizer().render(BoardDocument(name: "texture"), options: .init(maximumTextureDimension: 256))
        for size in [50.0, 100.0, 200.0] {
            let board = BoardDocument(name: "board-\(size)", bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: size, y: size / 2)), thicknessMillimeters: 1.6)
            renderer.update(document: board, textures: textures)
            let buffer = try XCTUnwrap(renderer.vertexBuffer)
            let vertices = buffer.contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self)
            XCTAssertEqual(Double(vertices[0].position.y - vertices[4].position.y) * size, 1.6, accuracy: 0.00001)
        }
    }
}
