import SwiftUI
import GerberKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @State private var model = WorkspaceModel()
    @State private var viewer = ViewerController()
    @State private var isRelinking = false
    @State private var isImportingTopProof = false
    @State private var isImportingBottomProof = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            ZStack {
                MetalBoardView(document: model.document, textures: model.textures, controller: viewer)
                    .id(viewer.retryRevision)
                    .opacity(viewer.rendererError == nil && !viewer.use2DFallback ? 1 : 0)
                if viewer.use2DFallback, let textures = model.textures {
                    VStack {
                        Text("2D faces · \(model.document?.name ?? "Board")")
                        HStack {
                            Image(decorative: textures.top, scale: 1).resizable().scaledToFit().accessibilityLabel("Top face")
                            Image(decorative: textures.bottom, scale: 1).resizable().scaledToFit().accessibilityLabel("Bottom face in board coordinates")
                        }
                        Button("Retry 3D") { viewer.retryRendering() }
                    }.padding().background(.background)
                } else if let error = viewer.rendererError {
                    VStack(spacing: 12) {
                        Text("3D display unavailable").font(.headline)
                        Text(model.document?.name ?? "Workspace")
                        Text(error)
                        Button("Retry 3D") { viewer.retryRendering() }
                        if model.textures != nil { Button("Show 2D faces") { viewer.use2DFallback = true } }
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                if model.document == nil { welcomeOverlay }
                if model.isLoading {
                    VStack {
                        loadingOverlay
                        if let pending = model.pendingFileName { Text("Opening \(pending)").foregroundStyle(.white) }
                    }
                }
                if model.document != nil { interactionHint }
            }
            .background(Color(red: 0.025, green: 0.032, blue: 0.04))
            .toolbar {
                ToolbarItemGroup {
                    Button("Fabrication History", systemImage: "clock.arrow.circlepath") {
                        model.isShowingHistory = true
                    }
                    Button("Perspective", systemImage: "cube.transparent") { viewer.show(.perspective) }
                        .disabled(model.document == nil)
                    Button("Top", systemImage: "square.3.layers.3d.top.filled") { viewer.show(.top) }
                        .disabled(model.document == nil)
                    Button("Bottom", systemImage: "square.3.layers.3d.bottom.filled") { viewer.show(.bottom) }
                        .disabled(model.document == nil)
                    Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { viewer.show(.fit) }
                        .disabled(model.document == nil)

                    Menu("Board finish", systemImage: "paintpalette") {
                        ForEach(BoardMaskStyle.allCases) { style in
                            Button {
                                model.selectMask(style)
                            } label: {
                                if model.maskStyle == style {
                                    Label(style.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(style.rawValue)
                                }
                            }
                        }
                    }
                    .disabled(model.isOpening || model.document == nil || model.document?.colorSilkscreens.isEmpty == false)
                }
            }
        }
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: [.zip, .folder, .data],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { model.open(url) }
        }
        .fileImporter(
            isPresented: $isImportingTopProof,
            allowedContentTypes: [.png, .jpeg, .tiff, .heic],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { model.attachColorProof(url, side: .top) }
        }
        .fileImporter(
            isPresented: $isImportingBottomProof,
            allowedContentTypes: [.png, .jpeg, .tiff, .heic],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first { model.attachColorProof(url, side: .bottom) }
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
                Text("Choose fabrication board").font(.title2)
                Text("This delivery contains several board sets. Choose the source path to inspect.")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.candidateChoices) { candidate in
                            Button(candidate.displayName) { model.chooseCandidate(candidate) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Cancel", role: .cancel) { model.cancelCandidateSelection() }
            }.padding().frame(minWidth: 320, idealWidth: 500, minHeight: 240)
        }
        .alert("Couldn’t open fabrication package", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .alert("History needs recovery", isPresented: Binding(
            get: { model.historyError != nil },
            set: { if !$0 { model.historyError = nil } }
        )) {
            if model.historyRecovery != nil {
                Button("Back Up Original and Recover Valid History") { model.recoverHistory() }
            }
            Button("Keep Original", role: .cancel) { model.historyError = nil }
        } message: { Text(model.historyError ?? "") }
        .alert("History access needs attention", isPresented: Binding(
            get: { model.historyAccessError != nil },
            set: { if !$0 { model.historyAccessError = nil } }
        )) {
            Button("Reselect Source…") { isRelinking = true }
            Button("Later", role: .cancel) { model.historyAccessError = nil }
        } message: { Text(model.historyAccessError ?? "") }
        .fileImporter(isPresented: $isRelinking, allowedContentTypes: [.zip, .folder, .data]) { result in
            switch result {
            case let .success(url): model.relink(url)
            case let .failure(error): model.historyAccessError = error.localizedDescription
            }
        }
        .sheet(isPresented: $model.showProofs) {
            if let document = model.document { ProofGalleryView(document: document, onSelect: { model.selectArtwork($0) }, onReset: { model.resetArtwork($0) }, onMap: { model.mapArtwork($0, mapping: $1) }) }
        }
        .sheet(isPresented: $model.isShowingHistory) {
            PackageBrowserView(
                entries: model.historyEntries,
                onOpen: { model.open($0) },
                onRelink: { model.relinkEntry = $0; model.isShowingHistory = false; isRelinking = true },
                onRemove: { model.removeFromHistory($0) },
                onClear: { model.clearHistory() }
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("FABRICATION REVIEW", systemImage: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fabrication History", systemImage: "clock.arrow.circlepath") {
                    model.isShowingHistory = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Browse fabrication history")
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
                    Label("No package open", systemImage: "shippingbox")
                        .font(.headline)
                    Text("Open a Gerber ZIP from EasyEDA, Eagle, KiCad, or your manufacturer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Open Package…") { model.isImporting = true }
                        .buttonStyle(.borderedProminent)
                    if !model.historyEntries.isEmpty {
                        Button("Browse \(model.historyEntries.count) Recent Package\(model.historyEntries.count == 1 ? "" : "s")") {
                            model.isShowingHistory = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(16)
                Spacer()
            }

            Divider()
            Label("Local inspection only", systemImage: "lock.shield")
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
            Text("\(document.bounds.width, format: .number.precision(.fractionLength(2))) × \(document.bounds.height, format: .number.precision(.fractionLength(2))) mm")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(document.layers.count) layers · \(document.drills.count) drills · \(document.primitiveCount.formatted()) objects")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if document.packageRole == .jlcpcbProduction {
                Text("JLCPCB engineer production · OK")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
                if !document.enclosedSourceArchives.isEmpty {
                    Text("\(document.enclosedSourceArchives.count) original upload\(document.enclosedSourceArchives.count == 1 ? "" : "s") enclosed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if document.packageRole == .nestedArchive {
                Text("Opened from an enclosed Gerber ZIP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reviewStatus(_ document: BoardDocument) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("REVIEW STATUS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            statusRow(
                document.layers.contains { $0.kind == .outline },
                label: "Board outline",
                goodDetail: "Parsed",
                badDetail: "Missing"
            )
            statusRow(!document.drills.isEmpty, label: "Drill map", goodDetail: "Present · alignment unverified", badDetail: "Missing")
            if document.packageRole == .jlcpcbProduction {
                statusRow(true, label: "Production set", goodDetail: "JLCPCB OK", badDetail: "")
            }
            if !document.colorSilkscreens.isEmpty {
                statusRow(
                    document.sidePreviews.contains { $0.fileName.contains("attached-artwork") || $0.fileName.contains("side") },
                    label: "EasyEDA color",
                    goodDetail: "Proof attached",
                    badDetail: "Factory-encrypted"
                )
            } else if !document.sidePreviews.isEmpty {
                Button("View supplied proofs", systemImage: "photo.on.rectangle") { model.showProofs = true }
                    .font(.callout)
            }
                Menu("Color proof options", systemImage: "photo.on.rectangle.angled") {
                    Button("Attach top artwork…") { isImportingTopProof = true }
                    Button("Attach bottom artwork…") { isImportingBottomProof = true }
                    if !document.sidePreviews.isEmpty {
                        Divider()
                        Button("View supplied proofs") { model.showProofs = true }
                    }
                }
                .font(.callout)

        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusRow(_ good: Bool, label: String, goodDetail: String, badDetail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good ? .green : .orange)
            Text(label)
            Spacer()
            Text(good ? goodDetail : badDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func layerList(_ document: BoardDocument) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("LAYERS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(document.layers) { layer in
                Button {
                    model.toggleLayer(layer)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: model.visibleLayerIDs.contains(layer.id) ? "eye" : "eye.slash")
                            .frame(width: 16)
                            .foregroundStyle(layerColor(layer.kind))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(layer.kind.displayName)
                                .foregroundStyle(.primary)
                            Text("\(layer.primitives.count.formatted()) objects")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(layer.fileName)
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
            Text("Inspect the board, not a screenshot")
                .font(.title2.weight(.semibold))
            Text("Drop a fabrication ZIP here, or open one from the sidebar.")
                .foregroundStyle(.secondary)
            Button("Choose Gerber Package") {
                model.isImporting = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if !model.historyEntries.isEmpty {
                Button("Browse fabrication history") {
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
            Text(model.document == nil ? "Reading fabrication package…" : "Rendering layers…")
                .font(.callout.weight(.medium))
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var interactionHint: some View {
        VStack {
            Spacer()
            Text("Drag to orbit · Scroll or pinch to zoom · Double-click to fit")
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
            [entry.name, entry.sourcePath, entry.formatName, entry.generator ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var selectedEntry: PackageHistoryEntry? {
        let id = selection ?? filteredEntries.first?.id
        return entries.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Fabrication History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Packages appear here after they have been inspected.")
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredEntries, selection: $selection) { entry in
                        NavigationLink(value: entry.id) {
                            PackageHistoryRow(entry: entry)
                        }
                        .contextMenu {
                            Button("Relink Source…") { onRelink(entry); dismiss() }
                            Button("Remove from History", role: .destructive) { onRemove(entry) }
                        }
                    }
                }
            }
            .navigationTitle("Fabrication History")
            .searchable(text: $searchText, prompt: "Package, format, or path")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem {
                    Button("Clear History", role: .destructive) { isConfirmingClear = true }
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
                    selection = filteredEntries.first?.id
                }
            } else {
                ContentUnavailableView("Select a Package", systemImage: "shippingbox")
            }
        }
        .onAppear { selection = selection ?? filteredEntries.first?.id }
        .confirmationDialog("Clear all fabrication history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) {
                onClear()
                selection = nil
            }
        } message: {
            Text("This removes the recent-package list. It does not delete any fabrication files.")
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
                Text("\(entry.formatName) · \(entry.boardWidth, format: .number.precision(.fractionLength(1))) × \(entry.boardHeight, format: .number.precision(.fractionLength(1))) mm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Modified \(entry.ageDescription)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if entry.openedCount > 1 {
                Text("×\(entry.openedCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
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

                Button("Open Package", systemImage: "arrow.up.forward.app", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                detailSection("PACKAGE") {
                    LabeledContent("Format", value: entry.formatName)
                    LabeledContent("Source", value: entry.sourceKind.displayName)
                    LabeledContent("Board") {
                        Text("\(entry.boardWidth, format: .number.precision(.fractionLength(2))) × \(entry.boardHeight, format: .number.precision(.fractionLength(2))) mm")
                            .monospacedDigit()
                    }
                    LabeledContent("Layers", value: entry.layerCount.formatted())
                    LabeledContent("Drills", value: entry.drillCount.formatted())
                    LabeledContent("Objects", value: entry.primitiveCount.formatted())
                    if entry.colorSilkscreenSides > 0 {
                        LabeledContent("Color silkscreen", value: "\(entry.colorSilkscreenSides) side\(entry.colorSilkscreenSides == 1 ? "" : "s")")
                    }
                    if entry.packageRole == .jlcpcbProduction {
                        LabeledContent("Review set", value: "JLCPCB engineer output (OK)")
                    } else if entry.packageRole == .nestedArchive {
                        LabeledContent("Container", value: "Nested ZIP")
                    }
                    if let count = entry.enclosedSourceCount, count > 0 {
                        LabeledContent(
                            entry.packageRole == .jlcpcbProduction ? "Original uploads" : "Enclosed archives",
                            value: "\(count) enclosed"
                        )
                    }
                    if let byteCount = entry.byteCount {
                        LabeledContent("Package size") {
                            Text(byteCount.formatted(.byteCount(style: .file)))
                        }
                    }
                    if entry.warningCount > 0 {
                        LabeledContent("Review warnings", value: entry.warningCount.formatted())
                    }
                }

                detailSection("AGE & ACTIVITY") {
                    LabeledContent("Source age", value: entry.ageDescription)
                    if let modifiedAt = entry.modifiedAt {
                        LabeledContent("Modified", value: modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let createdAt = entry.createdAt {
                        LabeledContent("Created", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("First inspected", value: entry.firstOpenedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Last inspected", value: entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Times opened", value: entry.openedCount.formatted())
                }

                if let generator = entry.generator {
                    detailSection("GENERATOR") {
                        Text(generator)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }

                detailSection("LOCATION") {
                    Text(entry.sourcePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Remove from History", role: .destructive, action: onRemove)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle(entry.name)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(document.sidePreviews) { preview in
                        VStack(alignment: .leading, spacing: 8) {
                            proofImage(preview)
                                .scaledToFit()
                                .frame(maxHeight: 620)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("\(preview.side == .top ? "Top" : "Bottom") · \(preview.fileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preview.provenance == .supplied ? "Supplied with source" : "User attachment")
                                .font(.caption2)
                            if preview.purpose == .boardArtwork && preview.mapping != nil {
                                if document.activeArtwork(for: preview.side)?.id == preview.id {
                                    Label("Active board artwork", systemImage: "checkmark.circle")
                                } else { Button("Use as Board Artwork") { onSelect(preview) } }
                            } else { Text("Unmapped gallery proof · not shown on board").font(.caption) }
                            Button(preview.mapping == nil ? "Map to Board…" : "Edit Mapping…") { mappingPreview = preview }
                            if let mapping = preview.mapping {
                                Text("\(mapping.bounds.width, format: .number) × \(mapping.bounds.height, format: .number) mm · \(mapping.orientation == .boardCoordinates ? "Board coordinates" : "Viewed from bottom")")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Color proofs")
            .toolbar {
                ToolbarItemGroup {
                    Button("Reset Top to Supplied Artwork") { onReset(.top) }
                    Button("Reset Bottom to Supplied Artwork") { onReset(.bottom) }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
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


private struct BoundedProofImageView: View {
    let preview: BoardSidePreview
    @State private var image: ProofImage?
    @State private var failure: String?

    var body: some View {
        Group {
            if let image { Image(decorative: image.cgImage, scale: 1).resizable() }
            else if let failure { Text(failure).foregroundStyle(.secondary) }
            else { ProgressView("Loading proof") }
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
                Text("Map the entire image to an axis-aligned rectangle in board millimeters. Initial bounds cover the full fabrication panel, including rails. Enter the artwork’s actual bounds; screenshots with margins need preparation before mapping.")
                    .font(.callout)
                TextField("Minimum X (mm)", value: $minimumX, format: .number)
                TextField("Minimum Y (mm)", value: $minimumY, format: .number)
                TextField("Maximum X (mm)", value: $maximumX, format: .number)
                TextField("Maximum Y (mm)", value: $maximumY, format: .number)
                Picker("Image orientation", selection: $orientation) {
                    Text("Choose orientation").tag(Optional<BoardArtworkMapping.Orientation>.none)
                    Text("Board coordinates · right is +X, up is +Y").tag(Optional(BoardArtworkMapping.Orientation.boardCoordinates))
                    Text("Viewed from bottom · mirror image X").tag(Optional(BoardArtworkMapping.Orientation.viewedFromBottom))
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Map \(preview.side == .top ? "Top" : "Bottom") Artwork")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Mapping") {
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
