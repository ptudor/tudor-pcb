import GerberKit
import MetalKit
import simd

enum CameraPreset: Sendable {
    case perspective
    case top
    case bottom
    case fit
}

@MainActor
protocol BoardInteractionDelegate: AnyObject {
    func orbit(deltaX: Float, deltaY: Float)
    func zoom(delta: Float)
    func fitCamera()
    func visibilityChanged()
}

@MainActor
final class BoardRenderer {
    enum AllocationStage: CaseIterable { case library, pipeline, topTexture, bottomTexture, maskTexture, vertexBuffer, indexBuffer }

    enum RendererError: Error, LocalizedError {
        case noDevice
        case noCommandQueue
        case noShaderLibrary
        case noShaderFunction
        case bufferAllocation
        case meshCapacity
        case commandEncoding
        var errorDescription: String? {
            switch self {
            case .noDevice: String(localized: ErrorStrings.noMetalDevice)
            case .noCommandQueue: String(localized: ErrorStrings.noCommandQueue)
            case .noShaderLibrary: String(localized: ErrorStrings.noShaderLibrary)
            case .noShaderFunction: String(localized: ErrorStrings.noShaderFunction)
            case .bufferAllocation: String(localized: ErrorStrings.bufferAllocation)
            case .commandEncoding: String(localized: ErrorStrings.commandEncoding)
            case .meshCapacity: String(localized: ErrorStrings.meshCapacity)
            }
        }
    }

