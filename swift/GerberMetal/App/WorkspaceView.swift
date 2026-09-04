import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @State private var isImporting = false
    @State private var hasDroppedFile = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            ZStack {
                MetalBoardView()
                welcomeOverlay
            }
            .background(Color(red: 0.025, green: 0.032, blue: 0.04))
            .toolbar {
                ToolbarItemGroup {
                    Button("Top", systemImage: "square.3.layers.3d.top.filled") { }
                    Button("Bottom", systemImage: "square.3.layers.3d.bottom.filled") { }
                    Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip, .folder, .data],
            allowsMultipleSelection: false
        ) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .openFabricationPackage)) { _ in
            isImporting = true
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

            VStack(alignment: .leading, spacing: 12) {
                Label("No package open", systemImage: "shippingbox")
                    .font(.headline)
                Text("Open a Gerber ZIP from EasyEDA, Eagle, KiCad, or your manufacturer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open Package…") {
                    isImporting = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Spacer()

            Divider()
            Label("Local inspection only", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
        .background(.regularMaterial)
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
}

