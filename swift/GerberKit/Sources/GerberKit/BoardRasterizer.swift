import CoreGraphics
import Foundation
import ImageIO

public struct BoardRenderOptions: Sendable, Hashable {
    public var visibleLayerIDs: Set<String>?
    public var maximumTextureDimension: Int
    public var solderMaskColor: RGBAColor
    public var useColorArtwork: Bool

    public init(
        visibleLayerIDs: Set<String>? = nil,
        maximumTextureDimension: Int = 2_048,
        solderMaskColor: RGBAColor = .greenMask,
        useColorArtwork: Bool = true
    ) {
        self.visibleLayerIDs = visibleLayerIDs
        self.maximumTextureDimension = maximumTextureDimension
        self.solderMaskColor = solderMaskColor
        self.useColorArtwork = useColorArtwork
    }
}

public struct RGBAColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let greenMask = RGBAColor(red: 0.035, green: 0.23, blue: 0.13)
    public static let whiteMask = RGBAColor(red: 0.82, green: 0.84, blue: 0.82)
    public static let blackMask = RGBAColor(red: 0.025, green: 0.03, blue: 0.032)
    public static let blueMask = RGBAColor(red: 0.025, green: 0.12, blue: 0.32)
    public static let redMask = RGBAColor(red: 0.34, green: 0.035, blue: 0.03)
}

