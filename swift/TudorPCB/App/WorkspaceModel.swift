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
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var proofTask: Task<BoardSidePreview, any Error>?
    private var proofGeneration = 0
    private var documentGeneration = 0
    private let readProof: @Sendable (URL, GerberSide) async throws -> BoardSidePreview
    private let loadPackage: @Sendable (URL) async throws -> BoardDocument
    private let renderBoard: @Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet
    private let saveHistory: ([PackageHistoryEntry]) -> Void
    private let startAccess: (URL) -> Bool
    private let stopAccess: (URL) -> Void

    init(
        readProof: @escaping @Sendable (URL, GerberSide) async throws -> BoardSidePreview = {
            try await ProofImageDecoder.read($0, side: $1)
        },
        loadPackage: (@Sendable (URL) async throws -> BoardDocument)? = nil,
        renderBoard: (@Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet)? = nil,
        startAccess: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        saveHistory: @escaping ([PackageHistoryEntry]) -> Void = { PackageHistoryStore.save($0) }
    ) {
        self.readProof = readProof
        let worker = FabricationWorkSession()
        self.loadPackage = loadPackage ?? { try await worker.load($0) }
        self.renderBoard = renderBoard ?? { try await worker.render($0, options: $1) }
        self.startAccess = startAccess
        self.stopAccess = stopAccess
        self.saveHistory = saveHistory
    }

    func open(_ url: URL) {
        loadTask?.cancel()
        renderTask?.cancel()
        documentGeneration += 1
        let generation = documentGeneration
        // A replacement owns document identity; rendering options cannot cancel it.
        renderGeneration += 1
        proofTask?.cancel()
        proofGeneration += 1
        let hasAccess = startAccess(url)
        phase = .opening(url.lastPathComponent)
        errorMessage = nil
        let maskStyle = self.maskStyle
        loadTask = Task {
            defer { if hasAccess { stopAccess(url) } }
            do {
                try Task.checkCancellation()
                let next = try await loadPackage(url)
                guard generation == documentGeneration else { return }
                let visible = Set(next.layers.map(\.id))
                let rendered = try await renderBoard(next, BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskStyle.color))
                guard generation == documentGeneration else { return }
                try Task.checkCancellation()
                let historyEntry = PackageHistoryEntry.capture(url: url, document: next)
                document = next
                textures = rendered
                visibleLayerIDs = visible
                historyEntries = PackageHistoryStore.merging(historyEntry, into: historyEntries)
                saveHistory(historyEntries)
                phase = .idle
                loadTask = nil
            } catch is CancellationError { }
              catch {
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
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let visible = visibleLayerIDs
        let maskColor = maskStyle.color
        phase = .rendering
        renderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(35))
                try Task.checkCancellation()
                let rendered = try await renderBoard(document, BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskColor))
                guard generation == renderGeneration else { return }
                try Task.checkCancellation()
                textures = rendered
                phase = .idle
                renderTask = nil
            } catch is CancellationError { }
              catch {
                guard generation == renderGeneration else { return }
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }
}
