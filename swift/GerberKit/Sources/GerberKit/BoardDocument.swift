import Foundation

public struct ColorSilkscreenInfo: Sendable, Hashable, Codable {
    public enum Payload: String, Sendable, Hashable, Codable {
        case encryptedJLC
        case previewImage
    }

    public var side: GerberSide
    public var fileName: String
    public var payload: Payload
    public var byteCount: Int

    public init(side: GerberSide, fileName: String, payload: Payload, byteCount: Int) {
        self.side = side
        self.fileName = fileName
        self.payload = payload
        self.byteCount = byteCount
    }
}

public struct BoardSidePreview: Sendable, Equatable {
    public var side: GerberSide
    public var fileName: String
    public var imageData: Data

    public init(side: GerberSide, fileName: String, imageData: Data) {
        self.side = side
        self.fileName = fileName
        self.imageData = imageData
    }
}

public struct BoardDocument: Sendable, Equatable {
    public var name: String
    public var layers: [GerberLayer]
    public var drills: [DrillHit]
    public var bounds: Bounds2D
    public var thicknessMillimeters: Double
    public var colorSilkscreens: [ColorSilkscreenInfo]
    public var sidePreviews: [BoardSidePreview]
    public var warnings: [String]

    public init(
        name: String,
        layers: [GerberLayer] = [],
        drills: [DrillHit] = [],
        bounds: Bounds2D = Bounds2D(
            minimum: Point2D(x: 0, y: 0),
            maximum: Point2D(x: 100, y: 60)
        ),
        thicknessMillimeters: Double = 1.6,
        colorSilkscreens: [ColorSilkscreenInfo] = [],
        sidePreviews: [BoardSidePreview] = [],
        warnings: [String] = []
    ) {
        self.name = name
        self.layers = layers
        self.drills = drills
        self.bounds = bounds
        self.thicknessMillimeters = thicknessMillimeters
        self.colorSilkscreens = colorSilkscreens
        self.sidePreviews = sidePreviews
        self.warnings = warnings
    }

    public var isEasyEDA: Bool {
        layers.contains { $0.sourceGenerator?.localizedCaseInsensitiveContains("EasyEDA") == true }
    }

    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitives.count }
    }
}
