import Testing
@testable import GerberKit

@Test func documentKeepsItsName() {
    #expect(BoardDocument(name: "Front panel").name == "Front panel")
}