    struct BoardVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
        var material: UInt32
        var padding: UInt32 = 0
    }

    private struct Uniforms {
        var model: simd_float4x4
        var viewProjection: simd_float4x4
        var lightDirection: SIMD4<Float>
    }

    private let beforeAllocation: (AllocationStage) throws -> Void
    private let allocateBuffer: (UnsafeRawPointer, Int) -> MTLBuffer?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private(set) var vertexBuffer: MTLBuffer?
    private(set) var indexBuffer: MTLBuffer?
    private(set) var indexCount = 0
    private(set) var lastCommandBuffer: MTLCommandBuffer?
    private(set) var topTexture: MTLTexture?
    private(set) var bottomTexture: MTLTexture?
    private(set) var maskTexture: MTLTexture?

    private(set) var camera = BoardCamera()
    private(set) var contentRevision = 0
    private(set) var renderedFrameCount = 0
    var isAnimating: Bool { camera.isAnimating }
    private struct MeshIdentity: Equatable {
        let bounds: Bounds2D
        let thickness: Double
        let outlines: [[GerberPrimitive]]
        let drills: [DrillHit]
        init(_ document: BoardDocument) {
            bounds = document.bounds
            thickness = document.thicknessMillimeters
            outlines = document.layers.filter { $0.kind == .outline }.map(\.primitives)
            drills = document.drills
        }
    }
    private var lastMeshIdentity: MeshIdentity?
    private struct TextureIdentity: Equatable {
        let top: ObjectIdentifier
        let bottom: ObjectIdentifier
        let mask: ObjectIdentifier
        init(_ textures: BoardTextureSet) {
            top = ObjectIdentifier(textures.top); bottom = ObjectIdentifier(textures.bottom); mask = ObjectIdentifier(textures.boardMask)
        }
    }
    private var lastTextureIdentity: TextureIdentity?
    private(set) var hasCurrentResources = false
    private var updateRevision = 0
    var onError: ((String) -> Void)?

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat, depthPixelFormat: MTLPixelFormat,
         bufferAllocator: ((UnsafeRawPointer, Int) -> MTLBuffer?)? = nil,
         beforeAllocation: @escaping (AllocationStage) throws -> Void = { _ in }) throws {
        self.beforeAllocation = beforeAllocation
        self.device = device
        self.allocateBuffer = bufferAllocator ?? { device.makeBuffer(bytes: $0, length: $1) }
        guard let queue = device.makeCommandQueue() else { throw RendererError.noCommandQueue }
        commandQueue = queue
        try beforeAllocation(.library)
        guard let library = device.makeDefaultLibrary() else { throw RendererError.noShaderLibrary }
        guard let vertex = library.makeFunction(name: "board_vertex"),
              let fragment = library.makeFunction(name: "board_fragment") else {
            throw RendererError.noShaderFunction
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Gerber board surface"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
        try beforeAllocation(.pipeline)
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.bufferAllocation
        }
        depthState = depth

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.maxAnisotropy = 8
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.bufferAllocation
        }
        self.sampler = sampler
    }

    private(set) var renderError: (any Error)?
    var geometryError: (any Error)? { renderError }

    @discardableResult
    func update(document: BoardDocument?, textures: BoardTextureSet?) -> Bool {
        guard let document, let textures else {
            updateRevision += 1; contentRevision += 1
            vertexBuffer = nil; indexBuffer = nil; indexCount = 0
            topTexture = nil; bottomTexture = nil; maskTexture = nil
            lastMeshIdentity = nil; lastTextureIdentity = nil
            hasCurrentResources = false; renderError = nil
            return true
        }
        let textureIdentity = TextureIdentity(textures)
        let meshIdentity = MeshIdentity(document)
        if hasCurrentResources, lastMeshIdentity == meshIdentity, lastTextureIdentity == textureIdentity { return true }
        updateRevision += 1; contentRevision += 1
        do {
            let meshChanged = lastMeshIdentity != meshIdentity
            let nextMesh = meshChanged ? try buildMesh(for: document) : nil
            var nextTop = topTexture, nextBottom = bottomTexture, nextMask = maskTexture
            if lastTextureIdentity != textureIdentity {
                let loader = MTKTextureLoader(device: device)
                let options: [MTKTextureLoader.Option: Any] = [
                    .SRGB: true, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.bottomLeft
                ]
                try beforeAllocation(.topTexture)
                nextTop = try loader.newTexture(cgImage: textures.top, options: options)
                try beforeAllocation(.bottomTexture)
                nextBottom = try loader.newTexture(cgImage: textures.bottom, options: options)
                try beforeAllocation(.maskTexture)
                nextMask = try loader.newTexture(cgImage: textures.boardMask, options: options)
            }
            guard let nextTop, let nextBottom, let nextMask,
                  nextMesh != nil || (vertexBuffer != nil && indexBuffer != nil) else { throw RendererError.bufferAllocation }
            // Publish a complete matching mesh/texture set and only then advance caches.
            if let nextMesh { vertexBuffer = nextMesh.0; indexBuffer = nextMesh.1; indexCount = nextMesh.2 }
            topTexture = nextTop; bottomTexture = nextBottom; maskTexture = nextMask
            lastMeshIdentity = meshIdentity; lastTextureIdentity = textureIdentity
            renderError = nil; hasCurrentResources = true
            if meshChanged { camera.configure(document); apply(.perspective) } // Texture-only updates preserve the camera.
            return true
        } catch {
            renderError = error
            hasCurrentResources = false
            onError?(error.localizedDescription)
            return false
        }
    }

    func apply(_ preset: CameraPreset) { camera.apply(preset) }
    func resize(_ size: CGSize) { camera.resize(size) }
    func orbit(deltaX: Float, deltaY: Float) { camera.orbit(deltaX: deltaX, deltaY: deltaY) }
    func zoom(delta: Float) { camera.zoom(delta: delta) }

    func draw(in view: MTKView) {
        guard hasCurrentResources else { return }
        camera.resize(view.drawableSize)
        camera.advance()
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let vertexBuffer,
              let indexBuffer,
              let topTexture,
              let bottomTexture,
              let maskTexture,
              indexCount > 0 else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            renderError = RendererError.commandEncoding
            hasCurrentResources = false
            return
        }

        var uniforms = Uniforms(
            model: matrix_identity_float4x4,
            viewProjection: camera.viewProjection,
            lightDirection: SIMD4<Float>(0.35, 0.82, 0.48, 0)
        )

        encoder.label = "Draw fabrication board"
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(topTexture, index: 0)
        encoder.setFragmentTexture(bottomTexture, index: 1)
        encoder.setFragmentTexture(maskTexture, index: 2)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        let revision = updateRevision
        commandBuffer.addCompletedHandler { [weak self] completed in
            guard let error = completed.error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.updateRevision == revision else { return }
                self.renderError = error
                self.hasCurrentResources = false
                self.onError?(error.localizedDescription)
            }
        }
        commandBuffer.commit()
        renderedFrameCount += 1
        lastCommandBuffer = commandBuffer
    }

    private func buildMesh(for document: BoardDocument) throws -> (MTLBuffer, MTLBuffer, Int) {
        try document.validateForRendering()
        let longest = Float(max(document.bounds.width, document.bounds.height, 0.001))
        let halfWidth = Float(document.bounds.width) / longest / 2
        let halfDepth = Float(document.bounds.height) / longest / 2
        let halfHeight = Float(document.thicknessMillimeters) / longest / 2
        let yTop = halfHeight
        let yBottom = -halfHeight

        let wallPaths = try BoardMachiningExtractor.wallPaths(in: document)
        let maximumVertices = GeometryLimits.meshVertices
        var faces = 2
        for path in wallPaths {
            let added = max(0, path.points.count - 1)
            guard added <= maximumVertices / 4 - faces else { throw RendererError.meshCapacity }
            faces += added
        }
        let plannedVertices = faces * 4
        let plannedIndices = faces * 6
        guard plannedVertices <= Int(UInt32.max),
              plannedVertices <= device.maxBufferLength / MemoryLayout<BoardVertex>.stride,
              plannedIndices <= device.maxBufferLength / MemoryLayout<UInt32>.stride else { throw RendererError.meshCapacity }
        var vertices: [BoardVertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity(plannedVertices)
        indices.reserveCapacity(plannedIndices)
        func face(_ positions: [SIMD3<Float>], normal: SIMD3<Float>, material: UInt32, uv: [SIMD2<Float>]) throws {
            guard vertices.count <= maximumVertices - 4, let base = UInt32(exactly: vertices.count), base <= UInt32.max - 3 else {
                throw RendererError.meshCapacity
            }
            for index in 0..<4 {
                vertices.append(BoardVertex(position: positions[index], normal: normal, uv: uv[index], material: material))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        let standardUV = [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)]
        try face([
            SIMD3(-halfWidth, yTop, halfDepth), SIMD3(halfWidth, yTop, halfDepth),
            SIMD3(halfWidth, yTop, -halfDepth), SIMD3(-halfWidth, yTop, -halfDepth)
        ], normal: SIMD3(0, 1, 0), material: 0, uv: standardUV)
        try face([
            SIMD3(halfWidth, yBottom, halfDepth), SIMD3(-halfWidth, yBottom, halfDepth),
            SIMD3(-halfWidth, yBottom, -halfDepth), SIMD3(halfWidth, yBottom, -halfDepth)
        ], normal: SIMD3(0, -1, 0), material: 1, uv: [
            // Keep UVs in board coordinates. Orbiting underneath performs the
            // physical flip; mirroring here as well makes bottom text backward.
            SIMD2<Float>(1, 0), SIMD2<Float>(0, 0),
            SIMD2<Float>(0, 1), SIMD2<Float>(1, 1)
        ])

        let edgeUV = Array(repeating: SIMD2<Float>(0.5, 0.5), count: 4)
        for wallPath in wallPaths where wallPath.points.count >= 2 {
            let edgePath = wallPath.points
            for index in 0..<(edgePath.count - 1) {
                let p0 = worldPoint(edgePath[index])
                let p1 = worldPoint(edgePath[index + 1])
                let delta = p1 - p0
                guard simd_length(delta) > 0.000_001 else { continue }
                let normal = normalize(SIMD3<Float>(-delta.z, 0, delta.x))
                try face([
                    SIMD3(p0.x, yBottom, p0.z), SIMD3(p1.x, yBottom, p1.z),
                    SIMD3(p1.x, yTop, p1.z), SIMD3(p0.x, yTop, p0.z)
                ], normal: normal, material: wallPath.plated ? 3 : 2, uv: edgeUV)
            }
        }

        try beforeAllocation(.vertexBuffer)
        let newVertices = vertices.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { allocateBuffer($0, bytes.count) }
        }
        try beforeAllocation(.indexBuffer)
        let newIndices = indices.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { allocateBuffer($0, bytes.count) }
        }
        guard let newVertices, let newIndices else { throw RendererError.bufferAllocation }
        return (newVertices, newIndices, indices.count)

        func worldPoint(_ point: Point2D) -> SIMD3<Float> {
            SIMD3<Float>(
                Float(point.x - document.bounds.minimum.x) / longest - halfWidth,
                0,
                halfDepth - Float(point.y - document.bounds.minimum.y) / longest
            )
        }
    }

}
