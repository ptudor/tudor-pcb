import Foundation

public struct BoardDocument: Sendable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

