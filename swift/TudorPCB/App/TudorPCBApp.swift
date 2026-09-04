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
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Fabrication Package…") {
                NotificationCenter.default.post(name: .openFabricationPackage, object: nil)
            }
            .keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Button("Fabrication History…") {
                NotificationCenter.default.post(name: .showPackageHistory, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openFabricationPackage = Notification.Name("TudorPCB.openFabricationPackage")
    static let showPackageHistory = Notification.Name("TudorPCB.showPackageHistory")
}
