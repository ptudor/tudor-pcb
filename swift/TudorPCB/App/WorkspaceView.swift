import SwiftUI
import GerberKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WorkspaceModel()
    @State private var viewer = ViewerController()
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    private enum ImportPurpose { case package, proof(GerberSide), relink }
    @State private var importPurpose = ImportPurpose.package
    @State private var isChoosingFile = false

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
                .toolbar { packageToolbar }
        } detail: {
            ZStack {
                MetalBoardView(document: model.document, textures: model.textures, controller: viewer, isActive: scenePhase == .active && viewer.rendererError == nil && !viewer.use2DFallback && model.inspectionTarget == nil)
                    .id(viewer.retryRevision)
                    .opacity(viewer.rendererError == nil && !viewer.use2DFallback && model.inspectionTarget == nil ? 1 : 0)
                if let document = model.document, model.inspectionTarget != nil {
                    LayerInspectionView(document: document, target: $model.inspectionTarget, render: model.inspectBoard)
                        .background(.background)
                } else if viewer.use2DFallback, let textures = model.textures {
                    VStack {
                        Text(WorkspaceStrings.twoDFaces(model.document?.name ?? String(localized: WorkspaceStrings.untitledBoard)))
                        HStack {
                            Image(decorative: textures.top, scale: 1).resizable().scaledToFit().accessibilityLabel(WorkspaceStrings.topFace)
                            Image(decorative: textures.bottom, scale: 1).resizable().scaledToFit().accessibilityLabel(WorkspaceStrings.bottomFaceInBoardCoordinates)
                        }
                        Button(WorkspaceStrings.retry3D) { viewer.retryRendering() }
                    }.padding().background(.background)
                } else if let error = viewer.rendererError {
                    VStack(spacing: 12) {
                        Text(WorkspaceStrings.display3DUnavailable).font(.headline)
                        Text(model.document?.name ?? String(localized: WorkspaceStrings.workspace))
                        Text(error)
                        Button(WorkspaceStrings.retry3D) { viewer.retryRendering() }
                        if model.textures != nil { Button(WorkspaceStrings.show2DFaces) { viewer.use2DFallback = true } }
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                if model.document == nil { welcomeOverlay }
                if model.isLoading {
                    VStack {
                        loadingOverlay
                        if let pending = model.pendingFileName { Text(WorkspaceStrings.opening(pending)).foregroundStyle(.white) }
                    }
                }
                if model.document != nil { interactionHint }
            }
            .background(Color(red: 0.025, green: 0.032, blue: 0.04))
            .navigationTitle(model.document?.name ?? "Tudor PCB")
            .toolbar {
                packageToolbar
                ToolbarItemGroup {
                    Button(WorkspaceStrings.fabricationHistory, systemImage: "clock.arrow.circlepath") {
                        model.isShowingHistory = true
                    }
                    if model.document?.sidePreviews.isEmpty == false {
                        Button(WorkspaceStrings.colorProofs, systemImage: "photo.on.rectangle") { model.showProofs = true }
                            .accessibilityIdentifier("color-proofs")
                    }
                    Button(WorkspaceStrings.perspective, systemImage: "cube.transparent") { viewer.show(.perspective) }
                        .disabled(model.document == nil)
                    Button(WorkspaceStrings.topView, systemImage: "square.3.layers.3d.top.filled") { viewer.show(.top) }
                        .disabled(model.document == nil)
                    Button(WorkspaceStrings.bottomView, systemImage: "square.3.layers.3d.bottom.filled") { viewer.show(.bottom) }
                        .disabled(model.document == nil)
                    Button(WorkspaceStrings.fit, systemImage: "arrow.up.left.and.arrow.down.right") { viewer.show(.fit) }
                        .disabled(model.document == nil)

                    Button(CommonStrings.zoomIn, systemImage: "plus.magnifyingglass") { viewer.zoom(by: -75) }
                        .disabled(model.document == nil)
                    Button(CommonStrings.zoomOut, systemImage: "minus.magnifyingglass") { viewer.zoom(by: 75) }
                        .disabled(model.document == nil)

                    Menu(WorkspaceStrings.boardFinish, systemImage: "paintpalette") {
                        ForEach(BoardMaskStyle.allCases) { style in
                            Button {
                                model.selectMask(style)
                            } label: {
                                if model.maskStyle == style {
                                    Label(style.displayName, systemImage: "checkmark")
                                } else {
                                    Text(style.displayName)
                                }
                            }
                        }
                    }
                    .disabled(model.isOpening || model.document == nil || model.document?.colorSilkscreens.isEmpty == false)
                }
            }
        }
        .onChange(of: model.document?.name) { _, name in
            if name != nil { preferredCompactColumn = .detail }
        }
        .onChange(of: model.isImporting) { _, requested in
            if requested { model.isImporting = false; beginImport(.package) }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: importContentTypes, allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                switch importPurpose {
                case .package: model.open(url)
                case let .proof(side): model.attachColorProof(url, side: side)
                case .relink: model.relink(url)
                }
            case let .failure(error):
                switch importPurpose {
                case .package: model.reportFailure(error, operation: .selectPackage)
                case let .proof(side): model.reportFailure(error, operation: .selectProof, side: side)
                case .relink:
                    if (error as? CocoaError)?.code != .userCancelled && !(error is CancellationError) { model.historyAccessError = error.localizedDescription }
                }
            }
        }
        .focusedSceneValue(\.fabricationWorkspace, model)
        .onOpenURL { model.open($0) }
        .task {
            guard model.document == nil,
                  let path = ProcessInfo.processInfo.arguments.dropFirst().first,
                  !path.hasPrefix("-") else { return }
            model.open(URL(fileURLWithPath: path))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .sheet(isPresented: Binding(get: { !model.candidateChoices.isEmpty }, set: { if !$0 { model.cancelCandidateSelection() } })) {
            VStack(alignment: .leading, spacing: 16) {
                Text(WorkspaceStrings.chooseFabricationBoard).font(.title2)
                Text(WorkspaceStrings.severalBoardSets)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.candidateChoices) { candidate in
                            Button(candidate.displayName) { model.chooseCandidate(candidate) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(CommonStrings.cancel, role: .cancel) { model.cancelCandidateSelection() }
            }.padding().frame(minWidth: 320, idealWidth: 500, minHeight: 240)
        }
        .alert(model.errorTitle, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            switch model.failedOperation {
            case .openPackage, .selectPackage:
                Button(ErrorStrings.selectPackage) { beginImport(.package) }
            case .attachProof, .selectProof:
                Button(ErrorStrings.selectProof) {
                    if model.failedProofSide == .bottom { beginImport(.proof(.bottom)) }
                    else { beginImport(.proof(.top)) }
                }
            case .mapProof: Button(ErrorStrings.reviewProofMapping) { model.showProofs = true }
            case .renderBoard: Button(ErrorStrings.retryRendering) { model.rerender() }
            }
            Button(ErrorStrings.dismiss, role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? String(localized: ErrorStrings.unknownError))
        }
        .alert(HistoryStrings.historyNeedsRecovery, isPresented: Binding(
            get: { model.historyError != nil },
            set: { if !$0 { model.historyError = nil } }
        )) {
            if model.historyRecovery != nil {
                Button(HistoryStrings.backUpAndRecover) { model.recoverHistory() }
            }
            Button(HistoryStrings.keepOriginal, role: .cancel) { model.historyError = nil }
        } message: { Text(model.historyError ?? "") }
        .alert(HistoryStrings.historyAccessNeedsAttention, isPresented: Binding(
            get: { model.historyAccessError != nil },
            set: { if !$0 { model.historyAccessError = nil } }
        )) {
            Button(HistoryStrings.reselectSource) { beginImport(.relink) }
            Button(HistoryStrings.later, role: .cancel) { model.historyAccessError = nil }
        } message: { Text(model.historyAccessError ?? "") }
        .sheet(isPresented: $model.showProofs) {
            if let document = model.document { ProofGalleryView(document: document, onSelect: { model.selectArtwork($0) }, onReset: { model.resetArtwork($0) }, onMap: { model.mapArtwork($0, mapping: $1) }) }
        }
        .sheet(isPresented: $model.isShowingHistory) {
            PackageBrowserView(
                entries: model.historyEntries,
                onOpen: { model.open($0) },
                onRelink: { model.relinkEntry = $0; model.isShowingHistory = false; beginImport(.relink) },
                onRemove: { model.removeFromHistory($0) },
                onClear: { model.clearHistory() }
            )
        }
    }

    private var importContentTypes: [UTType] {
        if case .proof = importPurpose { [.png, .jpeg, .tiff, .heic] }
        else { [.zip, .folder, .data] }
    }

    private func beginImport(_ purpose: ImportPurpose) {
        importPurpose = purpose
        isChoosingFile = true
    }

    @ToolbarContentBuilder
    private var packageToolbar: some ToolbarContent {
        ToolbarItem(placement: openToolbarPlacement) {
            Button(model.document == nil ? WorkspaceStrings.openPackage : WorkspaceStrings.replacePackage, systemImage: "folder.badge.plus") {
                beginImport(.package)
            }
            .accessibilityIdentifier("open-package")
            .help(WorkspaceStrings.openOrReplaceHelp)
        }
    }

    private var openToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(WorkspaceStrings.fabricationReview, systemImage: "cpu")
                    .textCase(.uppercase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(WorkspaceStrings.fabricationHistory, systemImage: "clock.arrow.circlepath") {
                    model.isShowingHistory = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help(WorkspaceStrings.browseFabricationHistory)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if let document = model.document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        boardSummary(document)
                        reviewStatus(document)
                        layerList(document)
                        if !document.warnings.isEmpty { warningList(document.warnings) }
                    }
                    .padding(16)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label(WorkspaceStrings.noPackageOpen, systemImage: "shippingbox")
                        .font(.headline)
                    Text(WorkspaceStrings.openAGerberZip)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(WorkspaceStrings.openPackage) { beginImport(.package) }
                        .buttonStyle(.borderedProminent)
                    if !model.historyEntries.isEmpty {
                        Button(WorkspaceStrings.browseRecentPackages(model.historyEntries.count)) {
                            model.isShowingHistory = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(16)
                Spacer()
            }

            Divider()
            Label(WorkspaceStrings.localInspectionOnly, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
        .background(.regularMaterial)
    }

    private func boardSummary(_ document: BoardDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(document.name)
                .font(.headline)
                .lineLimit(2)
            Text(CommonStrings.boardDimensions(width: document.bounds.width.formatted(.number.precision(.fractionLength(2))), height: document.bounds.height.formatted(.number.precision(.fractionLength(2)))))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(WorkspaceStrings.summary(String(localized: WorkspaceStrings.layerCount(document.layers.count)), String(localized: WorkspaceStrings.drillCount(document.drills.count)), String(localized: WorkspaceStrings.objectCount(document.primitiveCount))))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if document.packageRole == .jlcpcbProduction {
                Text(WorkspaceStrings.jlcpcbEngineerProduction)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                if !document.enclosedSourceArchives.isEmpty {
                    Text(WorkspaceStrings.originalUploadsEnclosed(document.enclosedSourceArchives.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if document.packageRole == .nestedArchive {
                Text(WorkspaceStrings.openedFromEnclosedZip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reviewStatus(_ document: BoardDocument) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(WorkspaceStrings.reviewStatus)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            statusRow(
                document.layers.contains { $0.kind == .outline },
                label: WorkspaceStrings.boardOutline,
                goodDetail: Text(WorkspaceStrings.outlineLoadedDetail),
                badDetail: Text(WorkspaceStrings.missing)
            )
            statusRow(!document.drills.isEmpty, label: WorkspaceStrings.drillMap, goodDetail: Text(WorkspaceStrings.drillPresentDetail), badDetail: Text(WorkspaceStrings.missing))
            if document.packageRole == .jlcpcbProduction {
                Label(WorkspaceStrings.jlcpcbSourceFolder, systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(WorkspaceStrings.inspectedSource(document.name, document.sourceSelection?.displayName ?? String(localized: WorkspaceStrings.directInput)))
                .font(.caption).textSelection(.enabled)
            Label(WorkspaceStrings.reviewIncomplete, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            Text(WorkspaceStrings.reviewIncompleteDetail)
                .font(.caption).foregroundStyle(.secondary)
            ForEach([GerberSide.top, .bottom], id: \.self) { side in
                if document.colorSilkscreens.contains(where: { $0.side == side }) || document.sidePreviews.contains(where: { $0.side == side }) {
                    statusRow(document.proofState(for: side) == .mappedArtwork,
                        label: side == .top ? WorkspaceStrings.topColor : WorkspaceStrings.bottomColor,
                        goodDetail: Text(document.proofState(for: side).label),
                        badDetail: Text(document.proofState(for: side).label), validated: true)
                }
            }
            if !document.sidePreviews.isEmpty {
                Text(WorkspaceStrings.proofValidationNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !document.colorSilkscreens.isEmpty {
                Text(WorkspaceStrings.factoryPayloadsPresent)
                    .font(.caption).foregroundStyle(.secondary)
            }
                Menu(WorkspaceStrings.colorProofOptions, systemImage: "photo.on.rectangle.angled") {
                    Button(WorkspaceStrings.attachTopArtwork) { beginImport(.proof(.top)) }
                    Button(WorkspaceStrings.attachBottomArtwork) { beginImport(.proof(.bottom)) }
                    if !document.sidePreviews.isEmpty {
                        Divider()
                        Button(WorkspaceStrings.viewSuppliedProofs) { model.showProofs = true }
                    }
                }
                .font(.callout)

        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusRow(_ good: Bool, label: LocalizedStringResource, goodDetail: Text, badDetail: Text, validated: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: good ? (validated ? "checkmark.circle.fill" : "info.circle") : "exclamationmark.triangle.fill")
                .foregroundStyle(good ? (validated ? .green : .secondary) : .orange)
            Text(label)
            Spacer()
            (good ? goodDetail : badDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func layerList(_ document: BoardDocument) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(WorkspaceStrings.layers)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(WorkspaceStrings.layersNote)
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(document.layers) { layer in
                HStack(spacing: 9) {
                    if layer.kind.hasPhysicalAppearanceControl {
                        Button { model.toggleLayer(layer) } label: {
                            Image(systemName: model.visibleLayerIDs.contains(layer.id) ? "eye" : "eye.slash")
                        }.accessibilityLabel(WorkspaceStrings.togglePhysicalLayer(layer.kind.displayName))
                    } else { Text(WorkspaceStrings.twoD).font(.caption2).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(layer.kind.displayName)
                        Text(layer.fileName).font(.caption2).lineLimit(1).help(layer.fileName)
                    }
                    Spacer()
                    Button { model.inspectionTarget = .layer(layer.id) } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel(WorkspaceStrings.inspectIn2D(layer.fileName))
                }
                .buttonStyle(.plain).disabled(model.isOpening)
            }
            if !document.drills.isEmpty {
                Button(WorkspaceStrings.inspectDrillsSlotsIn2D, systemImage: "circle.dotted") { model.inspectionTarget = .drills }
                    .disabled(model.isOpening)
            }
        }
    }

    private func warningList(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func layerColor(_ kind: GerberLayerKind) -> Color {
        switch kind {
        case .copper: .orange
        case .solderMask: .green
        case .silkscreen: .white
        case .paste: .gray
        case .outline: .pink
        case .documentation: .blue
        default: .secondary
        }
    }

    @ViewBuilder
    private var welcomeOverlay: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 58, weight: .thin))
                .foregroundStyle(.mint)
            Text(WorkspaceStrings.welcomeTitle)
                .font(.title2.weight(.semibold))
            Text(WorkspaceStrings.welcomeSubtitle)
                .foregroundStyle(.secondary)
            Button(WorkspaceStrings.chooseGerberPackage) {
                beginImport(.package)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if !model.historyEntries.isEmpty {
                Button(WorkspaceStrings.browseFabricationHistory) {
                    model.isShowingHistory = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(38)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text(model.document == nil ? WorkspaceStrings.readingPackage : WorkspaceStrings.renderingLayers)
                .font(.callout.weight(.medium))
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var interactionHint: some View {
        VStack {
            Spacer()
            Text(WorkspaceStrings.interactionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
        }
        .allowsHitTesting(false)
    }
}

private struct PackageBrowserView: View {
    let entries: [PackageHistoryEntry]
    let onOpen: (PackageHistoryEntry) -> Void
    let onRelink: (PackageHistoryEntry) -> Void
    let onRemove: (PackageHistoryEntry) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: PackageHistoryEntry.ID?
    @State private var searchText = ""
    @State private var isConfirmingClear = false

    private var filteredEntries: [PackageHistoryEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            [entry.name, entry.sourcePath, entry.formatDisplayName, entry.generator ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var selectedEntry: PackageHistoryEntry? {
        let id = PackageHistorySelection.reconciled(selection, visibleIDs: filteredEntries.map(\.id))
        return filteredEntries.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        HistoryStrings.noFabricationHistory,
                        systemImage: "clock.arrow.circlepath",
                        description: Text(HistoryStrings.packagesAppearAfterInspection)
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredEntries, selection: $selection) { entry in
                        NavigationLink(value: entry.id) {
                            PackageHistoryRow(entry: entry)
                        }
                        .contextMenu {
                            Button(HistoryStrings.relinkSource) { onRelink(entry); dismiss() }
                            Button(HistoryStrings.removeFromHistory, role: .destructive) { onRemove(entry) }
                        }
                    }
                }
            }
            .navigationTitle(HistoryStrings.fabricationHistoryTitle)
            .searchable(text: $searchText, prompt: HistoryStrings.searchPrompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CommonStrings.done) { dismiss() }.accessibilityIdentifier("done")
                }
                ToolbarItem {
                    Button(HistoryStrings.clearHistory, role: .destructive) { isConfirmingClear = true }
                        .disabled(entries.isEmpty)
                }
            }
        } detail: {
            if let entry = selectedEntry {
                PackageHistoryDetail(entry: entry) {
                    onOpen(entry)
                    dismiss()
                } onRemove: {
                    onRemove(entry)
                }
            } else {
                ContentUnavailableView(HistoryStrings.selectAPackage, systemImage: "shippingbox")
            }
        }
        .onChange(of: filteredEntries.map(\.id), initial: true) { _, ids in
            selection = PackageHistorySelection.reconciled(selection, visibleIDs: ids)
        }
        .confirmationDialog(HistoryStrings.clearAllConfirmation, isPresented: $isConfirmingClear) {
            Button(HistoryStrings.clearHistory, role: .destructive) {
                onClear()
                selection = nil
            }
        } message: {
            Text(HistoryStrings.clearAllMessage)
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 580)
        #endif
    }
}

private struct PackageHistoryRow: View {
    let entry: PackageHistoryEntry

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: entry.sourceKind.systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(entry.colorSilkscreenSides > 0 ? .purple : .mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(HistoryStrings.rowSummary(format: entry.formatDisplayName, width: entry.boardWidth.formatted(.number.precision(.fractionLength(1))), height: entry.boardHeight.formatted(.number.precision(.fractionLength(1)))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(HistoryStrings.modified(entry.ageDescription))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if entry.openedCount > 1 {
                Text(HistoryStrings.openedTimes(entry.openedCount))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// One labeled value in the history detail panel.
private struct DetailRow: View {
    let label: LocalizedStringResource
    let value: String

    init(_ label: LocalizedStringResource, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent { Text(value) } label: { Text(label) }
    }
}

private struct PackageHistoryDetail: View {
    let entry: PackageHistoryEntry
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var availability = HistorySourceAvailability.checking

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: entry.sourceKind.systemImage)
                        .font(.system(size: 34))
                        .foregroundStyle(entry.colorSilkscreenSides > 0 ? .purple : .mint)
                        .frame(width: 54, height: 54)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.title2.weight(.semibold))
                        Label(
                            availability.label,
                            systemImage: availability.accessible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(availability.accessible ? .green : .orange)
                        .task(id: entry) { availability = .checking; availability = await PackageHistoryStore.availability(entry) }
                    }
                }

                Button(HistoryStrings.openPackage, systemImage: "arrow.up.forward.app", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                detailSection(HistoryStrings.packageSection) {
                    DetailRow(HistoryStrings.format, entry.formatDisplayName)
                    DetailRow(HistoryStrings.source, entry.sourceKind.displayName)
                    LabeledContent {
                        Text(CommonStrings.boardDimensions(width: entry.boardWidth.formatted(.number.precision(.fractionLength(2))), height: entry.boardHeight.formatted(.number.precision(.fractionLength(2)))))
                            .monospacedDigit()
                    } label: { Text(HistoryStrings.board) }
                    DetailRow(HistoryStrings.layers, entry.layerCount.formatted())
                    DetailRow(HistoryStrings.drills, entry.drillCount.formatted())
                    DetailRow(HistoryStrings.objects, entry.primitiveCount.formatted())
                    if entry.colorSilkscreenSides > 0 {
                        DetailRow(HistoryStrings.colorSilkscreen, String(localized: HistoryStrings.sideCount(entry.colorSilkscreenSides)))
                    }
                    if entry.packageRole == .jlcpcbProduction {
                        DetailRow(HistoryStrings.reviewSet, String(localized: HistoryStrings.jlcpcbEngineerOutput))
                    } else if entry.packageRole == .nestedArchive {
                        DetailRow(HistoryStrings.container, String(localized: HistoryStrings.nestedZip))
                    }
                    if let count = entry.enclosedSourceCount, count > 0 {
                        DetailRow(
                            entry.packageRole == .jlcpcbProduction ? HistoryStrings.originalUploads : HistoryStrings.enclosedArchives,
                            String(localized: HistoryStrings.enclosedCount(count))
                        )
                    }
                    if let byteCount = entry.byteCount {
                        DetailRow(HistoryStrings.packageSize, byteCount.formatted(.byteCount(style: .file)))
                    }
                    if entry.warningCount > 0 {
                        DetailRow(HistoryStrings.reviewWarnings, entry.warningCount.formatted())
                    }
                }

                detailSection(HistoryStrings.ageAndActivity) {
                    DetailRow(HistoryStrings.sourceAge, entry.ageDescription)
                    if let modifiedAt = entry.modifiedAt {
                        DetailRow(HistoryStrings.modifiedLabel, modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let createdAt = entry.createdAt {
                        DetailRow(HistoryStrings.created, createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    DetailRow(HistoryStrings.firstInspected, entry.firstOpenedAt.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(HistoryStrings.lastInspected, entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(HistoryStrings.timesOpened, entry.openedCount.formatted())
                }

                if let generator = entry.generator {
                    detailSection(HistoryStrings.generator) {
                        Text(generator)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }

                detailSection(HistoryStrings.location) {
                    Text(entry.sourcePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button(HistoryStrings.removeFromHistory, role: .destructive, action: onRemove)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle(entry.name)
    }

    private func detailSection<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9, content: content)
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct ProofGalleryView: View {
    let document: BoardDocument
    let onSelect: (BoardSidePreview) -> Void
    let onReset: (GerberSide) -> Void
    let onMap: (BoardSidePreview, BoardArtworkMapping) -> Void
    @State private var mappingPreview: BoardSidePreview?
    @State private var inspectingPreview: BoardSidePreview?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(280, max(120, geometry.size.width - 32))), spacing: 18)], spacing: 24) {
                    ForEach(document.sidePreviews) { preview in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { inspectingPreview = preview } label: {
                                proofImage(preview).scaledToFit().frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                                .accessibilityLabel(preview.side == .top ? ProofStrings.inspectTopProof(preview.fileName) : ProofStrings.inspectBottomProof(preview.fileName))
                            Button(ProofStrings.inspectImage) { inspectingPreview = preview }.accessibilityIdentifier("inspect-image")
                            Text(preview.side == .top ? ProofStrings.topProofFile(preview.fileName) : ProofStrings.bottomProofFile(preview.fileName))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preview.provenance == .supplied ? ProofStrings.suppliedWithSource : ProofStrings.userAttachment)
                                .font(.caption2)
                            if preview.purpose == .boardArtwork && preview.mapping != nil {
                                if document.activeArtwork(for: preview.side)?.id == preview.id {
                                    Label(ProofStrings.activeBoardArtwork, systemImage: "checkmark.circle")
                                } else { Button(ProofStrings.useAsBoardArtwork) { onSelect(preview) } }
                            } else { Text(ProofStrings.unmappedGalleryProof).font(.caption) }
                            Button(preview.mapping == nil ? ProofStrings.mapToBoard : ProofStrings.editMapping) { mappingPreview = preview }
                            if let mapping = preview.mapping {
                                Text(ProofStrings.mappingSummary(width: mapping.bounds.width.formatted(), height: mapping.bounds.height.formatted(), orientation: String(localized: mapping.orientation == .boardCoordinates ? ProofStrings.orientationBoardCoordinates : ProofStrings.orientationViewedFromBottom)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(16)
            }
            }
            .navigationTitle(ProofStrings.colorProofsTitle)
            .toolbar {
                ToolbarItemGroup {
                    Menu(ProofStrings.resetArtwork, systemImage: "arrow.counterclockwise") {
                        Button(ProofStrings.resetTopToSupplied) { onReset(.top) }
                        Button(ProofStrings.resetBottomToSupplied) { onReset(.bottom) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button(CommonStrings.done) { dismiss() }.accessibilityIdentifier("done") }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .sheet(item: $inspectingPreview) { preview in ProofInspectionView(preview: preview) }
        .sheet(item: $mappingPreview) { preview in
            ProofMappingView(preview: preview, initialBounds: preview.mapping?.bounds ?? document.bounds) { mapping in
                onMap(preview, mapping)
            }
        }
    }

    @ViewBuilder
    private func proofImage(_ preview: BoardSidePreview) -> some View {
        BoundedProofImageView(preview: preview)
    }
}


private struct ProofInspectionView: View {
    let preview: BoardSidePreview
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag = CGSize.zero

    var body: some View {
        NavigationStack {
            GeometryReader { available in
            ScrollView {
            VStack {
                Text(preview.side == .top ? ProofStrings.topProofFile(preview.fileName) : ProofStrings.bottomProofFile(preview.fileName)).font(.caption).textSelection(.enabled)
                Text(preview.provenance == .supplied ? ProofStrings.suppliedWithSource : ProofStrings.userAttachment).font(.caption2)
                GeometryReader { geometry in
                    BoundedProofImageView(preview: preview).scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoom * pinch)
                        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(.black).clipped().contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ProofStrings.proofImage)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityIdentifier("proof-inspection-image")
                        .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { setZoom(zoom * $0.magnification) })
                        .highPriorityGesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height)
                                constrainOffset(geometry.size)
                            }, including: zoom > 1 ? .all : .none)
                        .onChange(of: zoom) { _, _ in constrainOffset(geometry.size) }
                        .onChange(of: offset) { _, _ in constrainOffset(geometry.size) }
                        .onChange(of: geometry.size) { _, size in constrainOffset(size) }
                }.frame(height: max(200, min(600, available.size.height * 0.6)))
                Text(ProofStrings.imagePreviewZoom(Double(zoom).formatted(.number.precision(.fractionLength(1))))).font(.caption.monospacedDigit())
                ScrollView(.horizontal) {
                    HStack {
                        Button(CommonStrings.zoomIn, systemImage: "plus.magnifyingglass") { setZoom(zoom * 2) }
                            .accessibilityIdentifier("zoom-in")
                        Button(CommonStrings.zoomOut, systemImage: "minus.magnifyingglass") { setZoom(zoom / 2) }
                        Button(ProofStrings.fitImage) { setZoom(1); offset = .zero }.accessibilityIdentifier("fit-image")
                        Menu(CommonStrings.pan, systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                            Button(CommonStrings.left) { offset.width += 60 }
                            Button(CommonStrings.right) { offset.width -= 60 }
                            Button(CommonStrings.up) { offset.height += 60 }
                            Button(CommonStrings.down) { offset.height -= 60 }
                        }
                    }
                }
            }.padding()
            }
            }
            .navigationTitle(preview.side == .top ? ProofStrings.topProof : ProofStrings.bottomProof)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(CommonStrings.done) { dismiss() }.accessibilityIdentifier("done") } }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
    private func setZoom(_ value: CGFloat) { zoom = min(16, max(1, value)) }
    private func constrainOffset(_ size: CGSize) {
        offset.width = min(size.width * (zoom - 1) / 2, max(-size.width * (zoom - 1) / 2, offset.width))
        offset.height = min(size.height * (zoom - 1) / 2, max(-size.height * (zoom - 1) / 2, offset.height))
    }
}


private struct BoundedProofImageView: View {
    let preview: BoardSidePreview
    @State private var image: ProofImage?
    @State private var failure: String?

    var body: some View {
        Group {
            if let image { Image(decorative: image.cgImage, scale: 1).resizable() }
            else if let failure { Text(failure).foregroundStyle(.secondary) }
            else { ProgressView(ProofStrings.loadingProof) }
        }
        .task(id: preview) {
            if let cached = preview.validatedImage { image = cached; return }
            let data = preview.imageData
            let name = preview.fileName
            let task = Task.detached { try ProofImageDecoder.decode(data, name: name) }
            do {
                image = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            } catch is CancellationError { }
              catch { failure = error.localizedDescription }
        }
    }
}

private struct ProofMappingView: View {
    let preview: BoardSidePreview
    let onMap: (BoardArtworkMapping) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minimumX: Double
    @State private var minimumY: Double
    @State private var maximumX: Double
    @State private var maximumY: Double
    @State private var orientation: BoardArtworkMapping.Orientation?
    @State private var error: String?

    init(preview: BoardSidePreview, initialBounds: Bounds2D, onMap: @escaping (BoardArtworkMapping) -> Void) {
        self.preview = preview; self.onMap = onMap
        _minimumX = State(initialValue: initialBounds.minimum.x)
        _minimumY = State(initialValue: initialBounds.minimum.y)
        _maximumX = State(initialValue: initialBounds.maximum.x)
        _maximumY = State(initialValue: initialBounds.maximum.y)
        _orientation = State(initialValue: preview.mapping?.orientation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text(preview.fileName)
                BoundedProofImageView(preview: preview).scaledToFit().frame(maxHeight: 220)
                Text(ProofStrings.mappingInstructions)
                    .font(.callout)
                TextField(ProofStrings.minimumX, value: $minimumX, format: .number)
                TextField(ProofStrings.minimumY, value: $minimumY, format: .number)
                TextField(ProofStrings.maximumX, value: $maximumX, format: .number)
                TextField(ProofStrings.maximumY, value: $maximumY, format: .number)
                Picker(ProofStrings.imageOrientation, selection: $orientation) {
                    Text(ProofStrings.chooseOrientation).tag(Optional<BoardArtworkMapping.Orientation>.none)
                    Text(ProofStrings.orientationBoardCoordinatesDetail).tag(Optional(BoardArtworkMapping.Orientation.boardCoordinates))
                    Text(ProofStrings.orientationViewedFromBottomDetail).tag(Optional(BoardArtworkMapping.Orientation.viewedFromBottom))
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(preview.side == .top ? ProofStrings.mapTopArtwork : ProofStrings.mapBottomArtwork)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(CommonStrings.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ProofStrings.useMapping) {
                        guard let orientation else { return }
                        let mapping = BoardArtworkMapping(bounds: Bounds2D(minimum: Point2D(x: minimumX, y: minimumY), maximum: Point2D(x: maximumX, y: maximumY)), orientation: orientation)
                        do { try mapping.validate(); onMap(mapping); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(orientation == nil)
                }
            }
        }.frame(idealWidth: 560, idealHeight: 650)
    }
}

private struct LayerInspectionView: View {
    let document: BoardDocument
    @Binding var target: BoardInspectionTarget?
    let render: @Sendable (BoardDocument, Set<String>, Bool, Bounds2D?) async throws -> BoardInspectionImage
    @State private var showDrills = true
    @State private var output: BoardInspectionImage?
    @State private var error: String?
    @State private var viewport: Bounds2D?
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    private struct Request: Equatable { var document: BoardDocument; var target: BoardInspectionTarget?; var drills: Bool; var viewport: Bounds2D? }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker(WorkspaceStrings.inspectSource, selection: $target) {
                    ForEach(document.layers) { layer in Text(layer.fileName).tag(Optional(BoardInspectionTarget.layer(layer.id))) }
                    if !document.drills.isEmpty { Text(WorkspaceStrings.drillsAndSlots).tag(Optional(BoardInspectionTarget.drills)) }
                }
                Button(WorkspaceStrings.physicalBoard) { target = nil }
            }
            Toggle(WorkspaceStrings.showDrillOverlay, isOn: $showDrills).disabled(document.drills.isEmpty)
            ScrollView(.horizontal) {
                HStack {
                    Button(CommonStrings.zoomIn, systemImage: "plus.magnifyingglass") { zoom(2) }
                    Button(CommonStrings.zoomOut, systemImage: "minus.magnifyingglass") { zoom(0.5) }
                    Button(WorkspaceStrings.fitSource, systemImage: "arrow.up.left.and.arrow.down.right") { viewport = nil }
                    Menu(CommonStrings.pan, systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                        Button(CommonStrings.left) { pan(x: -0.25, y: 0) }
                        Button(CommonStrings.right) { pan(x: 0.25, y: 0) }
                        Button(CommonStrings.up) { pan(x: 0, y: 0.25) }
                        Button(CommonStrings.down) { pan(x: 0, y: -0.25) }
                    }
                }
            }.disabled(output == nil)
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let output {
                        Image(decorative: output.image, scale: 1).resizable().scaledToFit()
                            .scaleEffect(magnification).offset(drag)
                            .accessibilityLabel(WorkspaceStrings.selectedSourceAccessibility)
                    } else { ProgressView(WorkspaceStrings.drawingSourceGeometry) }
                    if let error { Text(error).foregroundStyle(.orange).padding() }
                }
                .clipped().contentShape(Rectangle())
                .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard let output else { return }
                        let scale = pointsPerMillimeter(geometry.size, output.bounds)
                        setViewport(center: Point2D(x: output.bounds.center.x - value.translation.width / scale,
                                                    y: output.bounds.center.y + value.translation.height / scale), bounds: output.bounds)
                    })
                .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { zoom($0.magnification) })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                    guard let output else { return }
                    let scale = pointsPerMillimeter(geometry.size, output.bounds)
                    zoom(2, center: Point2D(x: output.bounds.center.x + (value.location.x - geometry.size.width / 2) / scale,
                                           y: output.bounds.center.y - (value.location.y - geometry.size.height / 2) / scale))
                })
            }
            if let output {
                Text(WorkspaceStrings.inspectionMetrics(width: output.bounds.width.formatted(.number.precision(.fractionLength(4))), height: output.bounds.height.formatted(.number.precision(.fractionLength(4))), millimetersPerPixel: output.millimetersPerPixel.formatted(.number.precision(.significantDigits(3))), pixelWidth: output.image.width, pixelHeight: output.image.height))
                    .font(.caption.monospacedDigit())
            }
            Text(WorkspaceStrings.inspectionHint)
                .font(.caption2).foregroundStyle(.secondary)
        }.padding()
        .onChange(of: document) { _, _ in viewport = nil }
        .onChange(of: target) { _, _ in viewport = nil }
        .task(id: Request(document: document, target: target, drills: showDrills, viewport: viewport)) {
            output = nil; error = nil
            let ids: Set<String>
            if case let .layer(id) = target { ids = [id] } else { ids = [] }
            let task = Task { try await render(document, ids, showDrills, viewport) }
            do {
                let image = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                output = image
            } catch is CancellationError { }
              catch { self.error = error.localizedDescription }
        }
    }

    private func pointsPerMillimeter(_ size: CGSize, _ bounds: Bounds2D) -> Double {
        max(0.000001, min(size.width / bounds.width, size.height / bounds.height))
    }
    private func zoom(_ scale: Double, center: Point2D? = nil) {
        guard let output, scale.isFinite, scale > 0 else { return }
        let bounds = output.bounds
        let limited = min(max(scale, max(bounds.width, bounds.height) / 1_000_000), min(bounds.width, bounds.height) / 0.001)
        let next = Bounds2D(minimum: .zero, maximum: Point2D(x: bounds.width / limited, y: bounds.height / limited))
        setViewport(center: center ?? bounds.center, bounds: next)
    }
    private func pan(x: Double, y: Double) {
        guard let output else { return }
        setViewport(center: Point2D(x: output.bounds.center.x + x * output.bounds.width, y: output.bounds.center.y + y * output.bounds.height), bounds: output.bounds)
    }
    private func setViewport(center: Point2D, bounds: Bounds2D) {
        let x = min(1_000_000 - bounds.width / 2, max(-1_000_000 + bounds.width / 2, center.x))
        let y = min(1_000_000 - bounds.height / 2, max(-1_000_000 + bounds.height / 2, center.y))
        viewport = Bounds2D(minimum: Point2D(x: x - bounds.width / 2, y: y - bounds.height / 2), maximum: Point2D(x: x + bounds.width / 2, y: y + bounds.height / 2))
    }
}
