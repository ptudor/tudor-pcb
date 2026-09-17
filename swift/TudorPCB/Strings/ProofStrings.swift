import Foundation

/// English source text for color proofs: the gallery of proof images, the
/// image inspector, and the sheet that maps a proof onto the board.
///
/// Every key lives in `Localization/Proofs.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md).
///
/// Vocabulary for translators: a *proof* is a picture of the finished board
/// supplied by the manufacturer or attached by the user; *artwork* is a proof
/// that has been *mapped* (positioned and scaled) onto the 3D board so the
/// board shows its true colors.
nonisolated enum ProofStrings {
    // MARK: Gallery

    static let colorProofsTitle = LocalizedStringResource("Color proofs", table: "Proofs",
        comment: "Title of the sheet that lists the proof images for the board.")

    static func inspectTopProof(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Inspect top proof \(fileName)", table: "Proofs",
            comment: "Accessibility name of a gallery thumbnail for the board's top face; activating it opens the image inspector. %@ is the image file name.")
    }

    static func inspectBottomProof(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Inspect bottom proof \(fileName)", table: "Proofs",
            comment: "Accessibility name of a gallery thumbnail for the board's bottom face; activating it opens the image inspector. %@ is the image file name.")
    }

    static let inspectImage = LocalizedStringResource("Inspect Image…", table: "Proofs",
        comment: "Gallery button that opens one proof image in the zoomable inspector. Ends with an ellipsis because a sheet follows.")

    static func topProofFile(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Top · \(fileName)", table: "Proofs",
            comment: "Caption under a proof of the board's top face. %@ is the image file name. The middle dot is a separator.")
    }

    static func bottomProofFile(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Bottom · \(fileName)", table: "Proofs",
            comment: "Caption under a proof of the board's bottom face. %@ is the image file name. The middle dot is a separator.")
    }

    static let suppliedWithSource = LocalizedStringResource("Supplied with source", table: "Proofs",
        comment: "Caption noting that the proof image came with the package (from the manufacturer or design program).")

    static let userAttachment = LocalizedStringResource("User attachment", table: "Proofs",
        comment: "Caption noting that the proof image was attached by the user.")

    static let activeBoardArtwork = LocalizedStringResource("Active board artwork", table: "Proofs",
        comment: "Label (with a check mark) on the proof currently drawn on the 3D board for its face.")

    static let useAsBoardArtwork = LocalizedStringResource("Use as Board Artwork", table: "Proofs",
        comment: "Button that makes this mapped proof the one drawn on the 3D board for its face.")

    static let unmappedGalleryProof = LocalizedStringResource("Unmapped gallery proof · not shown on board", table: "Proofs",
        comment: "Caption on a proof that has not been positioned on the board, so it only appears in this gallery. The middle dot is a separator.")

    static let mapToBoard = LocalizedStringResource("Map to Board…", table: "Proofs",
        comment: "Button that opens the sheet for positioning a proof image on the board. Ends with an ellipsis because a sheet follows.")

    static let editMapping = LocalizedStringResource("Edit Mapping…", table: "Proofs",
        comment: "Button that opens the sheet to change how an already mapped proof image is positioned on the board. Ends with an ellipsis because a sheet follows.")

    static func mappingSummary(width: String, height: String, orientation: String) -> LocalizedStringResource {
        LocalizedStringResource("\(width) × \(height) mm · \(orientation)", table: "Proofs",
            comment: "Caption describing a proof's mapping. %1$@ and %2$@ are the mapped area's width and height as formatted numbers ('mm' is millimeters), %3$@ is the orientation ('Board coordinates' or 'Viewed from bottom'). Keep the multiplication sign; the middle dot is a separator.")
    }

    static let orientationBoardCoordinates = LocalizedStringResource("Board coordinates", table: "Proofs",
        comment: "Mapping orientation: the image is drawn as seen from above the board, with +X to the right and +Y up.")

    static let orientationViewedFromBottom = LocalizedStringResource("Viewed from bottom", table: "Proofs",
        comment: "Mapping orientation: the image shows the bottom face as a viewer would see it from below, so it is mirrored left-to-right when placed on the board.")

    static let resetArtwork = LocalizedStringResource("Reset Artwork", table: "Proofs",
        comment: "Toolbar menu with commands that discard the user's chosen artwork and return to the proof supplied with the package.")

    static let resetTopToSupplied = LocalizedStringResource("Reset Top to Supplied Artwork", table: "Proofs",
        comment: "Menu command that returns the top face to the proof image supplied with the package.")

    static let resetBottomToSupplied = LocalizedStringResource("Reset Bottom to Supplied Artwork", table: "Proofs",
        comment: "Menu command that returns the bottom face to the proof image supplied with the package.")

    // MARK: Image inspector

    static let topProof = LocalizedStringResource("Top proof", table: "Proofs",
        comment: "Title of the image inspector when showing a proof of the board's top face.")

    static let bottomProof = LocalizedStringResource("Bottom proof", table: "Proofs",
        comment: "Title of the image inspector when showing a proof of the board's bottom face.")

    static let proofImage = LocalizedStringResource("Proof image", table: "Proofs",
        comment: "Accessibility description of the picture in the image inspector.")

    static func imagePreviewZoom(_ zoom: String) -> LocalizedStringResource {
        LocalizedStringResource("Image preview · \(zoom)×", table: "Proofs",
            comment: "Caption under the image inspector showing the magnification. %@ is the zoom factor as a formatted number, followed by a multiplication sign meaning 'times'. The middle dot is a separator.")
    }

    static let fitImage = LocalizedStringResource("Fit Image", table: "Proofs",
        comment: "Button in the image inspector that resets zoom so the whole proof image is visible.")

    static let loadingProof = LocalizedStringResource("Loading proof", table: "Proofs",
        comment: "Progress text while a proof image is being decoded for display.")

    // MARK: Mapping sheet

    static let mapTopArtwork = LocalizedStringResource("Map Top Artwork", table: "Proofs",
        comment: "Title of the sheet for positioning a proof image on the board's top face.")

    static let mapBottomArtwork = LocalizedStringResource("Map Bottom Artwork", table: "Proofs",
        comment: "Title of the sheet for positioning a proof image on the board's bottom face.")

    static let mappingInstructions = LocalizedStringResource("Map the entire image to an axis-aligned rectangle in board millimeters. Initial bounds cover the full fabrication panel, including rails. Enter the artwork’s actual bounds; screenshots with margins need preparation before mapping.", table: "Proofs",
        comment: "Instructions at the top of the mapping sheet. The user types the rectangle, in millimeters of board space, that the whole image should cover. 'Rails' are the strips of extra board material around a panel of boards.")

    static let minimumX = LocalizedStringResource("Minimum X (mm)", table: "Proofs",
        comment: "Text field label: the left edge of the mapped rectangle in millimeters ('mm').")

    static let minimumY = LocalizedStringResource("Minimum Y (mm)", table: "Proofs",
        comment: "Text field label: the bottom edge of the mapped rectangle in millimeters ('mm').")

    static let maximumX = LocalizedStringResource("Maximum X (mm)", table: "Proofs",
        comment: "Text field label: the right edge of the mapped rectangle in millimeters ('mm').")

    static let maximumY = LocalizedStringResource("Maximum Y (mm)", table: "Proofs",
        comment: "Text field label: the top edge of the mapped rectangle in millimeters ('mm').")

    static let imageOrientation = LocalizedStringResource("Image orientation", table: "Proofs",
        comment: "Label of the pop-up menu choosing how the proof image faces relative to the board.")

    static let chooseOrientation = LocalizedStringResource("Choose orientation", table: "Proofs",
        comment: "Placeholder item in the orientation menu before the user has chosen one.")

    static let orientationBoardCoordinatesDetail = LocalizedStringResource("Board coordinates · right is +X, up is +Y", table: "Proofs",
        comment: "Orientation menu item: the image is drawn as seen from above the board, with +X to the right and +Y up. The middle dot is a separator.")

    static let orientationViewedFromBottomDetail = LocalizedStringResource("Viewed from bottom · mirror image X", table: "Proofs",
        comment: "Orientation menu item: the image shows the bottom face as seen from below, so it is mirrored left-to-right when placed on the board. The middle dot is a separator.")

    static let useMapping = LocalizedStringResource("Use Mapping", table: "Proofs",
        comment: "Button that applies the entered rectangle and orientation and closes the mapping sheet.")
}
