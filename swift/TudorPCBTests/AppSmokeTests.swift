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

private enum ControlledOpenError: Error { case failed }
private actor ControlledPackageLoader {
    private var requests: [String: CheckedContinuation<BoardDocument, any Error>] = [:]
    func load(_ url: URL) async throws -> BoardDocument {
        try await withCheckedThrowingContinuation { requests[url.lastPathComponent] = $0 }
    }
    func has(_ name: String) -> Bool { requests[name] != nil }
    func finish(_ name: String, document: BoardDocument?) {
        let request = requests.removeValue(forKey: name)
        if let document { request?.resume(returning: document) }
        else { request?.resume(throwing: ControlledOpenError.failed) }
    }
}

extension AppSmokeTests {
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for model transition")
    }

    private func waitForRequest(_ name: String, loader: ControlledPackageLoader) async throws {
        for _ in 0..<1000 {
            if await loader.has(name) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for \(name)")
    }

    @MainActor
    func testPendingOpenOwnsDocumentDespiteOldLayerAndFinishActions() async throws {
        let loader = ControlledPackageLoader()
        let model = WorkspaceModel(loadPackage: { try await loader.load($0) }, saveHistory: { _ in })
        model.historyEntries = []
        let aLayer = GerberLayer(fileName: "a.gtl", kind: .copper(side: .top, index: nil), primitives: [])
        let bLayer = GerberLayer(fileName: "b.gbl", kind: .copper(side: .bottom, index: nil), primitives: [])
        let a = BoardDocument(name: "A", layers: [aLayer])
        let b = BoardDocument(name: "B", layers: [bLayer], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 20, y: 5)))
        model.open(URL(fileURLWithPath: "/private/tmp/A.gtl"))
        try await waitForRequest("A.gtl", loader: loader)
        await loader.finish("A.gtl", document: a)
        try await waitUntil { !model.isLoading }
        model.open(URL(fileURLWithPath: "/private/tmp/B.gtl"))
        try await waitForRequest("B.gtl", loader: loader)
        XCTAssertEqual(model.pendingFileName, "B.gtl")
        model.toggleLayer(aLayer)
        model.selectMask(.red)
        XCTAssertEqual(model.maskStyle, .green) // Affected controls are disabled during replacement.
        XCTAssertEqual(model.visibleLayerIDs, [aLayer.id])
        await loader.finish("B.gtl", document: b)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.document, b)
        XCTAssertEqual(model.visibleLayerIDs, [bLayer.id])
        XCTAssertEqual(model.textures?.pixelWidth, 2048)
        XCTAssertEqual(model.textures?.pixelHeight, 512)
        XCTAssertEqual(Set(model.historyEntries.map(\.name)), ["A", "B"])
        XCTAssertEqual(model.historyEntries.first?.name, "B")
    }

    @MainActor
    func testLastOpenWinsOutOfOrderAndFailureRetainsOldBoard() async throws {
        let loader = ControlledPackageLoader()
        let model = WorkspaceModel(loadPackage: { try await loader.load($0) }, saveHistory: { _ in })
        model.historyEntries = []
        model.document = BoardDocument(name: "A")
        model.open(URL(fileURLWithPath: "/private/tmp/B.gtl"))
        try await waitForRequest("B.gtl", loader: loader)
        model.open(URL(fileURLWithPath: "/private/tmp/C.gtl"))
        try await waitForRequest("C.gtl", loader: loader)
        await loader.finish("C.gtl", document: BoardDocument(name: "C"))
        try await waitUntil { !model.isLoading }
        await loader.finish("B.gtl", document: BoardDocument(name: "B"))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.document?.name, "C")
        XCTAssertEqual(model.historyEntries.map(\.name), ["C"])
        let previousTextures = try XCTUnwrap(model.textures)
        model.open(URL(fileURLWithPath: "/private/tmp/B.gtl"))
        try await waitForRequest("B.gtl", loader: loader)
        await loader.finish("B.gtl", document: nil)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.document?.name, "C")
        XCTAssertTrue(model.textures?.top === previousTextures.top)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.historyEntries.map(\.name), ["C"])
    }
}


