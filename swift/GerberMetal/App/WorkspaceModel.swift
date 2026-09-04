import Foundation
import GerberKit
import Observation

enum BoardMaskStyle: String, CaseIterable, Identifiable {
    case green = "Green"
    case black = "Black"
    case blue = "Blue"
    case red = "Red"
    case white = "White"

    var id: Self { self }

    nonisolated var color: RGBAColor {
        switch self {
        case .green: .greenMask
        case .black: .blackMask
        case .blue: .blueMask
        case .red: .redMask
        case .white: .whiteMask
        }
    }
}

@MainActor
@Observable
final class WorkspaceModel {
    var document: BoardDocument?
    var textures: BoardTextureSet?
    var isLoading = false
    var errorMessage: String?
    var visibleLayerIDs: Set<String> = []
    var maskStyle = BoardMaskStyle.green
    var showProofs = false
    private var renderGeneration = 0

    func open(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        isLoading = true
        errorMessage = nil
        renderGeneration += 1
        let generation = renderGeneration
        let maskStyle = self.maskStyle

        Task {
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let document = try FabricationPackageLoader().load(from: url)
                    let visible = Set(document.layers.map(\.id))
                    let textures = try BoardRasterizer().render(
                        document,
                        options: BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskStyle.color)
                    )
                    return (document, textures, visible)
                }.value
                guard generation == renderGeneration else { return }
                document = result.0
                textures = result.1
                visibleLayerIDs = result.2
                isLoading = false
            } catch {
                guard generation == renderGeneration else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleLayer(_ layer: GerberLayer) {
        if visibleLayerIDs.contains(layer.id) {
            visibleLayerIDs.remove(layer.id)
        } else {
            visibleLayerIDs.insert(layer.id)
        }
        rerender()
    }

    func selectMask(_ style: BoardMaskStyle) {
        maskStyle = style
        rerender()
    }

    func attachColorProof(_ url: URL, side: GerberSide) {
        guard var document else { return }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            document.sidePreviews.removeAll { $0.side == side && $0.fileName.contains("attached-artwork") }
            document.sidePreviews.append(BoardSidePreview(
                side: side,
                fileName: "attached-artwork-\(side.rawValue)-side.\(url.pathExtension)",
                imageData: data
            ))
            self.document = document
            rerender()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rerender() {
        guard let document else { return }
        renderGeneration += 1
        let generation = renderGeneration
        let visible = visibleLayerIDs
        let maskColor = maskStyle.color
        isLoading = true
        Task {
            do {
                let rendered = try await Task.detached(priority: .userInitiated) {
                    try BoardRasterizer().render(
                        document,
                        options: BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskColor)
                    )
                }.value
                guard generation == renderGeneration else { return }
                textures = rendered
                isLoading = false
            } catch {
                guard generation == renderGeneration else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
