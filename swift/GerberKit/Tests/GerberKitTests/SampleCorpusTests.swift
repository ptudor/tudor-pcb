import Foundation
import Testing
import XCTest
@testable import GerberKit

@Test func requiredSyntheticBoardLoadsWithoutExternalRepositories() throws {
    let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let board = try FabricationPackageLoader().load(from: root.appending(path: "required-board"))
    #expect(board.layers.count == 2)
    #expect(board.drills == [DrillHit(center: Point2D(x: 5, y: 2), diameter: 1, plated: true)])
    #expect(board.bounds == Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 5)))
    #expect(board.warnings.isEmpty)
}

// One XCTest per optional input makes missing coverage an actual reported skip.
final class OptionalProductionCorpusTests: XCTestCase {
    private var appsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["GERBERKIT_CORPUS_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func load(_ path: String) throws -> BoardDocument {
        let url = appsRoot.appending(path: path)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Optional external corpus unavailable: \(path)")
        return try FabricationPackageLoader().load(from: url)
    }

    private func checkProduction(_ board: BoardDocument) {
        XCTAssertTrue(board.isEasyEDA)
        XCTAssertGreaterThanOrEqual(board.layers.count, 8)
        XCTAssertFalse(board.drills.isEmpty)
        XCTAssertEqual(board.colorSilkscreens.count, 2)
        XCTAssertGreaterThan(board.bounds.width, 10)
        XCTAssertGreaterThan(board.bounds.height, 10)
    }

    func testXLRPad() throws {
        let board = try load("easyeda-tudor/pcb/music-xlr-pad-line-mic/release/2026/09/02/XLR-PAD_Gerbers.zip")
        checkProduction(board)
        XCTAssertEqual(board.bounds.width, 76.2, accuracy: 0.01)
        XCTAssertEqual(board.bounds.height, 76.2, accuracy: 0.01)
    }

    func testLTCCore() throws {
        let board = try load("hollytimecode/pcb/holly-ltc-core/release/2026/09/03/Holly-LTC-CORE_Gerbers.zip")
        checkProduction(board)
        XCTAssertGreaterThanOrEqual(BoardOutlineExtractor.contours(in: board).count, 1)
        XCTAssertGreaterThanOrEqual(BoardOutlineExtractor.edgePaths(in: board).count, 30)
    }

    func testLTCDisplay() throws {
        checkProduction(try load("hollytimecode/pcb/holly-ltc-display/release/2026/09/03/Holly-LTC-DISPLAY_Gerbers.zip"))
    }

    func testLegacyEagle() throws {
        let board = try load("eagle-tudor/pcb/_active/hm-10piggy/untitled folder")
        XCTAssertGreaterThanOrEqual(board.layers.count, 6)
        XCTAssertTrue(board.colorSilkscreens.isEmpty)
    }
}
