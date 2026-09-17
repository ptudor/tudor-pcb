import Foundation

public struct FabricationSelection: Sendable, Hashable, Codable, Identifiable {
    public var containers: [String]
    public var group: String?
    public var id: Self { self }
    public var displayName: String { DiagnosticStrings.joinedPath(containers + (group.map { [$0] } ?? [])) }
    public init(containers: [String] = [], group: String? = nil) { self.containers = containers; self.group = group }
}

public struct FabricationSelectionRequired: Error, LocalizedError, Sendable {
    public let candidates: [FabricationSelection]
    public var errorDescription: String? { DiagnosticStrings.chooseFabricationBoard(candidates.map(\.displayName)) }
}

public struct FabricationContainerError: Error, LocalizedError, Sendable {
    public let path: [String]
    public let reason: String
    public var errorDescription: String? { DiagnosticStrings.subjectMessage(DiagnosticStrings.joinedPath(path), reason) }
}
