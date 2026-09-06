import GerberKit
import CoreGraphics
import simd

/// Camera geometry uses the same normalized millimeter bounds as the mesh.
struct BoardCamera {
    private(set) var azimuth: Float = 0.58
    private(set) var elevation: Float = 0.72
    private(set) var distance: Float = 1.72
    private(set) var targetDistance: Float = 1.72
    private(set) var halfExtents = SIMD3<Float>(0.5, 0.008, 0.5)
    private(set) var aspect: Float = 1
    private var isFitted = true
    private let fov: Float = 42 * .pi / 180
    private let near: Float = 0.05

    mutating func configure(_ document: BoardDocument) {
        let longest = Float(max(document.bounds.width, document.bounds.height, 0.001))
        halfExtents = SIMD3(Float(document.bounds.width), Float(document.thicknessMillimeters), Float(document.bounds.height)) / longest / 2
    }

    var corners: [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        for x: Float in [-1, 1] {
            for y: Float in [-1, 1] {
                for z: Float in [-1, 1] { result.append(halfExtents * SIMD3(x, y, z)) }
            }
        }
        return result
    }
    private var direction: SIMD3<Float> { SIMD3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth)) }
    private var up: SIMD3<Float> { abs(sin(elevation)) > 0.98 ? SIMD3(0, 0, elevation > 0 ? -1 : 1) : SIMD3(0, 1, 0) }
    private var fitDistance: Float {
        let z = direction, x = normalize(cross(up, direction))
        let y = cross(z, x), tangent = tan(fov / 2)
        return corners.reduce(near * 2) { result, p in
            let depth = dot(p, z)
            return max(result, depth + near * 2,
                       depth + 1.1 * abs(dot(p, x)) / (tangent * aspect),
                       depth + 1.1 * abs(dot(p, y)) / tangent)
        }
    }
    mutating func resize(_ size: CGSize) {
        let next = Float(max(size.width, 1) / max(size.height, 1))
        guard next != aspect else { return }
        aspect = max(next, 0.001)
        if isFitted { fit() }
    }
    private mutating func fit() { targetDistance = fitDistance; distance = targetDistance; isFitted = true }
    mutating func apply(_ preset: CameraPreset) {
        switch preset {
        case .perspective: azimuth = 0.58; elevation = 0.72
        case .top: azimuth = 0; elevation = .pi / 2 - 0.015
        case .bottom: azimuth = .pi; elevation = -.pi / 2 + 0.015
        case .fit: break
        }
        fit()
    }
    mutating func orbit(deltaX: Float, deltaY: Float) {
        azimuth -= deltaX * 0.008
        elevation = min(.pi / 2 - 0.025, max(-.pi / 2 + 0.025, elevation + deltaY * 0.008))
        isFitted = false
    }
    mutating func zoom(delta: Float) {
        guard delta.isFinite else { return }
        targetDistance = min(max(5, fitDistance * 4), max(near * 2, targetDistance * exp(delta * 0.004)))
        isFitted = false
    }
    var isAnimating: Bool { abs(targetDistance - distance) > max(0.00001, targetDistance * 0.0001) }
    mutating func advance() {
        distance += (targetDistance - distance) * 0.16
        if !isAnimating { distance = targetDistance }
    }
    var viewProjection: simd_float4x4 {
        perspective(fovY: fov, aspect: aspect, near: near, far: max(20, distance + length(halfExtents) * 2 + 1)) * lookAt(eye: direction * distance, center: .zero, up: up)
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
