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
    var historyAccessError: String?
    var relinkEntry: PackageHistoryEntry?
    var candidateChoices: [FabricationSelection] = []
    private var candidateURL: URL?
    var visibleLayerIDs: Set<String> = []
    var maskStyle = BoardMaskStyle.green
    var showProofs = false
    var historyEntries: [PackageHistoryEntry]
    var historyError: String?
    private(set) var historyRecovery: HistoryRecovery?
    private var renderGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var proofTask: Task<BoardSidePreview, any Error>?
    private var proofGeneration = 0
    private var documentGeneration = 0
    private let readProof: @Sendable (URL, GerberSide) async throws -> BoardSidePreview
    private let loadPackage: @Sendable (URL) async throws -> BoardDocument
    private let loadSelection: @Sendable (URL, FabricationSelection) async throws -> BoardDocument
    private let renderBoard: @Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet
    private let makeBookmark: (URL) throws -> Data
    private let saveHistory: ([PackageHistoryEntry]) throws -> Void
    private let startAccess: (URL) -> Bool
    private let stopAccess: (URL) -> Void

    init(
        readProof: @escaping @Sendable (URL, GerberSide) async throws -> BoardSidePreview = {
            try await ProofImageDecoder.read($0, side: $1)
        },
        loadPackage: (@Sendable (URL) async throws -> BoardDocument)? = nil,
        loadSelection: (@Sendable (URL, FabricationSelection) async throws -> BoardDocument)? = nil,
        renderBoard: (@Sendable (BoardDocument, BoardRenderOptions) async throws -> BoardTextureSet)? = nil,
        startAccess: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        makeBookmark: @escaping (URL) throws -> Data = { try PackageHistoryStore.makeBookmark(for: $0) },
        saveHistory: @escaping ([PackageHistoryEntry]) throws -> Void = { try PackageHistoryStore.save($0) }
    ) {
        let history = PackageHistoryStore.load()
        self.historyEntries = history.entries
        self.historyRecovery = history.recovery
        self.historyError = history.recovery?.message
        self.readProof = readProof
        let worker = FabricationWorkSession()
        self.loadPackage = loadPackage ?? { try await worker.load($0) }
        self.loadSelection = loadSelection ?? { try await worker.load($0, selection: $1) }
        self.renderBoard = renderBoard ?? { try await worker.render($0, options: $1) }
        self.startAccess = startAccess
        self.stopAccess = stopAccess
        self.saveHistory = saveHistory
        self.makeBookmark = makeBookmark
    }

    func open(_ url: URL, selection: FabricationSelection? = nil, fromHistory: PackageHistoryEntry? = nil) {
        candidateChoices = []
        candidateURL = nil
        loadTask?.cancel()
        renderTask?.cancel()
        documentGeneration += 1
        let generation = documentGeneration
        // A replacement owns document identity; rendering options cannot cancel it.
        renderGeneration += 1
        proofTask?.cancel()
        proofGeneration += 1
        let hasAccess = startAccess(url)
        if fromHistory != nil && !hasAccess {
            phase = .idle
            relinkEntry = fromHistory
            historyAccessError = HistoryAccessError.reselectRequired(url.path).localizedDescription
            return
        }
        phase = .opening(url.lastPathComponent)
        errorMessage = nil
        let maskStyle = self.maskStyle
        loadTask = Task {
            defer { if hasAccess { stopAccess(url) } }
            do {
                try Task.checkCancellation()
                let next: BoardDocument
                if let selection { next = try await loadSelection(url, selection) }
                else { next = try await loadPackage(url) }
                guard generation == documentGeneration else { return }
                let visible = Set(next.layers.map(\.id))
                let rendered = try await renderBoard(next, BoardRenderOptions(visibleLayerIDs: visible, solderMaskColor: maskStyle.color))
                guard generation == documentGeneration else { return }
                try Task.checkCancellation()
                var historyEntry = PackageHistoryEntry.capture(url: url, document: next)
                do {
                    // A history URL holds scoped access here. Stale bookmarks
                    // are refreshed only after the package successfully opens.
                    historyEntry.bookmarkData = try makeBookmark(url)
                    historyAccessError = nil
                    relinkEntry = nil
                } catch {
                    historyAccessError = "The package opened, but persistent access could not be saved: \(error.localizedDescription) Reselect the source to retry."
                    relinkEntry = historyEntry
                }
                document = next
                textures = rendered
                visibleLayerIDs = visible
                historyEntries = PackageHistoryStore.merging(historyEntry, into: historyEntries)
                persistHistory()
                phase = .idle
                loadTask = nil
            } catch let error as FabricationSelectionRequired {
                guard generation == documentGeneration else { return }
                phase = .idle
                loadTask = nil
                candidateURL = url
                candidateChoices = error.candidates
            } catch is CancellationError { }
              catch {
                guard generation == documentGeneration else { return }
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseCandidate(_ selection: FabricationSelection) {
        guard candidateChoices.contains(selection), let url = candidateURL else { return }
        open(url, selection: selection)
    }

    func cancelCandidateSelection() { candidateChoices = []; candidateURL = nil }

    func open(_ entry: PackageHistoryEntry) {
        do {
            open(try PackageHistoryStore.resolve(entry), selection: entry.sourceSelection, fromHistory: entry)
        } catch {
            relinkEntry = entry
            historyAccessError = "Could not restore access to \(entry.sourcePath): \(error.localizedDescription) Reselect the source to relink it."
        }
    }

    func relink(_ url: URL) {
        let selection = relinkEntry?.sourceSelection
        historyAccessError = nil
        open(url, selection: selection)
    }

    func removeFromHistory(_ entry: PackageHistoryEntry) {
        historyEntries.removeAll { $0.id == entry.id }
        persistHistory()
    }

    func clearHistory() {
        historyEntries.removeAll()
        persistHistory()
    }

    private func persistHistory() {
        do {
            guard historyRecovery == nil else { throw HistoryStorageError.invalid(historyRecovery!.message) }
            try saveHistory(historyEntries)
        } catch { historyError = "History was not saved: \(error.localizedDescription)" }
    }

    func recoverHistory() {
        guard let recovery = historyRecovery else { return }
        do {
            try PackageHistoryStore.recover(historyEntries, original: recovery.original)
            historyRecovery = nil
            historyError = nil
        } catch { historyError = error.localizedDescription }
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
