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
}

@MainActor
final class BoardRenderer {
    enum RendererError: Error, LocalizedError {
        case noCommandQueue
        case noShaderLibrary
        case noShaderFunction
        case bufferAllocation
        case meshCapacity
        var errorDescription: String? {
            switch self {
            case .noCommandQueue: "Could not create the Metal command queue."
            case .noShaderLibrary: "Could not load the board shader library."
            case .noShaderFunction: "The board shader functions are missing."
            case .bufferAllocation: "Could not allocate the complete board mesh buffers."
            case .meshCapacity: "The board mesh exceeds the supported geometry or GPU buffer capacity."
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
    private var topTexture: MTLTexture?
    private var bottomTexture: MTLTexture?
    private var maskTexture: MTLTexture?

    private var azimuth: Float = 0.58
    private var elevation: Float = 0.72
    private var distance: Float = 1.72
    private var targetDistance: Float = 1.72
    private var lastDocumentName: String?
    private var lastTextureIdentity: ObjectIdentifier?

    init(device: MTLDevice, colorPixelFormat: MTLPixelFormat, depthPixelFormat: MTLPixelFormat,
         bufferAllocator: ((UnsafeRawPointer, Int) -> MTLBuffer?)? = nil) throws {
        self.device = device
        self.allocateBuffer = bufferAllocator ?? { device.makeBuffer(bytes: $0, length: $1) }
        guard let queue = device.makeCommandQueue() else { throw RendererError.noCommandQueue }
        commandQueue = queue
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

    private(set) var geometryError: (any Error)?

    func update(document: BoardDocument?, textures: BoardTextureSet?) {
        guard let document, let textures else { return }
        let textureIdentity = ObjectIdentifier(textures.top)
        if lastDocumentName != document.name {
            do { try buildMesh(for: document); geometryError = nil }
            catch { geometryError = error; return }
            lastDocumentName = document.name
            apply(.perspective)
        }
        if lastTextureIdentity != textureIdentity {
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [
                .SRGB: true,
                .generateMipmaps: true,
                .origin: MTKTextureLoader.Origin.bottomLeft
            ]
            topTexture = try? loader.newTexture(cgImage: textures.top, options: options)
            bottomTexture = try? loader.newTexture(cgImage: textures.bottom, options: options)
            maskTexture = try? loader.newTexture(cgImage: textures.boardMask, options: options)
            lastTextureIdentity = textureIdentity
        }
    }

    func apply(_ preset: CameraPreset) {
        switch preset {
        case .perspective:
            azimuth = 0.58
            elevation = 0.72
            targetDistance = 1.72
        case .top:
            azimuth = 0
            elevation = .pi / 2 - 0.015
            targetDistance = 1.5
        case .bottom:
            azimuth = .pi
            elevation = -.pi / 2 + 0.015
            targetDistance = 1.5
        case .fit:
            targetDistance = 1.72
        }
    }

    func orbit(deltaX: Float, deltaY: Float) {
        azimuth -= deltaX * 0.008
        elevation = min(.pi / 2 - 0.025, max(-.pi / 2 + 0.025, elevation + deltaY * 0.008))
    }

    func zoom(delta: Float) {
        targetDistance = min(5.0, max(0.72, targetDistance * exp(delta * 0.004)))
    }

    func draw(in view: MTKView) {
        distance += (targetDistance - distance) * 0.16
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let vertexBuffer,
              let indexBuffer,
              let topTexture,
              let bottomTexture,
              let maskTexture,
              indexCount > 0,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
        let eye = SIMD3<Float>(
            cos(elevation) * sin(azimuth) * distance,
            sin(elevation) * distance,
            cos(elevation) * cos(azimuth) * distance
        )
        let up: SIMD3<Float> = abs(sin(elevation)) > 0.98
            ? SIMD3<Float>(0, 0, elevation > 0 ? -1 : 1)
            : SIMD3<Float>(0, 1, 0)
        let viewMatrix = lookAt(eye: eye, center: .zero, up: up)
        let projection = perspective(fovY: 42 * .pi / 180, aspect: aspect, near: 0.05, far: 20)
        var uniforms = Uniforms(
            model: matrix_identity_float4x4,
            viewProjection: projection * viewMatrix,
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
        commandBuffer.commit()
        lastCommandBuffer = commandBuffer
    }

    private func buildMesh(for document: BoardDocument) throws {
        try document.validateForRendering()
        let longest = Float(max(document.bounds.width, document.bounds.height, 0.001))
        let halfWidth = Float(document.bounds.width) / longest / 2
        let halfDepth = Float(document.bounds.height) / longest / 2
        let halfHeight = Float(document.thicknessMillimeters) / longest / 2
        let yTop = halfHeight
        let yBottom = -halfHeight

        let edgePaths = try BoardOutlineExtractor.edgePaths(in: document)
        let maximumVertices = GeometryLimits.meshVertices
        var faces = 2
        for path in edgePaths {
            let added = max(0, path.count - 1)
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
        for edgePath in edgePaths where edgePath.count >= 2 {
            for index in 0..<(edgePath.count - 1) {
                let p0 = worldPoint(edgePath[index])
                let p1 = worldPoint(edgePath[index + 1])
                let delta = p1 - p0
                guard simd_length(delta) > 0.000_001 else { continue }
                let normal = normalize(SIMD3<Float>(delta.z, 0, -delta.x))
                try face([
                    SIMD3(p0.x, yBottom, p0.z), SIMD3(p1.x, yBottom, p1.z),
                    SIMD3(p1.x, yTop, p1.z), SIMD3(p0.x, yTop, p0.z)
                ], normal: normal, material: 2, uv: edgeUV)
            }
        }

        let newVertices = vertices.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { allocateBuffer($0, bytes.count) }
        }
        let newIndices = indices.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { allocateBuffer($0, bytes.count) }
        }
        guard let newVertices, let newIndices else { throw RendererError.bufferAllocation }
        vertexBuffer = newVertices
        indexBuffer = newIndices
        indexCount = indices.count

        func worldPoint(_ point: Point2D) -> SIMD3<Float> {
            SIMD3<Float>(
                Float(point.x - document.bounds.minimum.x) / longest - halfWidth,
                0,
                halfDepth - Float(point.y - document.bounds.minimum.y) / longest
            )
        }
    }

    private func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY / 2)
        let x = y / max(aspect, 0.001)
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        return simd_float4x4(columns: (
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
}
