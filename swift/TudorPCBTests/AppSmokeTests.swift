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


extension AppSmokeTests {
    @MainActor
    func testLargeOutlineUsesComplete32BitMeshAndPreservesBottomUVs() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float)
        let bounds = Bounds2D(minimum: .zero, maximum: Point2D(x: 100, y: 100))
        let bottom = GerberLayer(fileName: "bottom.gbl", kind: .copper(side: .bottom, index: nil), primitives: [
            .line(start: Point2D(x: 20, y: 20), end: Point2D(x: 20, y: 80), width: 5, polarity: .dark),
            .line(start: Point2D(x: 20, y: 80), end: Point2D(x: 60, y: 80), width: 5, polarity: .dark),
            .line(start: Point2D(x: 20, y: 50), end: Point2D(x: 45, y: 50), width: 5, polarity: .dark)
        ])
        let textures = try BoardRasterizer().render(BoardDocument(name: "asymmetric-bottom", layers: [bottom], bounds: bounds), options: .init(maximumTextureDimension: 256))
        for count in [4, 16_383] {
            let points = (0..<count).map { i in
                let a = Double(i) / Double(count) * 2 * Double.pi
                return Point2D(x: 50 + 40 * cos(a), y: 50 + 40 * sin(a))
            }
            let edges = points.indices.map { GerberPrimitive.line(start: points[$0], end: points[($0 + 1) % count], width: 0.1, polarity: .dark) }
            let board = BoardDocument(name: "outline-\(count)", layers: [GerberLayer(fileName: "outline.gko", kind: .outline, primitives: edges)], bounds: bounds)
            renderer.update(document: board, textures: textures)
            XCTAssertNil(renderer.geometryError)
            let vertices = try XCTUnwrap(renderer.vertexBuffer)
            let indices = try XCTUnwrap(renderer.indexBuffer)
            let vertexCount = vertices.length / MemoryLayout<BoardRenderer.BoardVertex>.stride
            XCTAssertEqual(vertexCount, (count + 2) * 4)
            XCTAssertEqual(renderer.indexCount, (count + 2) * 6)
            let values = Array(UnsafeBufferPointer(start: indices.contents().assumingMemoryBound(to: UInt32.self), count: renderer.indexCount))
            XCTAssertEqual(Set(values).count, vertexCount)
            XCTAssertEqual(values.max(), UInt32(vertexCount - 1))
            let v = vertices.contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self)
            XCTAssertEqual(v[4].uv, SIMD2<Float>(1, 0))
            XCTAssertEqual(v[5].uv, SIMD2<Float>(0, 0))
            XCTAssertEqual(v[6].uv, SIMD2<Float>(0, 1))
            XCTAssertEqual(v[7].uv, SIMD2<Float>(1, 1))
        }
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        renderer.apply(.bottom)
        renderer.draw(in: view)
        let command = try XCTUnwrap(renderer.lastCommandBuffer)
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        XCTAssertNil(command.error)
    }

    @MainActor
    func testMeshAllocationFailureIsReportedAndCanRetry() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var fail = true
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float,
            bufferAllocator: { pointer, count in fail ? nil : device.makeBuffer(bytes: pointer, length: count) })
        let board = BoardDocument(name: "retry")
        let textures = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 256))
        renderer.update(document: board, textures: textures)
        XCTAssertNotNil(renderer.geometryError)
        XCTAssertNil(renderer.vertexBuffer)
        XCTAssertNil(renderer.indexBuffer)
        fail = false
        renderer.update(document: board, textures: textures)
        XCTAssertNil(renderer.geometryError)
        XCTAssertNotNil(renderer.vertexBuffer)
        XCTAssertNotNil(renderer.indexBuffer)
    }
}
