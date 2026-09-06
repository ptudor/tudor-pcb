import Foundation

public struct FabricationSelection: Sendable, Hashable, Codable, Identifiable {
    public var containers: [String]
    public var group: String?
    public var id: Self { self }
    public var displayName: String { (containers + (group.map { [$0] } ?? [])).joined(separator: " → ") }
    public init(containers: [String] = [], group: String? = nil) { self.containers = containers; self.group = group }
}

public struct FabricationSelectionRequired: Error, LocalizedError, Sendable {
    public let candidates: [FabricationSelection]
    public var errorDescription: String? { "Choose a fabrication board: " + candidates.map(\.displayName).joined(separator: ", ") }
}

public struct FabricationContainerError: Error, LocalizedError, Sendable {
    public let path: [String]
    public let reason: String
    public var errorDescription: String? { path.joined(separator: " → ") + ": " + reason }
}