public struct BoardTextureSet: @unchecked Sendable {
    public var top: CGImage
    public var bottom: CGImage
    public var boardMask: CGImage
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(top: CGImage, bottom: CGImage, boardMask: CGImage, pixelWidth: Int, pixelHeight: Int) {
        self.top = top
        self.bottom = bottom
        self.boardMask = boardMask
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum BoardRasterizerError: Error, LocalizedError, Sendable {
    case contextCreation
    case imageCreation

    public var errorDescription: String? {
        switch self {
        case .contextCreation: "Could not allocate the board texture canvas."
        case .imageCreation: "Could not create the rendered board image."
        }
    }
}

public struct BoardRasterizer: Sendable {
    public init() { }

    public func render(_ document: BoardDocument, options: BoardRenderOptions = .init()) throws -> BoardTextureSet {
        let bounds = document.bounds
        let longestSide = max(bounds.width, bounds.height, 0.001)
        let dimension = min(max(options.maximumTextureDimension, 256), 4_096)
        let scale = Double(dimension) / longestSide
        let width = max(8, Int(ceil(bounds.width * scale)))
        let height = max(8, Int(ceil(bounds.height * scale)))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let outline = primaryOutline(in: document)
        let mask = try makeBoardMask(width: width, height: height, bounds: bounds, scale: scale, outline: outline)
        let top = try renderSide(
            .top,
            document: document,
            options: options,
            bounds: bounds,
            scale: scale,
            canvas: canvas,
            boardMask: mask
        )
        let bottom = try renderSide(
            .bottom,
            document: document,
            options: options,
            bounds: bounds,
            scale: scale,
            canvas: canvas,
            boardMask: mask
        )
        return BoardTextureSet(top: top, bottom: bottom, boardMask: mask, pixelWidth: width, pixelHeight: height)
    }

    private func renderSide(
        _ side: GerberSide,
        document: BoardDocument,
        options: BoardRenderOptions,
        bounds: Bounds2D,
        scale: Double,
        canvas: CGRect,
        boardMask: CGImage
    ) throws -> CGImage {
        guard let context = makeContext(width: Int(canvas.width), height: Int(canvas.height)) else {
            throw BoardRasterizerError.contextCreation
        }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.clip(to: canvas, mask: boardMask)

        let hasColor = document.colorSilkscreens.contains { $0.side == side }
        let baseColor = hasColor ? RGBAColor.whiteMask : options.solderMaskColor
        setFill(baseColor, in: context)
        context.fill(canvas)

        if options.useColorArtwork,
           let preview = preferredArtwork(for: side, in: document.sidePreviews),
           let source = CGImageSourceCreateWithData(preview.imageData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            context.saveGState()
            context.setAlpha(0.98)
            context.interpolationQuality = .high
            context.draw(image, in: canvas)
            context.restoreGState()
        }

        let visibleLayers = document.layers.filter { layer in
            options.visibleLayerIDs?.contains(layer.id) ?? true
        }
        let copper = visibleLayers.filter {
            guard case let .copper(layerSide, index) = $0.kind else { return false }
            return index == nil && layerSide == side
        }
        for layer in copper {
            try composite(layer: layer, color: RGBAColor(red: 0.36, green: 0.23, blue: 0.06, alpha: 0.34),
                          context: context, bounds: bounds, scale: scale, canvas: canvas)
        }

        let maskOpenings = visibleLayers.filter { $0.kind == .solderMask(side: side) }
        for layer in maskOpenings {
            try composite(layer: layer, color: RGBAColor(red: 0.83, green: 0.58, blue: 0.18, alpha: 1),
                          context: context, bounds: bounds, scale: scale, canvas: canvas)
        }

        let silkLayers = visibleLayers.filter { $0.kind == .silkscreen(side: side) }
        let silkColor = hasColor
            ? RGBAColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 0.92)
            : RGBAColor(red: 0.94, green: 0.94, blue: 0.88, alpha: 0.95)
        for layer in silkLayers {
            try composite(layer: layer, color: silkColor, context: context, bounds: bounds, scale: scale, canvas: canvas)
        }

        drawDrills(document.drills, in: context, bounds: bounds, scale: scale)
        guard let image = context.makeImage() else { throw BoardRasterizerError.imageCreation }
        return image
    }

    private func composite(
        layer: GerberLayer,
        color: RGBAColor,
        context: CGContext,
        bounds: Bounds2D,
        scale: Double,
        canvas: CGRect
    ) throws {
        guard let maskContext = makeContext(width: Int(canvas.width), height: Int(canvas.height)) else {
            throw BoardRasterizerError.contextCreation
        }
        for primitive in layer.primitives {
            draw(primitive, in: maskContext, bounds: bounds, scale: scale)
        }
        guard let mask = maskContext.makeImage() else { throw BoardRasterizerError.imageCreation }
        context.saveGState()
        context.clip(to: canvas, mask: mask)
        setFill(color, in: context)
        context.fill(canvas)
        context.restoreGState()
    }

    private func makeBoardMask(
        width: Int,
        height: Int,
        bounds: Bounds2D,
        scale: Double,
        outline: [Point2D]?
    ) throws -> CGImage {
        guard let context = makeContext(width: width, height: height) else {
            throw BoardRasterizerError.contextCreation
        }
        context.setFillColor(gray: 1, alpha: 1)
        if let outline, outline.count >= 3 {
            let path = CGMutablePath()
            path.move(to: pixel(outline[0], bounds: bounds, scale: scale))
            for point in outline.dropFirst() { path.addLine(to: pixel(point, bounds: bounds, scale: scale)) }
            path.closeSubpath()
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        } else {
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let image = context.makeImage() else { throw BoardRasterizerError.imageCreation }
        return image
    }

    private func draw(_ primitive: GerberPrimitive, in context: CGContext, bounds: Bounds2D, scale: Double) {
        context.saveGState()
        context.setBlendMode(primitive.polarity == .dark ? .normal : .clear)
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch primitive {
        case let .line(start, end, width, _):
            context.setLineWidth(max(0.7, width * scale))
            context.move(to: pixel(start, bounds: bounds, scale: scale))
            context.addLine(to: pixel(end, bounds: bounds, scale: scale))
            context.strokePath()
        case let .arc(start, end, center, clockwise, width, _):
            context.setLineWidth(max(0.7, width * scale))
            let path = CGMutablePath()
            path.move(to: pixel(start, bounds: bounds, scale: scale))
            let centerPixel = pixel(center, bounds: bounds, scale: scale)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            var endAngle = atan2(end.y - center.y, end.x - center.x)
            if start == end { endAngle = startAngle + (clockwise ? -2 * .pi : 2 * .pi) }
            path.addArc(
                center: centerPixel,
                radius: hypot(start.x - center.x, start.y - center.y) * scale,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: clockwise
            )
            context.addPath(path)
            context.strokePath()
        case let .flash(center, shape, _):
            drawFlash(shape, center: center, in: context, bounds: bounds, scale: scale)
        case let .region(contours, _):
            let path = CGMutablePath()
            for contour in contours where contour.count >= 3 {
                path.move(to: pixel(contour[0], bounds: bounds, scale: scale))
                for point in contour.dropFirst() { path.addLine(to: pixel(point, bounds: bounds, scale: scale)) }
                path.closeSubpath()
            }
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
    }

    private func drawFlash(
        _ shape: ApertureShape,
        center: Point2D,
        in context: CGContext,
        bounds: Bounds2D,
        scale: Double
    ) {
        let centerPixel = pixel(center, bounds: bounds, scale: scale)
        switch shape {
        case let .circle(diameter):
            let diameterPixels = diameter * scale
            context.fillEllipse(in: CGRect(
                x: centerPixel.x - diameterPixels / 2,
                y: centerPixel.y - diameterPixels / 2,
                width: diameterPixels,
                height: diameterPixels
            ))
        case let .rectangle(width, height):
            context.fill(CGRect(
                x: centerPixel.x - width * scale / 2,
                y: centerPixel.y - height * scale / 2,
                width: width * scale,
                height: height * scale
            ))
        case let .obround(width, height):
            let rect = CGRect(
                x: centerPixel.x - width * scale / 2,
                y: centerPixel.y - height * scale / 2,
                width: width * scale,
                height: height * scale
            )
            let radius = min(rect.width, rect.height) / 2
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        case let .polygon(diameter, vertices, rotationDegrees):
            let count = max(vertices, 3)
            let path = CGMutablePath()
            for index in 0..<count {
                let angle = (Double(index) / Double(count) * 2 * .pi) + rotationDegrees * .pi / 180
                let point = CGPoint(
                    x: centerPixel.x + cos(angle) * diameter * scale / 2,
                    y: centerPixel.y + sin(angle) * diameter * scale / 2
                )
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        case let .custom(points):
            guard let first = points.first else { return }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: centerPixel.x + first.x * scale, y: centerPixel.y + first.y * scale))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: centerPixel.x + point.x * scale, y: centerPixel.y + point.y * scale))
            }
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }

