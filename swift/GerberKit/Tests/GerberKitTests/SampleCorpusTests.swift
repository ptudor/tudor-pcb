import Foundation
import Testing
@testable import GerberKit

@Test func loadsAvailableProductionCorpus() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appsRoot = packageRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let archives = [
        "easyeda-tudor/pcb/music-xlr-pad-line-mic/release/2026/09/02/XLR-PAD_Gerbers.zip",
        "hollytimecode/pcb/holly-ltc-core/release/2026/09/03/Holly-LTC-CORE_Gerbers.zip",
        "hollytimecode/pcb/holly-ltc-display/release/2026/09/03/Holly-LTC-DISPLAY_Gerbers.zip"
    ]

    for relativePath in archives {
        let url = appsRoot.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        let entries = try ZipArchiveReader().read(Data(contentsOf: url, options: .mappedIfSafe))
        let board = try FabricationPackageLoader().load(files: entries, name: url.lastPathComponent)
        #expect(board.isEasyEDA)
        #expect(board.layers.count >= 8)
        #expect(board.drills.count > 0)
        #expect(board.colorSilkscreens.count == 2)
        #expect(board.bounds.width > 10)
        #expect(board.bounds.height > 10)
        if relativePath.contains("XLR-PAD") {
            #expect(abs(board.bounds.width - 76.2) < 0.01)
            #expect(abs(board.bounds.height - 76.2) < 0.01)
        }
    }

    let legacy = appsRoot.appending(path: "eagle-tudor/pcb/_active/hm-10piggy/untitled folder")
    if FileManager.default.fileExists(atPath: legacy.path) {
        let board = try FabricationPackageLoader().load(from: legacy)
        #expect(board.layers.count >= 6)
        #expect(board.colorSilkscreens.isEmpty)
    }
}