extension AppSmokeTests {
    @MainActor
    func testSameNamedGeometryRevisionsRebuildButFinishChangesReuseMesh() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float)
        let textures = try BoardRasterizer().render(BoardDocument(name: "texture"), options: .init(maximumTextureDimension: 256))
        let a = BoardDocument(name: "same", bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)))
        renderer.update(document: a, textures: textures)
        let old = try XCTUnwrap(renderer.vertexBuffer)
        let route = GerberLayer(fileName: "outline.gko", kind: .outline, primitives: [
            .line(start: Point2D(x: 5, y: 1), end: Point2D(x: 7, y: 1), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 7, y: 1), end: Point2D(x: 7, y: 3), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 7, y: 3), end: Point2D(x: 5, y: 3), width: 0.1, polarity: .dark),
            .line(start: Point2D(x: 5, y: 3), end: Point2D(x: 5, y: 1), width: 0.1, polarity: .dark)
        ])
        var b = BoardDocument(name: "same", layers: [route], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 20, y: 5)), thicknessMillimeters: 0.8)
        renderer.update(document: b, textures: textures)
        let revised = try XCTUnwrap(renderer.vertexBuffer)
        XCTAssertFalse(old === revised)
        XCTAssertEqual(renderer.indexCount, 36)
        let positions = revised.contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self)
        XCTAssertEqual(positions[0].position.z, 0.125, accuracy: 0.00001)
        XCTAssertEqual(positions[0].position.y, 0.02, accuracy: 0.00001)
        let finish = try BoardRasterizer().render(b, options: .init(maximumTextureDimension: 256, solderMaskColor: .redMask))
        renderer.update(document: b, textures: finish)
        XCTAssertTrue(renderer.vertexBuffer === revised)
        // Reopening a changed file in place creates the same name with new geometry.
        b.thicknessMillimeters = 2
        renderer.update(document: b, textures: finish)
        XCTAssertFalse(renderer.vertexBuffer === revised)
        let changed = try XCTUnwrap(renderer.vertexBuffer).contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self)
        XCTAssertEqual(changed[0].position.y, 0.05, accuracy: 0.00001)
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".gko")
        defer { try? FileManager.default.removeItem(at: url) }
        var prior: MTLBuffer?
        for (width, height) in [(100000, 100000), (200000, 50000)] {
            let source = "%FSLAX24Y24*%%MOMM*%%ADD10C,0.1*%D10*X0Y0D02*X\(width)Y0D01*X\(width)Y\(height)D01*X0Y\(height)D01*X0Y0D01*M02*"
            try Data(source.utf8).write(to: url)
            let reopened = try FabricationPackageLoader().load(from: url)
            renderer.update(document: reopened, textures: textures)
            let current = try XCTUnwrap(renderer.vertexBuffer)
            if let prior { XCTAssertFalse(current === prior) }
            prior = current
            let v = current.contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self)
            XCTAssertEqual(v[0].position.z, Float(height) / Float(width) / 2, accuracy: 0.00001)
        }
    }
}

private actor RenderWorkCounter {
    var active = 0
    var peak = 0
    var completed = 0
    func render(_ document: BoardDocument, _ options: BoardRenderOptions) async throws -> BoardTextureSet {
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        var options = options
        options.maximumTextureDimension = 256
        let result = try BoardRasterizer().render(document, options: options)
        completed += 1
        return result
    }
    func counts() -> (Int, Int) { (peak, completed) }
}

extension AppSmokeTests {
    @MainActor
    func testRapidOptionsCoalesceAndFinalPixelsMatchControls() async throws {
        let work = RenderWorkCounter()
        let model = WorkspaceModel(renderBoard: { try await work.render($0, $1) }, saveHistory: { _ in })
        let layer = GerberLayer(fileName: "top.gtl", kind: .copper(side: .top, index: nil), primitives: [.flash(center: Point2D(x: 5, y: 5), shape: .circle(diameter: 2), polarity: .dark)])
        let board = BoardDocument(name: "options", layers: [layer])
        model.document = board
        model.visibleLayerIDs = [layer.id]
        for i in 0..<100 {
            model.selectMask(i.isMultiple(of: 2) ? .red : .blue)
            model.toggleLayer(layer)
        }
        try await waitUntil { !model.isLoading }
        let counts = await work.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
        let expected = try BoardRasterizer().render(board, options: .init(visibleLayerIDs: model.visibleLayerIDs, maximumTextureDimension: 256, solderMaskColor: model.maskStyle.color))
        XCTAssertEqual(model.textures?.top.dataProvider?.data, expected.top.dataProvider?.data)
    }

