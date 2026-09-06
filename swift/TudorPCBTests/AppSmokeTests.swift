import XCTest
import GerberKit
import MetalKit
import ImageIO
@testable import TudorPCB

final class AppSmokeTests: XCTestCase {
    func testHistoryRecoveryPreservesOriginalBytesAndIndividualValidRecords() throws {
        let name = "TudorPCB.history-recovery-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entry = PackageHistoryEntry.capture(url: URL(fileURLWithPath: "/board.gbr"), document: BoardDocument(name: "valid"))
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var malformed = record; malformed.removeValue(forKey: "id")
        var unknown = record; unknown["sourceKind"] = "future-kind"
        for bad in [malformed, unknown] {
            let original = try JSONSerialization.data(withJSONObject: [record, bad])
            defaults.set(original, forKey: PackageHistoryStore.defaultsKey)
            let loaded = PackageHistoryStore.load(defaults: defaults)
            XCTAssertEqual(loaded.entries, [entry])
            XCTAssertNotNil(loaded.recovery)
            XCTAssertThrowsError(try PackageHistoryStore.save([], defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: PackageHistoryStore.defaultsKey), original)
            let backup = try PackageHistoryStore.recover(loaded.entries, original: original, defaults: defaults)
            XCTAssertEqual(defaults.data(forKey: backup), original)
            XCTAssertNil(PackageHistoryStore.load(defaults: defaults).recovery)
            XCTAssertEqual(PackageHistoryStore.load(defaults: defaults).entries, [entry])
        }
        for original in [Data("[{\"id\":".utf8), Data("{\"version\":99,\"entries\":[]}".utf8)] {
            defaults.set(original, forKey: PackageHistoryStore.defaultsKey)
            XCTAssertNotNil(PackageHistoryStore.load(defaults: defaults).recovery)
            XCTAssertThrowsError(try PackageHistoryStore.save([entry], defaults: defaults))
            XCTAssertEqual(defaults.data(forKey: PackageHistoryStore.defaultsKey), original)
            let backup = try PackageHistoryStore.recover([], original: original, defaults: defaults)
            XCTAssertEqual(defaults.data(forKey: backup), original)
        }
        try PackageHistoryStore.save([entry], defaults: defaults)
        let previous = defaults.data(forKey: PackageHistoryStore.defaultsKey)
        var invalid = entry; invalid.boardWidth = .infinity
        XCTAssertThrowsError(try PackageHistoryStore.save([invalid], defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: PackageHistoryStore.defaultsKey), previous)
        let merged = PackageHistoryStore.merging(entry, into: PackageHistoryStore.load(defaults: defaults).entries)
        try PackageHistoryStore.save(merged, defaults: defaults)
        XCTAssertEqual(PackageHistoryStore.load(defaults: defaults).entries[0].openedCount, 2)
        try PackageHistoryStore.save([], defaults: defaults)
        XCTAssertTrue(PackageHistoryStore.load(defaults: defaults).entries.isEmpty)
    }

