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
    var historyEntries: [PackageHistoryEntry] = PackageHistoryStore.load()
    private var renderGeneration = 0
    private var proofTask: Task<BoardSidePreview, any Error>?
    private var proofGeneration = 0
    private var documentGeneration = 0
    private let readProof: @Sendable (URL, GerberSide) async throws -> BoardSidePreview

    init(readProof: @escaping @Sendable (URL, GerberSide) async throws -> BoardSidePreview = {
        try await ProofImageDecoder.read($0, side: $1)
    }) { self.readProof = readProof }

    func open(_ url: URL) {
        documentGeneration += 1
        proofTask?.cancel()
        proofGeneration += 1
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
                    let historyEntry = PackageHistoryEntry.capture(url: url, document: document)
                    return (document, textures, visible, historyEntry)
                }.value
                guard generation == renderGeneration else { return }
                document = result.0
                textures = result.1
                visibleLayerIDs = result.2
                historyEntries = PackageHistoryStore.merging(result.3, into: historyEntries)
                PackageHistoryStore.save(historyEntries)
                isLoading = false
            } catch {
                guard generation == renderGeneration else { return }
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func open(_ entry: PackageHistoryEntry) {
        do {
            open(try PackageHistoryStore.resolve(entry))
        } catch {
            errorMessage = "The original package could not be reopened. It may have moved or no longer be available."
        }
    }

    func removeFromHistory(_ entry: PackageHistoryEntry) {
        historyEntries.removeAll { $0.id == entry.id }
        PackageHistoryStore.save(historyEntries)
    }

    func clearHistory() {
        historyEntries.removeAll()
        PackageHistoryStore.save(historyEntries)
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
        guard document != nil else { return }
        proofTask?.cancel()
        proofGeneration += 1
        let generation = proofGeneration
        let documentIdentity = documentGeneration
        let readProof = self.readProof
        let task = Task { try await readProof(url, side) }
        proofTask = task
        Task {
            do {
                var preview = try await task.value
                guard generation == proofGeneration, documentIdentity == documentGeneration, var document else { return }
                preview.fileName = "attached-artwork-\(side.rawValue)-side.\(url.pathExtension)"
                document.sidePreviews.removeAll { $0.side == side && $0.fileName.contains("attached-artwork") }
                document.sidePreviews.append(preview)
                self.document = document
                proofTask = nil
                rerender()
            } catch is CancellationError { }
              catch {
                guard generation == proofGeneration, documentIdentity == documentGeneration else { return }
                proofTask = nil
                errorMessage = error.localizedDescription
            }
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