    @MainActor
    func testSupersededOpensCancelAndBalanceSecurityScopes() async throws {
        var starts = 0
        var stops = 0
        let model = WorkspaceModel(loadPackage: { url in
            try await Task.sleep(for: .milliseconds(30))
            try Task.checkCancellation()
            return BoardDocument(name: url.lastPathComponent)
        }, startAccess: { _ in starts += 1; return true }, stopAccess: { _ in stops += 1 }, saveHistory: { _ in })
        model.historyEntries = []
        for i in 0..<20 { model.open(URL(fileURLWithPath: "/private/tmp/package-\(i).zip")) }
        try await waitUntil { !model.isLoading && stops == starts }
        XCTAssertEqual(starts, 20)
        XCTAssertEqual(stops, 20)
        XCTAssertEqual(model.document?.name, "package-19.zip")
        XCTAssertEqual(model.historyEntries.count, 1)
        XCTAssertNil(model.errorMessage)
    }
}

private enum InjectedGPUError: Error, LocalizedError {
    case allocation
    var errorDescription: String? { "Injected GPU allocation failure" }
}

extension AppSmokeTests {
    @MainActor
    func testGPUResourceFailuresAreTransactionalAndRetryable() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let a = BoardDocument(name: "A")
        let aTextures = try BoardRasterizer().render(a, options: .init(maximumTextureDimension: 256))
        let b = BoardDocument(name: "B", thicknessMillimeters: 0.8)
        let bTextures = try BoardRasterizer().render(b, options: .init(maximumTextureDimension: 256, solderMaskColor: .blueMask))
        for stage in [BoardRenderer.AllocationStage.topTexture, .bottomTexture, .maskTexture, .vertexBuffer, .indexBuffer] {
            var failedStage: BoardRenderer.AllocationStage?
            let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float,
                beforeAllocation: { if $0 == failedStage { throw InjectedGPUError.allocation } })
            XCTAssertTrue(renderer.update(document: a, textures: aTextures))
            let oldMesh = renderer.vertexBuffer
            let oldTop = renderer.topTexture
            let oldBottom = renderer.bottomTexture
            let oldMask = renderer.maskTexture
            failedStage = stage
            XCTAssertFalse(renderer.update(document: b, textures: bTextures))
            XCTAssertFalse(renderer.hasCurrentResources)
            XCTAssertNotNil(renderer.renderError)
            XCTAssertTrue(renderer.vertexBuffer === oldMesh)
            XCTAssertTrue(renderer.topTexture === oldTop)
            XCTAssertTrue(renderer.bottomTexture === oldBottom)
            XCTAssertTrue(renderer.maskTexture === oldMask)
            failedStage = nil
            XCTAssertTrue(renderer.update(document: b, textures: bTextures))
            XCTAssertNil(renderer.renderError)
            XCTAssertTrue(renderer.hasCurrentResources)
            XCTAssertFalse(renderer.vertexBuffer === oldMesh)
        }
    }

    @MainActor
    func testBottomAndMaskChangesUploadWhenTopImageIsUnchanged() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float)
        let board = BoardDocument(name: "identity")
        let a = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 256))
        let b = try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 256, solderMaskColor: .redMask))
        XCTAssertTrue(renderer.update(document: board, textures: a))
        let bottom = renderer.bottomTexture
        let mask = renderer.maskTexture
        let replacement = BoardTextureSet(top: a.top, bottom: b.bottom, boardMask: b.boardMask, pixelWidth: 256, pixelHeight: b.pixelHeight)
        XCTAssertTrue(renderer.update(document: board, textures: replacement))
        XCTAssertFalse(renderer.bottomTexture === bottom)
        XCTAssertFalse(renderer.maskTexture === mask)
    }

    @MainActor
    func testLibraryAndPipelineFailuresReachObservableStateAndRetry() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        for stage in [BoardRenderer.AllocationStage.library, .pipeline] {
            var fail = true
            let controller = ViewerController()
            let coordinator = MetalBoardView.Coordinator(controller: controller, makeRenderer: { device, color, depth in
                try BoardRenderer(device: device, colorPixelFormat: color, depthPixelFormat: depth,
                    beforeAllocation: { if fail && $0 == stage { throw InjectedGPUError.allocation } })
            })
            let view = MTKView(frame: .zero, device: device)
            view.colorPixelFormat = .bgra8Unorm_srgb
            view.depthStencilPixelFormat = .depth32Float
            coordinator.configure(view: view)
            try await waitUntil { controller.rendererError != nil }
            XCTAssertTrue(controller.rendererError?.contains("GPU allocation") == true)
            XCTAssertNil(coordinator.renderer)
            fail = false
            controller.retryRendering()
            coordinator.configure(view: view)
            try await waitUntil { controller.rendererError == nil }
            XCTAssertNotNil(coordinator.renderer)
            XCTAssertEqual(controller.retryRevision, 1)
        }
    }
}