    @MainActor
    func testMachinedFacesRevealContrastingBackgroundAndHavePhysicalWalls() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try BoardRenderer(device: device, colorPixelFormat: .bgra8Unorm_srgb, depthPixelFormat: .depth32Float)
        let board = BoardDocument(name: "through machining", drills: [
            DrillHit(center: Point2D(x: 5, y: 5), diameter: 4, plated: true),
            DrillHit(center: Point2D(x: 2, y: 1), end: Point2D(x: 8, y: 1), diameter: 1, plated: false)
        ], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10)), thicknessMillimeters: 1.6)
        renderer.update(document: board, textures: try BoardRasterizer().render(board, options: .init(maximumTextureDimension: 1024)))
        XCTAssertNil(renderer.geometryError)
        let vertexBuffer = try XCTUnwrap(renderer.vertexBuffer)
        let vertices = Array(UnsafeBufferPointer(start: vertexBuffer.contents().assumingMemoryBound(to: BoardRenderer.BoardVertex.self), count: vertexBuffer.length / MemoryLayout<BoardRenderer.BoardVertex>.stride))
        XCTAssertTrue(vertices.contains { $0.material == 2 })
        let barrels = vertices.filter { $0.material == 3 }
        XCTAssertFalse(barrels.isEmpty)
        for vertex in barrels {
            XCTAssertEqual(hypot(vertex.position.x, vertex.position.z) * 10, 2, accuracy: 0.0001)
            XCTAssertEqual(abs(vertex.position.y) * 10, 0.8, accuracy: 0.0001)
        }
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.framebufferOnly = false
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 1, green: 0, blue: 1, alpha: 1)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        var slotBoard = board
        slotBoard.drills = [DrillHit(center: Point2D(x: 2, y: 5), end: Point2D(x: 8, y: 5), diameter: 2, plated: false)]
        for machiningBoard in [board, slotBoard] {
        renderer.update(document: machiningBoard, textures: try BoardRasterizer().render(machiningBoard, options: .init(maximumTextureDimension: 1024)))
        for preset in [CameraPreset.top, .bottom, .perspective] {
            renderer.apply(preset)
            if preset == .perspective { renderer.orbit(deltaX: 0, deltaY: 60) }
            let drawable = try XCTUnwrap(view.currentDrawable)
            renderer.draw(in: view)
            let command = try XCTUnwrap(renderer.lastCommandBuffer)
            command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            let texture = drawable.texture
            let bytesPerRow = texture.width * 4
            let output = try XCTUnwrap(device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared))
            let copy = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
            let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: output, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * texture.height)
            blit.endEncoding(); copy.commit(); copy.waitUntilCompleted()
            XCTAssertEqual(copy.status, .completed)
            let pixels = output.contents().assumingMemoryBound(to: UInt8.self)
            let center = (texture.height / 2) * bytesPerRow + (texture.width / 2) * 4
            XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels + center, count: 4)), [255, 0, 255, 255])
            // Both a visible face and background must be present in the frame.
            let nonBackground = stride(from: 0, to: bytesPerRow * texture.height, by: 4).filter { pixels[$0 + 1] > 0 && pixels[$0 + 1] < 250 }
            XCTAssertGreaterThan(nonBackground.count, 500)
        }
        }
    }

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
    func testAttachedArtworkOverridesSuppliedAndCanResetWithoutLosingProvenance() async throws {
        func png(_ color: NSColor) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
        let red = try png(.red), blue = try png(.blue), green = try png(.green)
        let supplied = BoardSidePreview(side: .top, fileName: "artwork_top.png", imageData: red)
        let model = WorkspaceModel(readProof: { url, side in
            let data = url.lastPathComponent == "blue.png" ? blue : green
            return BoardSidePreview(side: side, fileName: url.lastPathComponent, imageData: data, validatedImage: try ProofImageDecoder.decode(data, name: url.lastPathComponent))
        }, saveHistory: { _ in })
        model.document = BoardDocument(name: "proofs", sidePreviews: [supplied])
        func center(_ image: CGImage) throws -> [UInt8] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: 4))
        }
        model.attachColorProof(URL(fileURLWithPath: "/blue.png"), side: .top)
        try await waitUntil { model.document?.activeArtwork(for: .top)?.provenance == .attached && !model.isLoading }
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).top)[2], 240)
        XCTAssertEqual(model.document?.sidePreviews.map(\.fileName), ["artwork_top.png", "blue.png"])
        XCTAssertEqual(model.document?.sidePreviews.map(\.provenance), [.supplied, .attached])
        model.attachColorProof(URL(fileURLWithPath: "/green.png"), side: .top)
        try await waitUntil { model.document?.activeArtwork(for: .top)?.fileName == "green.png" && !model.isLoading }
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).top)[1], 240)
        model.attachColorProof(URL(fileURLWithPath: "/blue.png"), side: .bottom)
        try await waitUntil { model.document?.activeArtwork(for: .bottom) != nil && !model.isLoading }
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).bottom)[2], 240)
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).top)[1], 240)
        model.resetArtwork(.top)
        try await waitUntil { !model.isLoading }
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).top)[0], 240)
        XCTAssertEqual(model.document?.activeArtwork(for: .top)?.id, supplied.id)
        let attached = try XCTUnwrap(model.document?.sidePreviews.first { $0.side == .top && $0.provenance == .attached })
        model.selectArtwork(attached)
        try await waitUntil { !model.isLoading }
        XCTAssertGreaterThan(try center(XCTUnwrap(model.textures).top)[1], 240)
    }

    @MainActor
    func testMovedBookmarkRetainsIdentityAndDoesNotCollapseReplacementAtOldPath() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "moved-history-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appending(path: "old.gbr"), moved = directory.appending(path: "moved.gbr")
        try Data("original".utf8).write(to: old)
        let bookmark = try PackageHistoryStore.makeBookmark(for: old)
        let original = PackageHistoryEntry.capture(url: old, document: BoardDocument(name: "original"), now: Date(timeIntervalSince1970: 100), bookmarkData: bookmark)
        try FileManager.default.moveItem(at: old, to: moved)
        XCTAssertEqual(try PackageHistoryStore.resolved(original).url.resolvingSymlinksInPath().path, moved.resolvingSymlinksInPath().path)
        let available = await PackageHistoryStore.availability(original, startAccess: { _ in true }, stopAccess: { _ in })
        XCTAssertEqual(available, .moved)
        let denied = await PackageHistoryStore.availability(original, startAccess: { _ in false })
        XCTAssertEqual(denied, .inaccessible)
        let missing = await PackageHistoryStore.availability(original, resolver: { _ in HistoryResolvedSource(url: directory.appending(path: "missing"), stale: true) }, startAccess: { _ in true }, stopAccess: { _ in })
        XCTAssertEqual(missing, .missing)
        let owner = PackageHistoryOwner(writer: { _ in })
        owner.record(original)
        let model = WorkspaceModel(loadPackage: { BoardDocument(name: $0.lastPathComponent) }, startAccess: { _ in true }, stopAccess: { _ in }, history: owner)
        model.open(original)
        try await waitUntil { !model.isLoading }
        let reopened = try XCTUnwrap(owner.entries.first { $0.id == original.id })
        XCTAssertEqual(URL(fileURLWithPath: reopened.sourcePath).resolvingSymlinksInPath().path, moved.resolvingSymlinksInPath().path)
        XCTAssertEqual(reopened.firstOpenedAt, original.firstOpenedAt)
        XCTAssertEqual(reopened.openedCount, 2)
        XCTAssertNotNil(reopened.bookmarkData)
        XCTAssertEqual(owner.entries.count, 1)
        try Data("different file".utf8).write(to: old)
        let replacement = PackageHistoryEntry.capture(url: old, document: BoardDocument(name: "replacement"))
        let oldList = PackageHistoryStore.merging(replacement, into: [original])
        XCTAssertEqual(oldList.count, 2) // Same path is insufficient after replacement.
        owner.record(replacement)
        let wrongResolution = await PackageHistoryStore.availability(original, resolver: { _ in HistoryResolvedSource(url: old, stale: true) }, startAccess: { _ in true }, stopAccess: { _ in })
        XCTAssertEqual(wrongResolution, .inaccessible)
        let deniedModel = WorkspaceModel(loadPackage: { _ in XCTFail("Replacement must not open"); return BoardDocument(name: "wrong") }, startAccess: { _ in true }, stopAccess: { _ in }, resolveHistory: { _ in HistoryResolvedSource(url: old, stale: true) }, history: owner)
        deniedModel.open(original)
        try await waitUntil { !deniedModel.isLoading }
        XCTAssertNotNil(deniedModel.historyAccessError)
        XCTAssertEqual(owner.entries.first { $0.id == original.id }?.openedCount, 2)
        model.relinkEntry = reopened
        model.relink(moved)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(owner.entries.first { $0.id == original.id }?.openedCount, 3)
        XCTAssertEqual(owner.entries.count, 2)
    }

    @MainActor
    func testSharedHistorySerializesInterleavedWindowsAndKeepsPresentationIndependent() async throws {
        let name = "TudorPCB.history-windows-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let owner = PackageHistoryOwner(defaults: defaults)
        func workspace() -> WorkspaceModel {
            WorkspaceModel(loadPackage: { BoardDocument(name: $0.lastPathComponent) },
                makeBookmark: { _ in Data([1]) }, history: owner)
        }
        let a = workspace(), b = workspace()
        a.open(URL(fileURLWithPath: "/A.gbr"))
        b.open(URL(fileURLWithPath: "/B.gbr"))
        try await waitUntil { !a.isLoading && !b.isLoading }
        XCTAssertEqual(Set(a.historyEntries.map(\.name)), ["A.gbr", "B.gbr"])
        XCTAssertEqual(a.historyEntries, b.historyEntries)
        let first = try XCTUnwrap(a.historyEntries.first { $0.name == "A.gbr" })
        a.removeFromHistory(first)
        b.open(URL(fileURLWithPath: "/C.gbr"))
        try await waitUntil { !b.isLoading }
        XCTAssertEqual(Set(a.historyEntries.map(\.name)), ["B.gbr", "C.gbr"])
        a.clearHistory()
        b.open(URL(fileURLWithPath: "/D.gbr"))
        try await waitUntil { !b.isLoading }
        XCTAssertEqual(a.historyEntries.map(\.name), ["D.gbr"])
        let original = try XCTUnwrap(a.historyEntries.first)
        a.open(URL(fileURLWithPath: "/D.gbr"))
        try await waitUntil { !a.isLoading }
        XCTAssertEqual(b.historyEntries[0].id, original.id)
        XCTAssertEqual(b.historyEntries[0].firstOpenedAt, original.firstOpenedAt)
        XCTAssertEqual(b.historyEntries[0].openedCount, 2)
        XCTAssertEqual(PackageHistoryStore.load(defaults: defaults).entries, a.historyEntries)
        // These are the per-scene observable values addressed by FocusedValues.
        a.isImporting = true
        b.isShowingHistory = true
        XCTAssertFalse(b.isImporting)
        XCTAssertFalse(a.isShowingHistory)
        XCTAssertEqual(a.document?.name, "D.gbr")
        XCTAssertEqual(b.document?.name, "D.gbr")
        for index in 0..<101 {
            owner.record(PackageHistoryEntry.capture(url: URL(fileURLWithPath: "/\(index).gbr"), document: BoardDocument(name: "\(index)")))
        }
        XCTAssertEqual(a.historyEntries.count, 100)
        XCTAssertEqual(a.historyEntries, b.historyEntries)
    }

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
    func testBookmarkFailuresRemainVisibleAndRequireReselection() async throws {
        var creations = 0
        let model = WorkspaceModel(loadPackage: { _ in BoardDocument(name: "opened") },
            startAccess: { _ in false }, makeBookmark: { _ in
                creations += 1
                throw CocoaError(.fileReadNoPermission)
            }, saveHistory: { _ in })
        model.clearHistory()
        model.open(URL(fileURLWithPath: "/outside/board.gbr"))
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.document?.name, "opened")
        XCTAssertNotNil(model.historyAccessError)
        XCTAssertEqual(creations, 1)
        let entry = try XCTUnwrap(model.historyEntries.first)
        XCTAssertNil(entry.bookmarkData)
        XCTAssertThrowsError(try PackageHistoryStore.resolve(entry))
        model.open(entry)
        try await waitUntil { !model.isLoading }
        XCTAssertNotNil(model.historyAccessError)
        XCTAssertEqual(model.relinkEntry?.id, entry.id)
        XCTAssertEqual(creations, 1)
        model.relink(URL(fileURLWithPath: "/reselected/board.gbr"))
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(creations, 2)
        var corrupt = entry
        corrupt.bookmarkData = Data([0, 1, 2])
        XCTAssertThrowsError(try PackageHistoryStore.resolve(corrupt))
        // No bookmark can be refreshed if scoped access was denied.
        model.open(URL(fileURLWithPath: entry.sourcePath), fromHistory: entry)
        XCTAssertEqual(creations, 2)
    }

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
        model.clearHistory()
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
        model.clearHistory()
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
        model.clearHistory()
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

