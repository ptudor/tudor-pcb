import GerberKit
import MetalKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ViewerController {
    private(set) var cameraRevision = 0
    private(set) var retryRevision = 0
    var rendererError: String?
    var use2DFallback = false

    func retryRendering() {
        rendererError = nil
        use2DFallback = false
        retryRevision += 1
    }
    private(set) var cameraPreset = CameraPreset.perspective

    func show(_ preset: CameraPreset) {
        cameraPreset = preset
        cameraRevision += 1
    }
}

struct MetalBoardView {
    var document: BoardDocument?
    var textures: BoardTextureSet?
    var controller: ViewerController

    @MainActor
    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    fileprivate func makeMetalView(_ coordinator: Coordinator) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.018, green: 0.024, blue: 0.031, alpha: 1)
        view.clearDepth = 1
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.interactionDelegate = coordinator
        coordinator.configure(view: view)
        sync(coordinator)
        return view
    }

    @MainActor
    fileprivate func sync(_ coordinator: Coordinator) {
        if let renderer = coordinator.renderer {
            renderer.update(document: document, textures: textures)
            coordinator.report(renderer.renderError?.localizedDescription)
        }
        if coordinator.cameraRevision != controller.cameraRevision {
            coordinator.renderer?.apply(controller.cameraPreset)
            coordinator.cameraRevision = controller.cameraRevision
        }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate, BoardInteractionDelegate {
        var renderer: BoardRenderer?
        var cameraRevision = -1
        let controller: ViewerController
        private var reportRevision = 0
        private let makeRenderer: (MTLDevice, MTLPixelFormat, MTLPixelFormat) throws -> BoardRenderer
        init(controller: ViewerController, makeRenderer: @escaping (MTLDevice, MTLPixelFormat, MTLPixelFormat) throws -> BoardRenderer = {
            try BoardRenderer(device: $0, colorPixelFormat: $1, depthPixelFormat: $2)
        }) {
            self.controller = controller
            self.makeRenderer = makeRenderer
        }

        func report(_ error: String?) {
            reportRevision += 1
            let revision = reportRevision
            Task { @MainActor in
                guard revision == reportRevision else { return }
                if controller.rendererError != error { controller.rendererError = error }
            }
        }

        func configure(view: MTKView) {
            guard let device = view.device else { report(BoardRenderer.RendererError.noDevice.localizedDescription); return }
            renderer = nil
            do {
                renderer = try makeRenderer(device, view.colorPixelFormat, view.depthStencilPixelFormat)
                renderer?.onError = { [weak self] in self?.report($0) }
                report(nil)
            } catch { report(error.localizedDescription) }
            view.delegate = self
        }

        func draw(in view: MTKView) {
            renderer?.draw(in: view)
            if let error = renderer?.renderError { report(error.localizedDescription) }
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
        func orbit(deltaX: Float, deltaY: Float) { renderer?.orbit(deltaX: deltaX, deltaY: deltaY) }
        func zoom(delta: Float) { renderer?.zoom(delta: delta) }
        func fitCamera() { renderer?.apply(.fit) }
    }
}

#if os(macOS)
extension MetalBoardView: NSViewRepresentable {
    func makeNSView(context: Context) -> InteractiveMTKView { makeMetalView(context.coordinator) }
    func updateNSView(_ view: InteractiveMTKView, context: Context) { sync(context.coordinator) }
}

final class InteractiveMTKView: MTKView {
    @MainActor weak var interactionDelegate: BoardInteractionDelegate?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        interactionDelegate?.orbit(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func rightMouseDragged(with event: NSEvent) {
        interactionDelegate?.orbit(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        interactionDelegate?.zoom(delta: Float(event.scrollingDeltaY))
    }

    override func magnify(with event: NSEvent) {
        interactionDelegate?.zoom(delta: Float(-event.magnification * 220))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { interactionDelegate?.fitCamera() }
        super.mouseDown(with: event)
    }
}
#else
extension MetalBoardView: UIViewRepresentable {
    func makeUIView(context: Context) -> InteractiveMTKView { makeMetalView(context.coordinator) }
    func updateUIView(_ view: InteractiveMTKView, context: Context) { sync(context.coordinator) }
}

final class InteractiveMTKView: MTKView {
    @MainActor weak var interactionDelegate: BoardInteractionDelegate?
    private var previousTouch: CGPoint?
    private var startingPinchDistance: CGFloat?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        previousTouch = touches.first?.location(in: self)
        startingPinchDistance = distance(between: touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count >= 2, let previous = startingPinchDistance, let current = distance(between: touches) {
            interactionDelegate?.zoom(delta: Float((previous - current) * 0.8))
            startingPinchDistance = current
        } else if let current = touches.first?.location(in: self), let previousTouch {
            interactionDelegate?.orbit(
                deltaX: Float(current.x - previousTouch.x),
                deltaY: Float(previousTouch.y - current.y)
            )
            self.previousTouch = current
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        previousTouch = nil
        startingPinchDistance = nil
    }

    private func distance(between touches: Set<UITouch>) -> CGFloat? {
        let points = touches.prefix(2).map { $0.location(in: self) }
        guard points.count == 2 else { return nil }
        return hypot(points[0].x - points[1].x, points[0].y - points[1].y)
    }
}
#endif
