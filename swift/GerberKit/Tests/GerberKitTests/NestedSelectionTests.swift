import Foundation
import Testing
@testable import GerberKit

@Test func hiddenNestedAmbiguityPropagatesAndExactSelectionReopens() throws {
    let a = storedZIP([("board.gko", groupingOutline(10)), ("board.gtl", groupingOutline(10))])
    let b = storedZIP([("board.gko", groupingOutline(20)), ("board.gtl", groupingOutline(20))])
    let ambiguous = storedZIP([("a.zip", a), ("b.zip", b)])
    let files = [ZipEntry(name: "ambiguous.zip", data: ambiguous), ZipEntry(name: "c.zip", data: a)]
    var choices: [FabricationSelection] = []
    do { _ = try FabricationPackageLoader().load(files: files, name: "delivery"); Issue.record("Opened C despite hidden ambiguity") }
    catch let error as FabricationSelectionRequired { choices = error.candidates }
    #expect(choices.count == 2)
    let chosen = try #require(choices.first { $0.containers == ["ambiguous.zip", "b.zip"] })
    let board = try FabricationPackageLoader().load(files: files, name: "delivery", selection: chosen)
    #expect(board.bounds.width == 20)
    #expect(board.sourceSelection == chosen)
    let reopened = try FabricationPackageLoader().load(files: files, name: "delivery", selection: board.sourceSelection)
    #expect(reopened == board)
    let deep = [ZipEntry(name: "outer.zip", data: storedZIP(files.map { ($0.name, $0.data) }))]
    do { _ = try FabricationPackageLoader().load(files: deep, name: "deep"); Issue.record("Hidden deep ambiguity") }
    catch let error as FabricationSelectionRequired { #expect(error.candidates.allSatisfy { $0.containers.first == "outer.zip" && $0.containers.count == 3 }) }
    let flat = [ZipEntry(name: "a/board.gko", data: groupingOutline(10)), ZipEntry(name: "b/board.gko", data: groupingOutline(20))]
    let isolated = try FabricationPackageLoader().load(files: flat, name: "flat", selection: .init(group: "b"))
    #expect(isolated.layers.count == 1 && isolated.bounds.width == 20)
}

@Test func corruptNestedCandidatesAndBoundaryFailuresKeepContext() throws {
    let board = storedZIP([("board.gko", groupingOutline(10)), ("board.gtl", groupingOutline(10))])
    let corrupt = [ZipEntry(name: "a/corrupt.zip", data: Data("bad zip".utf8)), ZipEntry(name: "c.zip", data: board)]
    do { _ = try FabricationPackageLoader().load(files: corrupt, name: "delivery"); Issue.record("Ignored corrupt candidate") }
    catch let error as FabricationContainerError { #expect(error.path == ["a/corrupt.zip"]) }
    let withCompleteRoot = corrupt + [ZipEntry(name: "board.gko", data: groupingOutline(10)), ZipEntry(name: "board.gtl", data: groupingOutline(10))]
    #expect(throws: FabricationContainerError.self) { try FabricationPackageLoader().load(files: withCompleteRoot, name: "complete-root") }
    let harmless = storedZIP([("notes.txt", Data("Documentation only".utf8))])
    #expect(try FabricationPackageLoader().load(files: [ZipEntry(name: "notes.zip", data: harmless), ZipEntry(name: "board.zip", data: board)], name: "safe").bounds.width == 10)
    let nested = [ZipEntry(name: "outer.zip", data: storedZIP([("board.zip", board)]))]
    var limits = ImportLimits(); limits.archiveDepth = 2; limits.archives = 2
    #expect(try FabricationPackageLoader(limits: limits).load(files: nested, name: "boundary").bounds.width == 10)
    limits.archiveDepth = 1
    do { _ = try FabricationPackageLoader(limits: limits).load(files: nested, name: "depth"); Issue.record("Exceeded depth") }
    catch let error as ImportLimitError { #expect(error.resource == "archive depth" && error.path.contains("outer.zip") && error.path.contains("board.zip")) }
    limits.archiveDepth = 2; limits.archives = 1
    #expect(throws: ImportLimitError.self) { try FabricationPackageLoader(limits: limits).load(files: nested, name: "count") }
}
