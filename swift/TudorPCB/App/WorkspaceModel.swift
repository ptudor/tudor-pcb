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
    let history: PackageHistoryOwner
    var historyEntries: [PackageHistoryEntry] { history.entries }
    var historyError: String? { get { history.error } set { history.error = newValue } }
    var historyRecovery: HistoryRecovery? { history.recovery }
    var isImporting = false
    var isShowingHistory = false
    private var renderGeneration = 0
    private var currentHistoryEntryID: UUID?
    private var historyResolutionTask: Task<HistoryResolvedSource, any Error>?
    private var historyResolutionRevision = 0
    private let resolveHistory: @Sendable (PackageHistoryEntry) throws -> HistoryResolvedSource
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
        resolveHistory: @escaping @Sendable (PackageHistoryEntry) throws -> HistoryResolvedSource = { try PackageHistoryStore.resolved($0) },
        history: PackageHistoryOwner? = nil,
        saveHistory: (([PackageHistoryEntry]) throws -> Void)? = nil
    ) {
        self.history = history ?? (saveHistory.map { PackageHistoryOwner(writer: $0) } ?? .shared)
        self.resolveHistory = resolveHistory
        self.readProof = readProof
        let worker = FabricationWorkSession()
        self.loadPackage = loadPackage ?? { try await worker.load($0) }
        self.loadSelection = loadSelection ?? { try await worker.load($0, selection: $1) }
        self.renderBoard = renderBoard ?? { try await worker.render($0, options: $1) }
        self.startAccess = startAccess
        self.stopAccess = stopAccess
        self.makeBookmark = makeBookmark
    }

    func open(_ url: URL, selection: FabricationSelection? = nil, fromHistory: PackageHistoryEntry? = nil, relinking: PackageHistoryEntry? = nil) {
        historyResolutionTask?.cancel()
        historyResolutionRevision += 1
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
                if let fromHistory {
                    try await Task.detached { try PackageHistoryStore.validateResolvedIdentity(fromHistory, at: url) }.value
                }
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
                    relinkEntry = fromHistory ?? relinking ?? historyEntry
                }
                document = next
                textures = rendered
                visibleLayerIDs = visible
                currentHistoryEntryID = history.record(historyEntry, reopening: fromHistory ?? relinking)
                phase = .idle
                loadTask = nil
            } catch let error as HistoryAccessError {
                guard generation == documentGeneration else { return }
                phase = .idle
                relinkEntry = fromHistory
                historyAccessError = error.localizedDescription
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
        historyResolutionTask?.cancel()
        historyResolutionRevision += 1
        let revision = historyResolutionRevision
        loadTask?.cancel(); renderTask?.cancel(); proofTask?.cancel()
        documentGeneration += 1; renderGeneration += 1; proofGeneration += 1
        phase = .opening(entry.name)
        let resolver = resolveHistory
        let task = Task.detached { try Task.checkCancellation(); return try resolver(entry) }
        historyResolutionTask = task
        Task {
            do {
                let source = try await task.value
                guard revision == historyResolutionRevision else { return }
                open(source.url, selection: entry.sourceSelection, fromHistory: entry)
            } catch {
                guard revision == historyResolutionRevision else { return }
                phase = .idle
                relinkEntry = entry
                historyAccessError = "Could not restore access to \(entry.sourcePath): \(error.localizedDescription) Reselect the source to relink it."
            }
        }
    }

    func relink(_ url: URL) {
        let entry = relinkEntry
        historyAccessError = nil
        open(url, selection: entry?.sourceSelection, relinking: entry)
    }

    func removeFromHistory(_ entry: PackageHistoryEntry) { history.remove(entry.id) }
    func clearHistory() { history.clear() }
    func recoverHistory() { history.recover() }

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

    func attachColorProof(_ url: URL, side: GerberSide, mapping: BoardArtworkMapping? = nil) {
        guard document != nil, !isOpening else { return }
        proofTask?.cancel()
        proofGeneration += 1
        let generation = proofGeneration
        let documentIdentity = documentGeneration
        let readProof = self.readProof
        phase = .rendering
        let task = Task { try await Self.validatedProof(try await readProof(url, side)) }
        proofTask = task
        Task {
            do {
                var preview = try await task.value
                guard generation == proofGeneration, documentIdentity == documentGeneration, var document else { return }
                preview.fileName = url.lastPathComponent
                try mapping?.validate()
                preview.purpose = mapping == nil ? .galleryProof : .boardArtwork
                preview.mapping = mapping
                preview.provenance = .attached
                document.sidePreviews.removeAll { $0.side == side && $0.provenance == .attached && (mapping != nil || $0.mapping == nil) }
                document.sidePreviews.append(preview)
                if mapping != nil { document.activeArtworkIDs[side] = preview.id }
                proofTask = nil
                if mapping == nil { showProofs = true }
                publishProofDocument(document)
            } catch is CancellationError { }
              catch {
                guard generation == proofGeneration, documentIdentity == documentGeneration else { return }
                proofTask = nil
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    private nonisolated static func validatedProof(_ preview: BoardSidePreview) async throws -> BoardSidePreview {
        guard preview.validatedImage == nil else { return preview }
        let task = Task.detached {
            var result = preview
            result.validatedImage = try ProofImageDecoder.decode(preview.imageData, name: preview.fileName)
            return result
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func publishProofDocument(_ source: BoardDocument) {
        var document = source
        document.refreshProofWarnings()
        self.document = document
        if let id = currentHistoryEntryID { history.updateInspection(id, document: document) }
        rerender()
    }

    func mapArtwork(_ preview: BoardSidePreview, mapping: BoardArtworkMapping, resetToSupplied: Bool = false) {
        guard !isOpening, document?.sidePreviews.contains(where: { $0.id == preview.id }) == true else { return }
        do { try mapping.validate() } catch { errorMessage = error.localizedDescription; return }
        proofTask?.cancel(); proofGeneration += 1
        let generation = proofGeneration, identity = documentGeneration
        phase = .rendering
        let task = Task { try await Self.validatedProof(preview) }
        proofTask = task
        Task {
            do {
                var validated = try await task.value
                guard generation == proofGeneration, identity == documentGeneration, var document,
                      let index = document.sidePreviews.firstIndex(where: { $0.id == preview.id }) else { return }
                validated.mapping = mapping; validated.purpose = .boardArtwork
                document.sidePreviews[index] = validated
                if resetToSupplied { document.activeArtworkIDs.removeValue(forKey: preview.side) }
                else { document.activeArtworkIDs[preview.side] = preview.id }
                if validated.provenance == .attached {
                    document.sidePreviews.removeAll { $0.side == preview.side && $0.provenance == .attached && $0.id != preview.id && $0.mapping != nil }
                }
                proofTask = nil
                publishProofDocument(document)
            } catch {
                guard generation == proofGeneration, identity == documentGeneration else { return }
                proofTask = nil; phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectArtwork(_ preview: BoardSidePreview) {
        guard let mapping = preview.mapping else { return }
        mapArtwork(preview, mapping: mapping)
    }

    func resetArtwork(_ side: GerberSide) {
        guard !isOpening, var document else { return }
        document.activeArtworkIDs.removeValue(forKey: side)
        if let preview = document.activeArtwork(for: side), let mapping = preview.mapping {
            mapArtwork(preview, mapping: mapping, resetToSupplied: true)
        } else { publishProofDocument(document) }
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
