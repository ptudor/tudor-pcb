import Foundation

/// English source text for failure alerts and for the 3D renderer's errors.
///
/// Every key lives in `Localization/Errors.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md).
nonisolated enum ErrorStrings {
    // MARK: Alert titles, one per operation that can fail

    static let couldNotOpenPackage = LocalizedStringResource("Couldn’t open fabrication package", table: "Errors",
        comment: "Alert title when reading a fabrication package (a Gerber ZIP or folder) failed.")

    static let couldNotSelectPackage = LocalizedStringResource("Couldn’t select fabrication package", table: "Errors",
        comment: "Alert title when the file picker for a fabrication package failed.")

    static let couldNotAttachProof = LocalizedStringResource("Couldn’t attach proof", table: "Errors",
        comment: "Alert title when a proof image (a picture of the finished board) could not be read or decoded.")

    static let couldNotSelectProof = LocalizedStringResource("Couldn’t select proof", table: "Errors",
        comment: "Alert title when the file picker for a proof image failed.")

    static let couldNotMapProof = LocalizedStringResource("Couldn’t map proof", table: "Errors",
        comment: "Alert title when positioning a proof image on the board failed (for example, an empty rectangle).")

    static let couldNotRenderBoard = LocalizedStringResource("Couldn’t render board", table: "Errors",
        comment: "Alert title when painting the board's layers for display failed.")

    // MARK: Alert body and buttons

    static let unknownError = LocalizedStringResource("Unknown error", table: "Errors",
        comment: "Alert body used when an operation failed without any description of the problem.")

    static func sourceFailure(_ source: String, _ detail: String) -> LocalizedStringResource {
        LocalizedStringResource("\(source): \(detail)", table: "Errors",
            comment: "Alert body naming what failed. %1$@ is a file name or path, %2$@ is the description of the problem (a full sentence). Keep the separator between them.")
    }

    static let dismiss = LocalizedStringResource("Dismiss", table: "Errors",
        comment: "Alert button that closes the failure alert.")

    static let selectPackage = LocalizedStringResource("Select Package…", table: "Errors",
        comment: "Alert button, after a package failed to open, that shows the file picker to choose another. Ends with an ellipsis because a dialog follows.")

    static let selectProof = LocalizedStringResource("Select Proof…", table: "Errors",
        comment: "Alert button, after a proof image failed, that shows the file picker to choose another. Ends with an ellipsis because a dialog follows.")

    static let reviewProofMapping = LocalizedStringResource("Review Proof Mapping", table: "Errors",
        comment: "Alert button, after mapping a proof failed, that opens the proof gallery so the mapping can be corrected.")

    static let retryRendering = LocalizedStringResource("Retry Rendering", table: "Errors",
        comment: "Alert button, after painting the board failed, that tries again.")

    // MARK: 3D renderer

    static let noMetalDevice = LocalizedStringResource("A Metal graphics device is unavailable.", table: "Errors",
        comment: "3D display error: no graphics processor supporting Apple's Metal graphics technology was found. 'Metal' is Apple's product name; keep it as written.")

    static let noCommandQueue = LocalizedStringResource("Could not create the Metal command queue.", table: "Errors",
        comment: "3D display error: setting up the graphics processor failed. 'Metal' is Apple's graphics technology; keep it as written.")

    static let noShaderLibrary = LocalizedStringResource("Could not load the board shader library.", table: "Errors",
        comment: "3D display error: the app's compiled graphics programs (shaders) are missing from the app bundle.")

    static let noShaderFunction = LocalizedStringResource("The board shader functions are missing.", table: "Errors",
        comment: "3D display error: the app's compiled graphics programs (shaders) do not contain the expected functions.")

    static let bufferAllocation = LocalizedStringResource("Could not allocate the complete board mesh buffers.", table: "Errors",
        comment: "3D display error: the graphics processor ran out of memory for the board's 3D model.")

    static let commandEncoding = LocalizedStringResource("Could not encode a Metal frame. Retry the 3D display.", table: "Errors",
        comment: "3D display error: drawing one frame failed; the user can press Retry. 'Metal' is Apple's graphics technology; keep it as written.")

    static let meshCapacity = LocalizedStringResource("The board mesh exceeds the supported geometry or GPU buffer capacity.", table: "Errors",
        comment: "3D display error: the board's 3D model has more vertices than the graphics processor ('GPU') can hold.")
}
