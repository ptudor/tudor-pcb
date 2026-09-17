import Foundation

/// English source text for controls that appear in several places: sheet
/// buttons, zoom and pan controls, and shared measurements.
///
/// Every key lives in `Localization/Common.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md).
nonisolated enum CommonStrings {
    static let cancel = LocalizedStringResource("Cancel", table: "Common",
        comment: "Button that closes a sheet or dialog without applying anything.")

    static let done = LocalizedStringResource("Done", table: "Common",
        comment: "Button that closes a sheet when the user has finished with it.")

    static let zoomIn = LocalizedStringResource("Zoom In", table: "Common",
        comment: "Button that magnifies the 3D board, a 2D layer view, or a proof image.")

    static let zoomOut = LocalizedStringResource("Zoom Out", table: "Common",
        comment: "Button that shrinks the 3D board, a 2D layer view, or a proof image.")

    static let pan = LocalizedStringResource("Pan", table: "Common",
        comment: "Menu holding the four buttons that move a magnified 2D view or proof image a fixed step in one direction.")

    static let left = LocalizedStringResource("Left", table: "Common",
        comment: "Button in the Pan menu that moves the view one step to the left.")

    static let right = LocalizedStringResource("Right", table: "Common",
        comment: "Button in the Pan menu that moves the view one step to the right.")

    static let up = LocalizedStringResource("Up", table: "Common",
        comment: "Button in the Pan menu that moves the view one step up.")

    static let down = LocalizedStringResource("Down", table: "Common",
        comment: "Button in the Pan menu that moves the view one step down.")

    /// "100.00 × 60.00 mm" — the width and height of a board.
    static func boardDimensions(width: String, height: String) -> LocalizedStringResource {
        LocalizedStringResource("\(width) × \(height) mm", table: "Common",
            comment: "The size of a circuit board. %1$@ is the width and %2$@ the height, both already formatted numbers; 'mm' is millimeters. Keep the multiplication sign between them.")
    }
}
