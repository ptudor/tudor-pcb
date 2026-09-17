import Foundation

/// English source text for the main window: menu commands, the toolbar, the
/// sidebar (package summary, review status, layer list), the welcome and
/// loading overlays, the 3D view, and the 2D layer inspection view.
///
/// Every key lives in `Localization/Workspace.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md).
///
/// Vocabulary for translators: a *fabrication package* is the ZIP file or
/// folder of Gerber and drill files a designer sends to a board manufacturer;
/// *Gerber* is that file format; a *proof* is a picture of the finished board;
/// *silkscreen* is the printed lettering on a board; *solder mask* is the
/// colored coating over the copper.
nonisolated enum WorkspaceStrings {
    // MARK: Menu commands

    static let openFabricationPackageCommand = LocalizedStringResource("Open Fabrication Package…", table: "Workspace",
        comment: "File menu command that shows the file picker for a fabrication package (a Gerber ZIP or folder). Ends with an ellipsis because a dialog follows.")

    static let fabricationHistoryCommand = LocalizedStringResource("Fabrication History…", table: "Workspace",
        comment: "File menu command that opens the list of packages inspected before. Ends with an ellipsis because a window follows.")

    // MARK: Toolbar

    static let openPackage = LocalizedStringResource("Open Package…", table: "Workspace",
        comment: "Toolbar and sidebar button that shows the file picker for a fabrication package when none is open yet. Ends with an ellipsis because a dialog follows.")

    static let replacePackage = LocalizedStringResource("Replace Package…", table: "Workspace",
        comment: "Toolbar button that shows the file picker to open a different fabrication package in place of the current one. Ends with an ellipsis because a dialog follows.")

    static let openOrReplaceHelp = LocalizedStringResource("Open or replace the fabrication package", table: "Workspace",
        comment: "Tooltip for the toolbar button that opens or replaces the fabrication package.")

    static let fabricationHistory = LocalizedStringResource("Fabrication History", table: "Workspace",
        comment: "Toolbar button (shown with a clock icon) that opens the list of packages inspected before.")

    static let colorProofs = LocalizedStringResource("Color proofs", table: "Workspace",
        comment: "Toolbar button that opens the gallery of proof images (pictures of the finished board).")

    static let perspective = LocalizedStringResource("Perspective", table: "Workspace",
        comment: "Toolbar button that shows the 3D board from an angled perspective camera.")

    static let topView = LocalizedStringResource("Top", table: "Workspace",
        comment: "Toolbar button that turns the 3D board to show its top face straight on.")

    static let bottomView = LocalizedStringResource("Bottom", table: "Workspace",
        comment: "Toolbar button that turns the 3D board to show its bottom face straight on.")

    static let fit = LocalizedStringResource("Fit", table: "Workspace",
        comment: "Toolbar button that zooms the 3D board so the whole board fills the view.")

    static let boardFinish = LocalizedStringResource("Board finish", table: "Workspace",
        comment: "Toolbar menu that chooses the solder mask color the 3D board is painted with.")

    static let finishGreen = LocalizedStringResource("Green", table: "Workspace",
        comment: "Board finish menu item: a green solder mask (the most common board color).")

    static let finishBlack = LocalizedStringResource("Black", table: "Workspace",
        comment: "Board finish menu item: a black solder mask.")

    static let finishBlue = LocalizedStringResource("Blue", table: "Workspace",
        comment: "Board finish menu item: a blue solder mask.")

    static let finishRed = LocalizedStringResource("Red", table: "Workspace",
        comment: "Board finish menu item: a red solder mask.")

    static let finishWhite = LocalizedStringResource("White", table: "Workspace",
        comment: "Board finish menu item: a white solder mask.")

    // MARK: 3D view and fallbacks

    static let untitledBoard = LocalizedStringResource("Board", table: "Workspace",
        comment: "Placeholder shown in place of a board's name when the name is not known.")

    static func twoDFaces(_ boardName: String) -> LocalizedStringResource {
        LocalizedStringResource("2D faces · \(boardName)", table: "Workspace",
            comment: "Heading above flat pictures of the top and bottom faces, shown when the 3D display is unavailable. %@ is the board name. The middle dot is a separator.")
    }

    static let topFace = LocalizedStringResource("Top face", table: "Workspace",
        comment: "Accessibility description of the flat picture of the board's top face.")

    static let bottomFaceInBoardCoordinates = LocalizedStringResource("Bottom face in board coordinates", table: "Workspace",
        comment: "Accessibility description of the flat picture of the board's bottom face, which is drawn un-mirrored (as seen through the board from the top) rather than as a viewer would see it from below.")

    static let retry3D = LocalizedStringResource("Retry 3D", table: "Workspace",
        comment: "Button that tries again to start the 3D display after it failed.")

    static let display3DUnavailable = LocalizedStringResource("3D display unavailable", table: "Workspace",
        comment: "Heading shown when the 3D display could not be started; the reason follows below it.")

    static let workspace = LocalizedStringResource("Workspace", table: "Workspace",
        comment: "Placeholder shown in place of a board's name in the 3D-unavailable panel when no board is open.")

    static let show2DFaces = LocalizedStringResource("Show 2D faces", table: "Workspace",
        comment: "Button that switches from the failed 3D display to flat pictures of the board's two faces.")

    static func opening(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Opening \(fileName)", table: "Workspace",
            comment: "Progress text while a package is being read. %@ is the file or folder name.")
    }

    static let readingPackage = LocalizedStringResource("Reading fabrication package…", table: "Workspace",
        comment: "Progress text while the files of a package are being read and parsed.")

    static let renderingLayers = LocalizedStringResource("Rendering layers…", table: "Workspace",
        comment: "Progress text while the board's layers are being painted for display.")

    static let interactionHint = LocalizedStringResource("Drag to orbit · Scroll or pinch to zoom · Double-click to fit", table: "Workspace",
        comment: "Hint shown at the bottom of the 3D view explaining the mouse and trackpad gestures. The middle dots are separators.")

    static let board3DAccessibilityLabel = LocalizedStringResource("3D fabrication board", table: "Workspace",
        comment: "Accessibility name of the 3D board view on iPhone and iPad.")

    static let board3DAccessibilityHint = LocalizedStringResource("Adjust to zoom. Camera controls also provide top, bottom, and fit views.", table: "Workspace",
        comment: "Accessibility hint for the 3D board view on iPhone and iPad: swiping up or down with VoiceOver zooms, and the toolbar has Top, Bottom, and Fit buttons.")

    // MARK: Choosing a board inside a package

    static let chooseFabricationBoard = LocalizedStringResource("Choose fabrication board", table: "Workspace",
        comment: "Title of the sheet shown when a package contains several boards and the user must pick one.")

    static let severalBoardSets = LocalizedStringResource("This delivery contains several board sets. Choose the source path to inspect.", table: "Workspace",
        comment: "Explanation on the sheet shown when a package contains several boards; a list of the boards follows.")

    // MARK: Sidebar

    static let fabricationReview = LocalizedStringResource("Fabrication review", table: "Workspace",
        comment: "Heading at the top of the sidebar; displayed in capital letters.")

    static let noPackageOpen = LocalizedStringResource("No package open", table: "Workspace",
        comment: "Sidebar heading shown before any fabrication package has been opened.")

    static let openAGerberZip = LocalizedStringResource("Open a Gerber ZIP from EasyEDA, Autodesk Eagle, KiCad, or your manufacturer.", table: "Workspace",
        comment: "Sidebar text before any package is open, naming typical sources of Gerber files. EasyEDA, Autodesk Eagle, and KiCad are circuit design programs; keep their names as written.")

    static func browseRecentPackages(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("Browse \(count) Recent Packages", table: "Workspace",
            comment: "Sidebar button that opens the list of packages inspected before. %lld is how many there are (plural forms are provided).")
    }

    static let localInspectionOnly = LocalizedStringResource("Local inspection only", table: "Workspace",
        comment: "Note at the bottom of the sidebar (with a shield icon): files are read on this device and never uploaded.")

    // MARK: Package summary

    static func layerCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) layers", table: "Workspace",
            comment: "Part of the package summary line. %lld is the number of Gerber layer files (plural forms are provided).")
    }

    static func drillCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) drills", table: "Workspace",
            comment: "Part of the package summary line. %lld is the number of drilled holes and slots (plural forms are provided).")
    }

    static func objectCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) objects", table: "Workspace",
            comment: "Part of the package summary line. %lld is the number of drawn shapes across all layers (plural forms are provided).")
    }

    static func summary(_ layers: String, _ drills: String, _ objects: String) -> LocalizedStringResource {
        LocalizedStringResource("\(layers) · \(drills) · \(objects)", table: "Workspace",
            comment: "Joins the three parts of the package summary line, for example '4 layers · 120 drills · 3,210 objects'. %1$@ is the layer count, %2$@ the drill count, %3$@ the object count. The middle dots are separators.")
    }

    static let jlcpcbEngineerProduction = LocalizedStringResource("JLCPCB engineer production · OK", table: "Workspace",
        comment: "Badge shown when the package is the manufacturer JLCPCB's reviewed production data (their engineers place the checked files in a folder named 'ok'). Keep 'JLCPCB' and 'OK' as written. The middle dot is a separator.")

    static func originalUploadsEnclosed(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) original uploads enclosed", table: "Workspace",
            comment: "Note under the JLCPCB badge: the reviewed package also contains the designer's original ZIP files. %lld is how many (plural forms are provided).")
    }

    static let openedFromEnclosedZip = LocalizedStringResource("Opened from an enclosed Gerber ZIP", table: "Workspace",
        comment: "Note shown when the board was found inside a ZIP archive that was itself inside the opened package.")

    // MARK: Review status

    static let reviewStatus = LocalizedStringResource("Review status", table: "Workspace",
        comment: "Sidebar section heading above the checklist of what the app could and could not verify; displayed in capital letters.")

    static let boardOutline = LocalizedStringResource("Board outline", table: "Workspace",
        comment: "Review checklist row: whether the package has a layer that draws the board's edge.")

    static let outlineLoadedDetail = LocalizedStringResource("Loaded · topology is not manufacturing validation", table: "Workspace",
        comment: "Review checklist detail for the board outline when present: the app read the outline's shape, but that does not prove the board can be manufactured. The middle dot is a separator.")

    static let missing = LocalizedStringResource("Missing", table: "Workspace",
        comment: "Review checklist detail when a board outline or drill file is absent from the package.")

    static let drillMap = LocalizedStringResource("Drill map", table: "Workspace",
        comment: "Review checklist row: whether the package has drill data (hole positions and sizes).")

    static let drillPresentDetail = LocalizedStringResource("Present · registration unverified", table: "Workspace",
        comment: "Review checklist detail for the drill map when present: the app read the holes, but has not checked that they line up with the copper layers. The middle dot is a separator.")

    static let jlcpcbSourceFolder = LocalizedStringResource("Source folder: ok/ · JLCPCB production data", table: "Workspace",
        comment: "Review note shown for JLCPCB reviewed packages: the files came from the folder named 'ok' inside the delivery. Keep 'ok/' and 'JLCPCB' as written. The middle dot is a separator.")

    static func inspectedSource(_ boardName: String, _ selection: String) -> LocalizedStringResource {
        LocalizedStringResource("Inspected source: \(boardName) · \(selection)", table: "Workspace",
            comment: "Review note naming what was inspected. %1$@ is the board name, %2$@ is the path inside the package it was found at (or 'direct input'). The middle dot is a separator.")
    }

    static let directInput = LocalizedStringResource("direct input", table: "Workspace",
        comment: "Used in the 'Inspected source' note when the files were opened directly rather than found inside a nested archive.")

    static let reviewIncomplete = LocalizedStringResource("Review incomplete", table: "Workspace",
        comment: "Review status label (with a warning icon): the app's checks do not amount to a full manufacturing review.")

    static let reviewIncompleteDetail = LocalizedStringResource("Layer completeness, drill registration, and manufacturing suitability have not been verified. Check import warnings and layer display limits.", table: "Workspace",
        comment: "Explanation under 'Review incomplete' listing what the app does not verify.")

    static let topColor = LocalizedStringResource("Top color", table: "Workspace",
        comment: "Review checklist row: the status of the color proof for the board's top face.")

    static let bottomColor = LocalizedStringResource("Bottom color", table: "Workspace",
        comment: "Review checklist row: the status of the color proof for the board's bottom face.")

    static let proofValidationNote = LocalizedStringResource("Proof validation checks image format and bounded pixel decoding; it does not check artwork registration.", table: "Workspace",
        comment: "Review note explaining what accepting a proof image means: the picture decodes safely, but the app has not checked that it lines up with the board.")

    static let factoryPayloadsPresent = LocalizedStringResource("Factory payloads present · validity unverified", table: "Workspace",
        comment: "Review note shown when the package contains the manufacturer's encrypted color silkscreen data, which the app cannot open or check. The middle dot is a separator.")

    static let colorProofOptions = LocalizedStringResource("Color proof options", table: "Workspace",
        comment: "Menu in the review section with commands for attaching and viewing proof images.")

    static let attachTopArtwork = LocalizedStringResource("Attach top artwork…", table: "Workspace",
        comment: "Menu command that shows the file picker for a picture of the board's top face. Ends with an ellipsis because a dialog follows.")

    static let attachBottomArtwork = LocalizedStringResource("Attach bottom artwork…", table: "Workspace",
        comment: "Menu command that shows the file picker for a picture of the board's bottom face. Ends with an ellipsis because a dialog follows.")

    static let viewSuppliedProofs = LocalizedStringResource("View supplied proofs", table: "Workspace",
        comment: "Menu command that opens the gallery of proof images that came with the package.")

    // MARK: Layer list

    static let layers = LocalizedStringResource("Layers", table: "Workspace",
        comment: "Sidebar section heading above the list of the package's layer files; displayed in capital letters.")

    static let layersNote = LocalizedStringResource("Eyes affect outer copper, mask and silk appearance. Outline and machining always define the physical board; inspect their source overlays in 2D.", table: "Workspace",
        comment: "Explanation above the layer list: the eye buttons show or hide copper, solder mask, and silkscreen layers on the 3D board, while the outline and drill layers always shape the board and can only be examined in the 2D view.")

    static func togglePhysicalLayer(_ layerName: String) -> LocalizedStringResource {
        LocalizedStringResource("Toggle physical \(layerName)", table: "Workspace",
            comment: "Accessibility name of the eye button that shows or hides one layer on the 3D board. %@ is the layer name, for example 'Top copper'.")
    }

    static let twoD = LocalizedStringResource("2D", table: "Workspace",
        comment: "Small tag shown beside layers that cannot be toggled on the 3D board and can only be examined in the 2D view.")

    static func inspectIn2D(_ fileName: String) -> LocalizedStringResource {
        LocalizedStringResource("Inspect \(fileName) in 2D", table: "Workspace",
            comment: "Accessibility name of the magnifier button that opens one layer in the 2D view. %@ is the layer's file name.")
    }

    static let inspectDrillsSlotsIn2D = LocalizedStringResource("Inspect Drills / Slots in 2D", table: "Workspace",
        comment: "Button that opens the drilled holes and milled slots in the 2D view.")

    // MARK: Welcome overlay

    static let welcomeTitle = LocalizedStringResource("Inspect the board, not a screenshot", table: "Workspace",
        comment: "Headline of the welcome panel shown before any package is open: the app renders the real manufacturing files rather than a preview image.")

    static let welcomeSubtitle = LocalizedStringResource("Drop a fabrication ZIP here, or open one from the sidebar.", table: "Workspace",
        comment: "Instruction on the welcome panel: the user can drag a ZIP file onto the window or use the sidebar button.")

    static let chooseGerberPackage = LocalizedStringResource("Choose Gerber Package", table: "Workspace",
        comment: "Large button on the welcome panel that shows the file picker for a fabrication package.")

    static let browseFabricationHistory = LocalizedStringResource("Browse fabrication history", table: "Workspace",
        comment: "Opens the list of packages inspected before. Used both as the link-style button on the welcome panel and as the tooltip of the sidebar's clock icon.")

    // MARK: 2D layer inspection

    static let inspectSource = LocalizedStringResource("Inspect source", table: "Workspace",
        comment: "Label of the pop-up menu in the 2D view that chooses which layer file (or the drills) to display.")

    static let drillsAndSlots = LocalizedStringResource("Drills and slots", table: "Workspace",
        comment: "Item in the 2D view's source menu that displays the drilled holes and milled slots.")

    static let physicalBoard = LocalizedStringResource("Physical Board", table: "Workspace",
        comment: "Button that leaves the 2D view and returns to the 3D board.")

    static let showDrillOverlay = LocalizedStringResource("Show drill/slot overlay in this 2D view", table: "Workspace",
        comment: "Checkbox in the 2D view that draws the drilled holes and slots on top of the displayed layer.")

    static let fitSource = LocalizedStringResource("Fit Source", table: "Workspace",
        comment: "Button in the 2D view that zooms out so the whole layer is visible.")

    static let selectedSourceAccessibility = LocalizedStringResource("Selected fabrication source in board coordinates", table: "Workspace",
        comment: "Accessibility description of the picture in the 2D view: the chosen layer drawn in the board's own coordinate system.")

    static let drawingSourceGeometry = LocalizedStringResource("Drawing source geometry", table: "Workspace",
        comment: "Progress text while a layer is being drawn for the 2D view.")

    static func inspectionMetrics(width: String, height: String, millimetersPerPixel: String, pixelWidth: Int, pixelHeight: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(width) × \(height) mm · \(millimetersPerPixel) mm/texel · \(pixelWidth) × \(pixelHeight) pixels", table: "Workspace",
            comment: "Measurements under the 2D view. %1$@ and %2$@ are the shown area's width and height in millimeters ('mm'), %3$@ is how many millimeters one pixel ('texel') covers, %4$lld and %5$lld are the picture's width and height in pixels. Keep the multiplication signs; the middle dots are separators.")
    }

    static let inspectionHint = LocalizedStringResource("Drag to pan; pinch or double-tap to focus. Source geometry is redrawn at each zoom. Outline centerlines are emphasized; drill visibility does not alter physical holes.", table: "Workspace",
        comment: "Help text under the 2D view explaining gestures and what the drawing shows: the board outline is drawn as thin centre lines, and the drill overlay checkbox only affects this picture, not the board.")
}
