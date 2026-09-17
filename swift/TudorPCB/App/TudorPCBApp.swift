import SwiftUI

@main
struct TudorPCBApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceView()
        }
        .commands {
            GerberCommands()
        }
        #if os(macOS)
        .defaultSize(width: 1_280, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }
}

private struct GerberCommands: Commands {
    @FocusedValue(\.fabricationWorkspace) private var workspace
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(WorkspaceStrings.openFabricationPackageCommand) {
                workspace?.isImporting = true
            }
            .keyboardShortcut("o")
            .disabled(workspace == nil)
        }
        CommandGroup(after: .newItem) {
            Button(WorkspaceStrings.fabricationHistoryCommand) {
                workspace?.isShowingHistory = true
            }.disabled(workspace == nil)
        }
    }
}

private struct FabricationWorkspaceKey: FocusedValueKey {
    typealias Value = WorkspaceModel
}
extension FocusedValues {
    var fabricationWorkspace: WorkspaceModel? {
        get { self[FabricationWorkspaceKey.self] }
        set { self[FabricationWorkspaceKey.self] = newValue }
    }
}
