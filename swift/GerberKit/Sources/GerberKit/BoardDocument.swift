import Foundation

public enum FabricationPackageRole: String, Sendable, Hashable, Codable {
    case direct
    case nestedArchive
    case jlcpcbProduction
}

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

public struct BoardArtworkMapping: Sendable, Equatable {
    public enum Orientation: String, Sendable, CaseIterable { case boardCoordinates, viewedFromBottom }
    public var bounds: Bounds2D
    public var orientation: Orientation
    public init(bounds: Bounds2D, orientation: Orientation) { self.bounds = bounds; self.orientation = orientation }
    public func validate() throws {
        try GeometryLimits.point(bounds.minimum, context: "artwork mapping")
        try GeometryLimits.point(bounds.maximum, context: "artwork mapping")
        try GeometryLimits.require(bounds.width > 0 && bounds.height > 0, "positive artwork mapping dimensions", "artwork mapping")
    }
}

public enum BoardProofState: String, Sendable, Codable {
    case missing, galleryOnly, mappedArtwork
    public var label: String {
        switch self {
        case .missing: "No validated proof"
        case .galleryOnly: "Validated gallery proof · unmapped"
        case .mappedArtwork: "Validated mapped artwork"
        }
    }
}

public enum BoardPreviewPurpose: String, Sendable { case galleryProof, boardArtwork }
public enum BoardPreviewProvenance: String, Sendable { case supplied, attached }

public struct BoardSidePreview: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var purpose: BoardPreviewPurpose
    public var provenance: BoardPreviewProvenance
    public var mapping: BoardArtworkMapping?
    public var side: GerberSide
    public var fileName: String
    public var imageData: Data { didSet { validatedImage = nil } }
    public var validatedImage: ProofImage?

    public init(side: GerberSide, fileName: String, imageData: Data, validatedImage: ProofImage? = nil,
                id: UUID = UUID(), purpose: BoardPreviewPurpose? = nil, provenance: BoardPreviewProvenance = .supplied, mapping: BoardArtworkMapping? = nil) {
        self.id = id
        // Migrate existing callers once; renderers consume explicit purpose.
        let legacyName = fileName.lowercased()
        self.purpose = purpose ?? (legacyName.contains("artwork") || legacyName.contains("top-side") || legacyName.contains("bottom-side") ? .boardArtwork : .galleryProof)
        self.provenance = provenance
        self.mapping = mapping
        self.side = side
        self.fileName = fileName
        self.imageData = imageData
        self.validatedImage = validatedImage
    }
}

extension BoardSidePreview {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.purpose == rhs.purpose && lhs.provenance == rhs.provenance && lhs.mapping == rhs.mapping &&
        lhs.side == rhs.side && lhs.fileName == rhs.fileName && lhs.imageData == rhs.imageData
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
    public var packageRole: FabricationPackageRole
    public var enclosedSourceArchives: [String]
    public var sourceSelection: FabricationSelection? = nil
    public var activeArtworkIDs: [GerberSide: UUID] = [:]

    public func activeArtwork(for side: GerberSide) -> BoardSidePreview? {
        if let id = activeArtworkIDs[side] {
            return sidePreviews.first { $0.id == id && $0.side == side && $0.purpose == .boardArtwork && $0.mapping != nil }
        }
        let supplied = sidePreviews.filter { $0.side == side && $0.purpose == .boardArtwork && $0.provenance == .supplied && $0.mapping != nil }
        return supplied.count == 1 ? supplied[0] : nil
    }

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
        warnings: [String] = [],
        packageRole: FabricationPackageRole = .direct,
        enclosedSourceArchives: [String] = []
    ) {
        self.name = name
        self.layers = layers
        self.drills = drills
        self.bounds = bounds
        self.thicknessMillimeters = thicknessMillimeters
        self.colorSilkscreens = colorSilkscreens
        self.sidePreviews = sidePreviews
        self.warnings = warnings
        self.packageRole = packageRole
        self.enclosedSourceArchives = enclosedSourceArchives
    }

    public func proofState(for side: GerberSide) -> BoardProofState {
        if let active = activeArtwork(for: side), active.validatedImage != nil { return .mappedArtwork }
        return sidePreviews.contains { $0.side == side && $0.validatedImage != nil } ? .galleryOnly : .missing
    }

    public mutating func refreshProofWarnings() {
        warnings.removeAll { $0.hasPrefix("[Color proof]") }
        for payload in colorSilkscreens where payload.payload == .encryptedJLC && payload.byteCount == 0 {
            warnings.append("[Color proof] \(payload.fileName): factory payload is empty; validity has not been established.")
        }
        for side in [GerberSide.top, .bottom] where colorSilkscreens.contains(where: { $0.side == side && $0.payload == .encryptedJLC }) {
            switch proofState(for: side) {
            case .mappedArtwork: break
            case .galleryOnly:
                warnings.append("[Color proof] \(side.rawValue.capitalized): a validated gallery proof is available but unmapped; exact board colors remain unavailable.")
            case .missing:
                warnings.append("[Color proof] \(side.rawValue.capitalized): factory payload present, validity unverified; exact colors are unavailable without a validated proof.")
            }
        }
    }

    public var isEasyEDA: Bool {
        layers.contains { $0.sourceGenerator?.localizedCaseInsensitiveContains("EasyEDA") == true }
    }

    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitives.count }
    }
}