extension AppSmokeTests {
    @MainActor
    func testCandidateChoiceAndHistoryReopenUseTheExactBoardSet() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, size) in [("a", 10), ("b", 20)] {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = "%FSLAX24Y24*%%MOMM*%%ADD10C,0.1*%D10*X0Y0D02*X\(size*10000)Y0D01*Y\(size*10000)D01*X0D01*Y0D01*M02*"
            try Data(source.utf8).write(to: directory.appending(path: "board.gko"))
        }
        let model = WorkspaceModel(saveHistory: { _ in })
        model.clearHistory()
        model.open(root)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.candidateChoices.count, 2)
        XCTAssertEqual(model.candidateChoices.compactMap(\.group), ["a", "b"])
        XCTAssertNil(model.document)
        XCTAssertNil(model.errorMessage)
        let choice = try XCTUnwrap(model.candidateChoices.first { $0.group == "b" })
        model.chooseCandidate(choice)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.document?.bounds.width, 20)
        XCTAssertTrue(model.candidateChoices.isEmpty)
        let entry = try XCTUnwrap(model.historyEntries.first)
        XCTAssertEqual(entry.sourceSelection, choice)
        model.open(entry)
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.document?.sourceSelection, choice)
        XCTAssertEqual(model.document?.bounds.width, 20)
        XCTAssertTrue(model.candidateChoices.isEmpty)
    }
}
