import SwiftUI
import GerberKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @State private var model = WorkspaceModel()
    @State private var viewer = ViewerController()
    @State private var isImporting = false
    @State private var isImportingTopProof = false
    @State private var isImportingBottomProof = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            ZStack {
                MetalBoardView(document: model.document, textures: model.textures, controller: viewer)
                if model.document == nil { welcomeOverlay }
                if model.isLoading { loadingOverlay }
                if model.document != nil { interactionHint }
            }
            .background(Color(red: 0.025, green: 0.032, blue: 0.04))
            .toolbar {
                ToolbarItemGroup {
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
                    .disabled(model.document == nil || model.document?.colorSilkscreens.isEmpty == false)
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
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
        .onReceive(NotificationCenter.default.publisher(for: .openFabricationPackage)) { _ in
            isImporting = true
        }
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
        .alert("Couldn’t open fabrication package", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $model.showProofs) {
            if let document = model.document { ProofGalleryView(document: document) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("FABRICATION REVIEW", systemImage: "cpu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

                    Button("Open Package…") { isImporting = true }
                        .buttonStyle(.borderedProminent)
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
            statusRow(!document.drills.isEmpty, label: "Drill map", goodDetail: "Aligned", badDetail: "Missing")
            if !document.colorSilkscreens.isEmpty {
                statusRow(
                    document.sidePreviews.contains { $0.fileName.contains("attached-artwork") || $0.fileName.contains("side") },
                    label: "EasyEDA color",
                    goodDetail: "Proof attached",
                    badDetail: "Factory-encrypted"
                )
                Menu("Color proof options", systemImage: "photo.on.rectangle.angled") {
                    Button("Attach top artwork…") { isImportingTopProof = true }
                    Button("Attach bottom artwork…") { isImportingBottomProof = true }
                    if !document.sidePreviews.isEmpty {
                        Divider()
                        Button("View supplied proofs") { model.showProofs = true }
                    }
                }
                .font(.callout)
            } else if !document.sidePreviews.isEmpty {
                Button("View supplied proofs", systemImage: "photo.on.rectangle") { model.showProofs = true }
                    .font(.callout)
            }
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
                isImporting = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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

private struct ProofGalleryView: View {
    let document: BoardDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(Array(document.sidePreviews.enumerated()), id: \.offset) { _, preview in
                        VStack(alignment: .leading, spacing: 8) {
                            proofImage(preview)
                                .scaledToFit()
                                .frame(maxHeight: 620)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("\(preview.side == .top ? "Top" : "Bottom") · \(preview.fileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Color proofs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private func proofImage(_ preview: BoardSidePreview) -> some View {
        #if os(macOS)
        if let image = NSImage(data: preview.imageData) { Image(nsImage: image).resizable() }
        #else
        if let image = UIImage(data: preview.imageData) { Image(uiImage: image).resizable() }
        #endif
    }
}
