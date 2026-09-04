import SwiftUI

@main
struct GerberMetalApp: App {
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
    }
}

extension Notification.Name {
    static let openFabricationPackage = Notification.Name("GerberMetal.openFabricationPackage")
}

