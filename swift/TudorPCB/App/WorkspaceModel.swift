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

enum WorkspacePhase: Equatable {
    case idle
    case opening(String)
    case rendering
}

@MainActor
@Observable
final class WorkspaceModel {
    var document: BoardDocument?
    var textures: BoardTextureSet?
    private(set) var phase = WorkspacePhase.idle
    var isLoading: Bool { phase != .idle }
    var isOpening: Bool { if case .opening = phase { true } else { false } }
    var pendingFileName: String? { if case let .opening(name) = phase { name } else { nil } }
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
    private let loadPackage: @Sendable (URL) async throws -> BoardDocument
    private let renderBoard: @Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet
    private let saveHistory: ([PackageHistoryEntry]) -> Void

    init(
        readProof: @escaping @Sendable (URL, GerberSide) async throws -> BoardSidePreview = {
            try await ProofImageDecoder.read($0, side: $1)
        },
        loadPackage: @escaping @Sendable (URL) async throws -> BoardDocument = { url in
            try await Task.detached(priority: .userInitiated) { try FabricationPackageLoader().load(from: url) }.value
        },
        renderBoard: @escaping @Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet = { document, options in
            try await Task.detached(priority: .userInitiated) { try BoardRasterizer().render(document, options: options) }.value
        },
        saveHistory: @escaping ([PackageHistoryEntry]) -> Void = { PackageHistoryStore.save($0) }
    ) {
        self.readProof = readProof
        self.loadPackage = loadPackage
        self.renderBoard = renderBoard
        self.saveHistory = saveHistory
    }

    func open(_ url: URL) {
        documentGeneration += 1
        let generation = documentGeneration
        // A replacement owns document identity; rendering options cannot cancel it.
        renderGeneration += 1
        proofTask?.cancel()
        proofGeneration += 1
        let hasAccess = url.startAccessingSecurityScopedResource()
        phase = .opening(url.lastPathComponent)
        errorMessage = nil
        let maskStyle = self.maskStyle
        Task {
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let next = try await loadPackage(url)
                guard generation == documentGeneration else { return }
                let visible = Set(next.layers.map(\.id))
                let rendered = try await renderBoard(next, BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskStyle.color))
                guard generation == documentGeneration else { return }
                let historyEntry = PackageHistoryEntry.capture(url: url, document: next)
                document = next
                textures = rendered
                visibleLayerIDs = visible
                historyEntries = PackageHistoryStore.merging(historyEntry, into: historyEntries)
                saveHistory(historyEntries)
                phase = .idle
            } catch {
                guard generation == documentGeneration else { return }
                phase = .idle
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
        saveHistory(historyEntries)
    }

    func clearHistory() {
        historyEntries.removeAll()
        saveHistory(historyEntries)
    }

    func toggleLayer(_ layer: GerberLayer) {
        guard !isOpening else { return }
        if visibleLayerIDs.contains(layer.id) {
            visibleLayerIDs.remove(layer.id)
        } else {
            visibleLayerIDs.insert(layer.id)
        }
        rerender()
    }

    func selectMask(_ style: BoardMaskStyle) {
        guard !isOpening else { return }
        maskStyle = style
        rerender()
    }

    func attachColorProof(_ url: URL, side: GerberSide) {
        guard document != nil, !isOpening else { return }
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
        guard let document, !isOpening else { return }
        renderGeneration += 1
        let generation = renderGeneration
        let visible = visibleLayerIDs
        let maskColor = maskStyle.color
        phase = .rendering
        Task {
            do {
                let rendered = try await renderBoard(document, BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskColor))
                guard generation == renderGeneration else { return }
                textures = rendered
                phase = .idle
            } catch {
                guard generation == renderGeneration else { return }
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }
}
