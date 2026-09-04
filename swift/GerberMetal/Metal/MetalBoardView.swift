import MetalKit
import SwiftUI

#if os(macOS)
struct MetalBoardView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        makeView()
    }

    func updateNSView(_ view: MTKView, context: Context) { }
}
#else
struct MetalBoardView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        makeView()
    }

    func updateUIView(_ view: MTKView, context: Context) { }
}
#endif

private func makeView() -> MTKView {
    let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    view.colorPixelFormat = .bgra8Unorm_srgb
    view.depthStencilPixelFormat = .depth32Float
    view.clearColor = MTLClearColor(red: 0.025, green: 0.032, blue: 0.04, alpha: 1)
    view.preferredFramesPerSecond = 60
    view.enableSetNeedsDisplay = false
    view.isPaused = false
    return view
}

