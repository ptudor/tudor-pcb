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

    public static let exposedSubstrate = RGBAColor(red: 0.36, green: 0.28, blue: 0.15)
    public static let exposedMetal = RGBAColor(red: 0.83, green: 0.58, blue: 0.18)

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
    public var warnings: [String] = []

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
        var cache = RasterCache()
        return try render(document, options: options, cache: &cache)
    }

    fileprivate func render(_ document: BoardDocument, options: BoardRenderOptions, cache: inout RasterCache) throws -> BoardTextureSet {
        try Task.checkCancellation()
        try document.validateForRendering()
        let bounds = document.bounds
        let longestSide = max(bounds.width, bounds.height)
        let dimension = min(max(options.maximumTextureDimension, 256), 4_096)
        let scale = Double(dimension) / longestSide
        let width = max(8, Int(ceil(bounds.width * scale)))
        let height = max(8, Int(ceil(bounds.height * scale)))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let maskKey = RasterCache.MaskKey(document: document, width: width, height: height)
        let mask: CGImage
        let topologyWarnings: [String]
        if cache.maskKey == maskKey, let existing = cache.mask { mask = existing; topologyWarnings = cache.maskWarnings }
        else {
            let topology = try BoardOutlineExtractor.topology(in: document)
            mask = try makeBoardMask(width: width, height: height, document: document, bounds: bounds, scale: scale, topology: topology)
            topologyWarnings = topology.warnings
        }
        try Task.checkCancellation()
        let topKey = RasterCache.SideKey(document: document, side: .top, options: options, mask: maskKey)
        let bottomKey = RasterCache.SideKey(document: document, side: .bottom, options: options, mask: maskKey)
        let top: CGImage
        if cache.topKey == topKey, let existing = cache.top { top = existing }
        else { top = try renderSide(.top, document: document, options: options, bounds: bounds, scale: scale, canvas: canvas, boardMask: mask) }
        try Task.checkCancellation()
        let bottom: CGImage
        if cache.bottomKey == bottomKey, let existing = cache.bottom { bottom = existing }
        else { bottom = try renderSide(.bottom, document: document, options: options, bounds: bounds, scale: scale, canvas: canvas, boardMask: mask) }
        try Task.checkCancellation()
        cache.maskKey = maskKey; cache.mask = mask; cache.maskWarnings = topologyWarnings
        cache.topKey = topKey; cache.top = top
        cache.bottomKey = bottomKey; cache.bottom = bottom
        var result = BoardTextureSet(top: top, bottom: bottom, boardMask: mask, pixelWidth: width, pixelHeight: height)
        result.warnings = topologyWarnings
        return result
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
           let preview = document.activeArtwork(for: side) {
            let image = try (preview.validatedImage ?? ProofImageDecoder.decode(preview.imageData, name: preview.fileName)).cgImage
            guard let mapping = preview.mapping else { throw ProofImageError.invalid(preview.fileName + " (unmapped)") }
            try mapping.validate()
            let artworkBounds = mapping.bounds
            let artworkCanvas = CGRect(
                x: (artworkBounds.minimum.x - bounds.minimum.x) * scale,
                y: (artworkBounds.minimum.y - bounds.minimum.y) * scale,
                width: artworkBounds.width * scale,
                height: artworkBounds.height * scale
            )
            context.saveGState()
            context.setAlpha(0.98)
            context.interpolationQuality = .high
            if mapping.orientation == .viewedFromBottom {
                context.translateBy(x: artworkCanvas.midX * 2, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            context.draw(image, in: artworkCanvas)
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
            try composite(layer: layer, color: .exposedSubstrate,
                          context: context, bounds: bounds, scale: scale, canvas: canvas)
        }

        if !copper.isEmpty && !maskOpenings.isEmpty {
            guard let copperContext = makeContext(width: Int(canvas.width), height: Int(canvas.height)) else {
                throw BoardRasterizerError.contextCreation
            }
            // Each source layer resolves its own clear polarity before union.
            for layer in copper {
                try composite(layer: layer, color: RGBAColor(red: 1, green: 1, blue: 1),
                              context: copperContext, bounds: bounds, scale: scale, canvas: canvas)
            }
            guard let copperMask = copperContext.makeImage() else { throw BoardRasterizerError.imageCreation }
            context.saveGState()
            context.clip(to: canvas, mask: copperMask)
            for layer in maskOpenings {
                try composite(layer: layer, color: .exposedMetal,
                              context: context, bounds: bounds, scale: scale, canvas: canvas)
            }
            context.restoreGState()
        }

        let silkLayers = visibleLayers.filter { $0.kind == .silkscreen(side: side) }
        let silkColor = hasColor
            ? RGBAColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 0.92)
            : RGBAColor(red: 0.94, green: 0.94, blue: 0.88, alpha: 0.95)
        for layer in silkLayers {
            try composite(layer: layer, color: silkColor, context: context, bounds: bounds, scale: scale, canvas: canvas)
        }

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
            try Task.checkCancellation()
            try draw(primitive, in: maskContext, bounds: bounds, scale: scale)
        }
        guard let mask = maskContext.makeImage() else { throw BoardRasterizerError.imageCreation }
        context.saveGState()
        context.clip(to: canvas, mask: mask)
        setFill(color, in: context)
        context.fill(canvas)
        context.restoreGState()
    }

    private func makeBoardMask(
        width: Int, height: Int, document: BoardDocument, bounds: Bounds2D,
        scale: Double, topology: BoardOutlineTopology
    ) throws -> CGImage {
        guard let context = makeContext(width: width, height: height) else { throw BoardRasterizerError.contextCreation }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let outlineLayers = document.layers.filter { $0.kind == .outline }
        if outlineLayers.isEmpty {
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(canvas)
        } else {
            if topology.requiresInference {
                // Retain the established panel-rail inference only for unresolved
                // paths, with an explicit diagnostic. Resolved contours below
                // replace this inference throughout their known coverage.
                for layer in outlineLayers {
                    for primitive in layer.primitives where primitive.polarity == .dark {
                        try Task.checkCancellation()
                        try draw(primitive, in: context, bounds: bounds, scale: scale, outlineBarrier: true)
                    }
                }
                try floodOutlineInterior(context: context, width: width, height: height)
                context.setBlendMode(.clear)
                for contour in topology.closedContours {
                    context.addPath(try outlinePath([contour], bounds: bounds, scale: scale))
                    context.fillPath()
                }
                context.setBlendMode(.normal)
            }
            context.setBlendMode(.normal)
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(try outlinePath(topology.materialContours, bounds: bounds, scale: scale))
            context.fillPath(using: .winding)
        }
        context.setBlendMode(.clear)
        try subtractDrills(document.drills, in: context, bounds: bounds, scale: scale)
        guard let image = context.makeImage() else { throw BoardRasterizerError.imageCreation }
        return image
    }

    private func outlinePath(_ contours: [[Point2D]], bounds: Bounds2D, scale: Double) throws -> CGPath {
        let path = CGMutablePath()
        for contour in contours where contour.count >= 3 {
            path.move(to: pixel(contour[0], bounds: bounds, scale: scale))
            for point in contour.dropFirst() { try Task.checkCancellation(); path.addLine(to: pixel(point, bounds: bounds, scale: scale)) }
            path.closeSubpath()
        }
        return path
    }

    private func floodOutlineInterior(context: CGContext, width: Int, height: Int) throws {
        guard let data = context.data else { return }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var outside = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        func isBarrier(_ index: Int) -> Bool { bytes[index * 4 + 3] > 24 }
        func enqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = y * width + x
            guard !outside[index], !isBarrier(index) else { return }
            outside[index] = true
            queue.append(index)
        }

        for x in 0..<width { enqueue(x, 0); enqueue(x, height - 1) }
        for y in 0..<height { enqueue(0, y); enqueue(width - 1, y) }
        var cursor = 0
        while cursor < queue.count {
            if cursor % 1024 == 0 { try Task.checkCancellation() }
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            enqueue(x - 1, y)
            enqueue(x + 1, y)
            enqueue(x, y - 1)
            enqueue(x, y + 1)
        }

        for index in 0..<(width * height) {
            if index % 1024 == 0 { try Task.checkCancellation() }
            let value: UInt8 = outside[index] ? 0 : 255
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
            bytes[index * 4 + 3] = value
        }
    }

    private func draw(_ primitive: GerberPrimitive, in context: CGContext, bounds: Bounds2D, scale: Double, outlineBarrier: Bool = false) throws {
        context.saveGState()
        context.setBlendMode(primitive.polarity == .dark ? .normal : .clear)
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch primitive {
        case let .line(start, end, width, _):
            // The raster flood-fill barrier is an explicit outline-only inference;
            // physical copper strokes use their actual width (zero draws nothing).
            guard outlineBarrier || width > 0 else { context.restoreGState(); return }
            context.setLineWidth(outlineBarrier ? max(0.7, width * scale) : width * scale)
            context.move(to: pixel(start, bounds: bounds, scale: scale))
            context.addLine(to: pixel(end, bounds: bounds, scale: scale))
            context.strokePath()
        case let .arc(start, end, center, clockwise, width, _):
            // The raster flood-fill barrier is an explicit outline-only inference;
            // physical copper strokes use their actual width (zero draws nothing).
            guard outlineBarrier || width > 0 else { context.restoreGState(); return }
            context.setLineWidth(outlineBarrier ? max(0.7, width * scale) : width * scale)
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
            try drawFlash(shape, center: center, in: context, bounds: bounds, scale: scale)
        case let .region(contours, _):
            let path = CGMutablePath()
            for contour in contours where contour.count >= 3 {
                path.move(to: pixel(contour[0], bounds: bounds, scale: scale))
                for point in contour.dropFirst() { try Task.checkCancellation(); path.addLine(to: pixel(point, bounds: bounds, scale: scale)) }
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
    ) throws {
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
                if index % 256 == 0 { try Task.checkCancellation() }
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
        case let .compound(primitives):
            guard let local = shape.localBounds else { return }
            let low = pixel(local.minimum + center, bounds: bounds, scale: scale)
            let high = pixel(local.maximum + center, bounds: bounds, scale: scale)
            let left = max(0, floor(low.x) - 1), bottom = max(0, floor(low.y) - 1)
            let right = min(Double(context.width), ceil(high.x) + 1), top = min(Double(context.height), ceil(high.y) + 1)
            guard left < right, bottom < top else { return }
            let width = Int(right - left), height = Int(top - bottom)
            guard let apertureContext = makeContext(width: width, height: height) else { throw BoardRasterizerError.contextCreation }
            let apertureBounds = Bounds2D(
                minimum: Point2D(x: bounds.minimum.x + left / scale - center.x, y: bounds.minimum.y + bottom / scale - center.y),
                maximum: Point2D(x: bounds.minimum.x + right / scale - center.x, y: bounds.minimum.y + top / scale - center.y))
            for primitive in primitives {
                try Task.checkCancellation()
                try draw(primitive, in: apertureContext, bounds: apertureBounds, scale: scale)
            }
            guard let mask = apertureContext.makeImage() else { throw BoardRasterizerError.imageCreation }
            let rect = CGRect(x: left, y: bottom, width: Double(width), height: Double(height))
            context.saveGState()
            context.clip(to: rect, mask: mask)
            context.fill(rect)
            context.restoreGState()
        case let .custom(points):
            guard let first = points.first else { return }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: centerPixel.x + first.x * scale, y: centerPixel.y + first.y * scale))
            for point in points.dropFirst() {
                try Task.checkCancellation()
                path.addLine(to: CGPoint(x: centerPixel.x + point.x * scale, y: centerPixel.y + point.y * scale))
            }
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }

    private func subtractDrills(_ drills: [DrillHit], in context: CGContext, bounds: Bounds2D, scale: Double) throws {
        for drill in drills {
            try Task.checkCancellation()
            let center = pixel(drill.center, bounds: bounds, scale: scale)
            let end = drill.end.map { pixel($0, bounds: bounds, scale: scale) }
            let diameter = drill.diameter * scale
            context.setFillColor(gray: 1, alpha: 1)
            if let end {
                context.setStrokeColor(gray: 1, alpha: 1)
                context.setLineCap(.round)
                context.setLineWidth(diameter)
                context.move(to: center)
                context.addLine(to: end)
                context.strokePath()
            } else {
                context.fillEllipse(in: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
            }
        }
    }

    private func pixel(_ point: Point2D, bounds: Bounds2D, scale: Double) -> CGPoint {
        CGPoint(x: (point.x - bounds.minimum.x) * scale, y: (point.y - bounds.minimum.y) * scale)
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


/// A workspace owns one session, serializing CPU-heavy import/render operations.
/// Cached masks and unchanged face images survive option changes safely.
public actor FabricationWorkSession {
    private var cache = RasterCache()
    public init() { }
    public func load(_ url: URL, selection: FabricationSelection? = nil) throws -> BoardDocument {
        try Task.checkCancellation()
        return try FabricationPackageLoader().load(from: url, selection: selection)
    }
    public func render(_ document: BoardDocument, options: BoardRenderOptions = .init()) throws -> BoardTextureSet {
        try Task.checkCancellation()
        return try BoardRasterizer().render(document, options: options, cache: &cache)
    }
}

fileprivate struct RasterCache {
    struct MaskKey: Equatable {
        let bounds: Bounds2D
        let outlines: [[GerberPrimitive]]
        let drills: [DrillHit]
        let width: Int
        let height: Int
        init(document: BoardDocument, width: Int, height: Int) {
            bounds = document.bounds
            outlines = document.layers.filter { $0.kind == .outline }.map(\.primitives)
            drills = document.drills
            self.width = width; self.height = height
        }
    }
    struct SideKey: Equatable {
        let mask: MaskKey
        let layers: [GerberLayer]
        let previews: [BoardSidePreview]
        let activeArtworkID: UUID?
        let hasColor: Bool
        let color: RGBAColor
        let artwork: Bool
        init(document: BoardDocument, side: GerberSide, options: BoardRenderOptions, mask: MaskKey) {
            self.mask = mask
            layers = document.layers.filter { $0.kind.side == side && (options.visibleLayerIDs?.contains($0.id) ?? true) }
            previews = document.sidePreviews.filter { $0.side == side }
            activeArtworkID = document.activeArtwork(for: side)?.id
            hasColor = document.colorSilkscreens.contains { $0.side == side }
            color = options.solderMaskColor
            artwork = options.useColorArtwork
        }
    }
    var maskKey: MaskKey?
    var topKey: SideKey?
    var bottomKey: SideKey?
    var mask: CGImage?
    var maskWarnings: [String] = []
    var top: CGImage?
    var bottom: CGImage?
}
