import Foundation

/// Shared directed sweep for bounds and tessellation. Finite-resolution Gerber
/// arcs may have unequal start/end radii (Ucamco 4.7.2.2); retain the current
/// start-radius rendering and include the specified endpoint in its bounds.
struct ArcSweep {
    let start: Point2D
    let end: Point2D
    let center: Point2D
    let radius: Double
    let startAngle: Double
    let sweep: Double

    init?(start: Point2D, end: Point2D, center: Point2D, clockwise: Bool) {
        guard [start, end, center].allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let sx = start.x - center.x, sy = start.y - center.y
        let ex = end.x - center.x, ey = end.y - center.y
        let radius = hypot(sx, sy), endRadius = hypot(ex, ey)
        guard radius.isFinite, endRadius.isFinite, radius > 0, endRadius > 0 else { return nil }
        // A center on the extension of the endpoint chord is nonsensical;
        // opposite radii (a semicircle) and coincident endpoints remain valid.
        if start != end, abs(sx * ey - sy * ex) <= 32 * Double.ulpOfOne * radius * endRadius,
           sx * ex + sy * ey > 0 { return nil }
        self.start = start; self.end = end; self.center = center; self.radius = radius
        startAngle = atan2(sy, sx)
        var sweep = atan2(ey, ex) - startAngle
        if clockwise, sweep >= 0 { sweep -= 2 * .pi }
        if !clockwise, sweep <= 0 { sweep += 2 * .pi }
        if start == end { sweep = clockwise ? -2 * .pi : 2 * .pi }
        self.sweep = sweep
    }

    var bounds: Bounds2D {
        var points = [start, end]
        let directions = [Point2D(x: 1, y: 0), Point2D(x: 0, y: 1), Point2D(x: -1, y: 0), Point2D(x: 0, y: -1)]
        for (index, direction) in directions.enumerated() {
            let angle = Double(index) * .pi / 2
            var delta = (sweep < 0 ? startAngle - angle : angle - startAngle).truncatingRemainder(dividingBy: 2 * .pi)
            if delta < 0 { delta += 2 * .pi }
            if delta <= abs(sweep) + 1e-12 {
                points.append(Point2D(x: center.x + direction.x * radius, y: center.y + direction.y * radius))
            }
        }
        return Bounds2D.containing(points)!
    }
}
