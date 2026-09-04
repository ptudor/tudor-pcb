import Foundation

public struct Point2D: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

public struct Bounds2D: Sendable, Hashable, Codable {
    public var minimum: Point2D
    public var maximum: Point2D

    public init(minimum: Point2D, maximum: Point2D) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public var width: Double { maximum.x - minimum.x }
    public var height: Double { maximum.y - minimum.y }
    public var center: Point2D {
        Point2D(x: (minimum.x + maximum.x) / 2, y: (minimum.y + maximum.y) / 2)
    }

    public func expanded(by amount: Double) -> Bounds2D {
        Bounds2D(
            minimum: Point2D(x: minimum.x - amount, y: minimum.y - amount),
            maximum: Point2D(x: maximum.x + amount, y: maximum.y + amount)
        )
    }

    public func union(_ other: Bounds2D) -> Bounds2D {
        Bounds2D(
            minimum: Point2D(
                x: min(minimum.x, other.minimum.x),
                y: min(minimum.y, other.minimum.y)
            ),
            maximum: Point2D(
                x: max(maximum.x, other.maximum.x),
                y: max(maximum.y, other.maximum.y)
            )
        )
    }

    static func containing(_ points: [Point2D]) -> Bounds2D? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return Bounds2D(
            minimum: Point2D(x: minX, y: minY),
            maximum: Point2D(x: maxX, y: maxY)
        )
    }
}

