import Foundation

/// English source text for board layer names and proof states.
///
/// Every key lives in `Resources/Board.xcstrings` together with the comment
/// written here, which the translation pipeline shows to translators. Keys are
/// inserted into the catalog by hand; Xcode's extraction build stays off (see
/// the Localization section of README.md).
enum BoardStrings {
    static var topCopper: String {
        String(localized: "Top copper", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the copper (conductive traces) layer on the top face of the circuit board.")
    }

    static var bottomCopper: String {
        String(localized: "Bottom copper", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the copper (conductive traces) layer on the bottom face of the circuit board.")
    }

    static func innerCopper(_ index: Int) -> String {
        String(localized: "Inner copper \(index)", table: "Board", bundle: Bundle.module,
               comment: "Layer name for one internal copper layer of a multilayer board. %lld is the layer's number counted from the top face (1, 2, 3, …).")
    }

    static var topSolderMask: String {
        String(localized: "Top solder mask", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the solder mask (the colored insulating coating, usually green) on the top face of the board.")
    }

    static var bottomSolderMask: String {
        String(localized: "Bottom solder mask", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the solder mask (the colored insulating coating, usually green) on the bottom face of the board.")
    }

    static var topSilkscreen: String {
        String(localized: "Top silkscreen", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the silkscreen (printed component labels and markings) on the top face of the board.")
    }

    static var bottomSilkscreen: String {
        String(localized: "Bottom silkscreen", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the silkscreen (printed component labels and markings) on the bottom face of the board.")
    }

    static var topPaste: String {
        String(localized: "Top paste", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the solder paste stencil layer for the top face (where paste is applied before components are placed).")
    }

    static var bottomPaste: String {
        String(localized: "Bottom paste", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the solder paste stencil layer for the bottom face (where paste is applied before components are placed).")
    }

    static var boardOutline: String {
        String(localized: "Board outline", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the layer that draws the physical edge (cut line) of the circuit board.")
    }

    static var platedDrills: String {
        String(localized: "Plated drills", table: "Board", bundle: Bundle.module,
               comment: "Layer name: drilled holes whose walls are plated with copper so they conduct between layers.")
    }

    static var nonPlatedDrills: String {
        String(localized: "Non-plated drills", table: "Board", bundle: Bundle.module,
               comment: "Layer name: drilled holes without copper plating, such as mounting holes.")
    }

    static var drills: String {
        String(localized: "Drills", table: "Board", bundle: Bundle.module,
               comment: "Layer name: drilled holes when the file does not say whether they are plated.")
    }

    static var easyEDAColorTop: String {
        String(localized: "EasyEDA color · top", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the full-color silkscreen artwork for the top face exported by the EasyEDA design tool. Keep the product name 'EasyEDA' as written. The middle dot is a separator.")
    }

    static var easyEDAColorBottom: String {
        String(localized: "EasyEDA color · bottom", table: "Board", bundle: Bundle.module,
               comment: "Layer name: the full-color silkscreen artwork for the bottom face exported by the EasyEDA design tool. Keep the product name 'EasyEDA' as written. The middle dot is a separator.")
    }

    static var documentation: String {
        String(localized: "Documentation", table: "Board", bundle: Bundle.module,
               comment: "Layer name: a drawing that documents the board (assembly or fabrication notes) and is not part of the physical board.")
    }

    static var other: String {
        String(localized: "Other", table: "Board", bundle: Bundle.module,
               comment: "Layer name used when the layer's purpose could not be identified.")
    }

    static var drillOverlay: String {
        String(localized: "Drill overlay", table: "Board", bundle: Bundle.module,
               comment: "Name of the layer the app synthesizes to draw drilled holes over the board; it can appear in limit errors in place of a file name.")
    }

    static var noValidatedProof: String {
        String(localized: "No validated proof", table: "Board", bundle: Bundle.module,
               comment: "Status of one board face's color proof: no proof image has been checked and accepted. A proof is a picture of the finished board supplied by the manufacturer or attached by the user.")
    }

    static var validatedGalleryProofUnmapped: String {
        String(localized: "Validated gallery proof · unmapped", table: "Board", bundle: Bundle.module,
               comment: "Status of one board face's color proof: a proof image was checked and accepted but has not been mapped (positioned) onto the board, so it is only shown in the proof gallery. The middle dot is a separator.")
    }

    static var validatedMappedArtwork: String {
        String(localized: "Validated mapped artwork", table: "Board", bundle: Bundle.module,
               comment: "Status of one board face's color proof: a proof image was checked, accepted, and mapped onto the board, so it is drawn on the 3D board.")
    }
}