    private func drawDrills(_ drills: [DrillHit], in context: CGContext, bounds: Bounds2D, scale: Double) {
        for drill in drills {
            let center = pixel(drill.center, bounds: bounds, scale: scale)
            let diameter = max(1, drill.diameter * scale)
            if drill.plated == true {
                context.setFillColor(red: 0.73, green: 0.48, blue: 0.14, alpha: 1)
                context.fillEllipse(in: CGRect(
                    x: center.x - diameter * 0.72,
                    y: center.y - diameter * 0.72,
                    width: diameter * 1.44,
                    height: diameter * 1.44
                ))
            }
            context.setFillColor(red: 0.012, green: 0.014, blue: 0.016, alpha: 1)
            context.fillEllipse(in: CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
        }
    }

    private func primaryOutline(in document: BoardDocument) -> [Point2D]? {
        let layers = document.layers.filter { $0.kind == .outline }
        var closedContours: [[Point2D]] = []
        for layer in layers {
            var current: [Point2D] = []
            func finish() {
                guard current.count >= 3,
                      let first = current.first,
                      let last = current.last,
                      distance(first, last) < 0.08 else {
                    current.removeAll(keepingCapacity: true)
                    return
                }
                closedContours.append(current)
                current.removeAll(keepingCapacity: true)
            }

            for primitive in layer.primitives where primitive.polarity == .dark {
                let segment: [Point2D]
                switch primitive {
                case let .line(start, end, _, _): segment = [start, end]
                case let .arc(start, end, center, clockwise, _, _):
                    segment = [start] + flattenArc(start: start, end: end, center: center, clockwise: clockwise)
                case let .region(contours, _):
                    closedContours += contours
                    continue
                case .flash:
                    continue
                }
                if current.isEmpty {
                    current = segment
                } else if let last = current.last, let first = segment.first, distance(last, first) < 0.08 {
                    current.append(contentsOf: segment.dropFirst())
                    if let chainFirst = current.first, let chainLast = current.last,
                       distance(chainFirst, chainLast) < 0.08 { finish() }
                } else {
                    finish()
                    current = segment
                }
            }
            finish()
        }
        return closedContours.max { abs(polygonArea($0)) < abs(polygonArea($1)) }
    }

    private func flattenArc(start: Point2D, end: Point2D, center: Point2D, clockwise: Bool) -> [Point2D] {
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.000_001 else { return [end] }
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        var sweep = atan2(end.y - center.y, end.x - center.x) - startAngle
        if clockwise, sweep >= 0 { sweep -= 2 * .pi }
        if !clockwise, sweep <= 0 { sweep += 2 * .pi }
        if start == end { sweep = clockwise ? -2 * .pi : 2 * .pi }
        let count = max(8, Int(ceil(abs(sweep) * radius / 0.1)))
        return (1...count).map { index in
            let angle = startAngle + sweep * Double(index) / Double(count)
            return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private func preferredArtwork(for side: GerberSide, in previews: [BoardSidePreview]) -> BoardSidePreview? {
        previews.first {
            guard $0.side == side else { return false }
            let lower = $0.fileName.lowercased()
            return lower.contains("top-side") || lower.contains("bottom-side") || lower.contains("artwork")
        }
    }

    private func pixel(_ point: Point2D, bounds: Bounds2D, scale: Double) -> CGPoint {
        CGPoint(x: (point.x - bounds.minimum.x) * scale, y: (point.y - bounds.minimum.y) * scale)
    }

    private func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func polygonArea(_ points: [Point2D]) -> Double {
        guard points.count >= 3 else { return 0 }
        var area = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        return area / 2
    }

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func setFill(_ color: RGBAColor, in context: CGContext) {
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

