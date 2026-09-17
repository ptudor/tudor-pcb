import Foundation

/// English source text for the fabrication history: the list of packages
/// inspected before, its detail panel, the messages about restoring access to
/// those files, and the recovery of a damaged history store.
///
/// Every key lives in `Localization/History.xcstrings` together with the
/// comment written here, which the translation pipeline shows to translators.
/// Keys are inserted into the catalog by hand; Xcode's extraction build stays
/// off (see the Localization section of README.md).
///
/// Vocabulary for translators: a *fabrication package* is the ZIP file or
/// folder of Gerber and drill files sent to a board manufacturer; *relinking*
/// means choosing the file again so the app may read it (the system revokes
/// access when a file moves).
nonisolated enum HistoryStrings {
    // MARK: Source kinds and formats

    static let sourceKindArchive = LocalizedStringResource("Gerber ZIP", table: "History",
        comment: "Kind of source a history entry was opened from: a ZIP archive of Gerber files.")

    static let sourceKindFolder = LocalizedStringResource("Fabrication folder", table: "History",
        comment: "Kind of source a history entry was opened from: a folder of Gerber files.")

    static let sourceKindLayer = LocalizedStringResource("Gerber layer", table: "History",
        comment: "Kind of source a history entry was opened from: a single Gerber layer file.")

    static let formatJLCPCBProduction = LocalizedStringResource("JLCPCB production", table: "History",
        comment: "Package format: production data reviewed by the manufacturer JLCPCB. Keep 'JLCPCB' as written.")

    static let formatEasyEDAPro = LocalizedStringResource("EasyEDA Pro", table: "History",
        comment: "Package format: exported by the EasyEDA Pro circuit design program. Keep the product name as written.")

    static let formatAutodeskEagle = LocalizedStringResource("Autodesk Eagle", table: "History",
        comment: "Package format: exported by the Autodesk Eagle circuit design program. Keep the product name as written.")

    static let formatKiCad = LocalizedStringResource("KiCad", table: "History",
        comment: "Package format: exported by the KiCad circuit design program. Keep the product name as written.")

    static let formatAltium = LocalizedStringResource("Altium", table: "History",
        comment: "Package format: exported by the Altium circuit design program. Keep the product name as written.")

    static let formatRS274X = LocalizedStringResource("RS-274X", table: "History",
        comment: "Package format: generic Gerber files whose design program is unknown. RS-274X is the name of the Gerber standard; keep it as written.")

    // MARK: Availability of the original file

    static let checkingSourceAccess = LocalizedStringResource("Checking source access…", table: "History",
        comment: "Status shown in the history detail panel while the app checks whether the original file or folder can still be read.")

    static let sourceAvailable = LocalizedStringResource("Source available", table: "History",
        comment: "Status in the history detail panel: the original file or folder can be read.")

    static let sourceMoved = LocalizedStringResource("Source moved · bookmark resolves", table: "History",
        comment: "Status in the history detail panel: the original file or folder was moved, but the app's saved reference still finds it. The middle dot is a separator.")

    static let sourceMissing = LocalizedStringResource("Source missing", table: "History",
        comment: "Status in the history detail panel: the original file or folder no longer exists.")

    static let sourceInaccessible = LocalizedStringResource("Source inaccessible · relink required", table: "History",
        comment: "Status in the history detail panel: the app is no longer allowed to read the original file or folder, and the user must choose it again. The middle dot is a separator.")

    // MARK: Access problems

    static func persistentAccessUnavailable(_ path: String) -> LocalizedStringResource {
        LocalizedStringResource("Persistent access to \(path) is unavailable. Reselect the original file or folder to relink it.", table: "History",
            comment: "Message shown when the app's saved permission to read a file from history no longer works. %@ is the file or folder path.")
    }

    static func fileIdentityChanged(_ path: String) -> LocalizedStringResource {
        LocalizedStringResource("\(path) (the file identity changed)", table: "History",
            comment: "Used as the path in the 'Persistent access' message when the file at that path is a different file from the one recorded (it was replaced). %@ is the path.")
    }

    static func persistentAccessNotSaved(_ detail: String) -> LocalizedStringResource {
        LocalizedStringResource("The package opened, but persistent access could not be saved: \(detail) Reselect the source to retry.", table: "History",
            comment: "Message shown when a package opened but the app could not save permission to reopen it later from history. %@ is the operating system's description of the problem (a full sentence ending with a period).")
    }

    static func couldNotRestoreAccess(_ path: String, _ detail: String) -> LocalizedStringResource {
        LocalizedStringResource("Could not restore access to \(path): \(detail) Reselect the source to relink it.", table: "History",
            comment: "Message shown when reopening a package from history fails. %1$@ is the file or folder path, %2$@ is the operating system's description of the problem (a full sentence ending with a period).")
    }

    static let historyAccessNeedsAttention = LocalizedStringResource("History access needs attention", table: "History",
        comment: "Title of the alert shown when a package in history can no longer be read.")

    static let reselectSource = LocalizedStringResource("Reselect Source…", table: "History",
        comment: "Alert button that shows the file picker so the user can choose the package again. Ends with an ellipsis because a dialog follows.")

    static let later = LocalizedStringResource("Later", table: "History",
        comment: "Alert button that dismisses the access problem without choosing the file now.")

    // MARK: History store recovery

    static let unsupportedHistoryFormat = LocalizedStringResource("Unsupported history format/version.", table: "History",
        comment: "Reason the saved history could not be read: it was written in a format this version of the app does not understand.")

    static let duplicateHistoryIdentity = LocalizedStringResource("Duplicate history identity.", table: "History",
        comment: "Reason a saved history record was rejected: two records share the same identifier.")

    static let historyChangedDuringRecovery = LocalizedStringResource("History changed during recovery. Reload it before choosing recovery again.", table: "History",
        comment: "Error shown when the saved history was modified (for example by another window) between reading it and repairing it.")

    static let invalidHistoryStatistics = LocalizedStringResource("History contains invalid activity or board statistics.", table: "History",
        comment: "Reason a saved history record was rejected: its dates, counts, or board size are impossible values.")

    static func unreadableRecords(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) history records could not be read.", table: "History",
            comment: "First sentence of the history recovery message. %lld is how many saved records are damaged (plural forms are provided).")
    }

    static func recoverableRecords(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) valid records are recoverable.", table: "History",
            comment: "Second sentence of the history recovery message. %lld is how many saved records are intact (plural forms are provided).")
    }

    static let savingPausedNote = LocalizedStringResource("Original data is preserved; saving is paused until you choose recovery.", table: "History",
        comment: "Last sentence of the history recovery message: nothing is overwritten until the user decides.")

    static func sentences(_ first: String, _ second: String, _ third: String) -> LocalizedStringResource {
        LocalizedStringResource("\(first) \(second) \(third)", table: "History",
            comment: "Joins three complete sentences into one message. Use whatever separates sentences in your language (a space in most languages, nothing in Chinese or Japanese).")
    }

    static func historyUnreadable(_ detail: String) -> LocalizedStringResource {
        LocalizedStringResource("History could not be read: \(detail) Original data is preserved; saving is paused until you choose recovery.", table: "History",
            comment: "History recovery message when the whole saved history is unreadable. %@ is the description of the problem (a full sentence ending with a period).")
    }

    static func historyNotSaved(_ detail: String) -> LocalizedStringResource {
        LocalizedStringResource("History was not saved: \(detail)", table: "History",
            comment: "Error shown when the history could not be written to disk. %@ is the description of the problem (a full sentence).")
    }

    static let historyNeedsRecovery = LocalizedStringResource("History needs recovery", table: "History",
        comment: "Title of the alert shown when the saved history is damaged.")

    static let backUpAndRecover = LocalizedStringResource("Back Up Original and Recover Valid History", table: "History",
        comment: "Alert button that keeps a copy of the damaged history and continues with the records that could be read.")

    static let keepOriginal = LocalizedStringResource("Keep Original", table: "History",
        comment: "Alert button that leaves the damaged history untouched (the app will not save history until it is repaired).")

    // MARK: Browser

    static let fabricationHistoryTitle = LocalizedStringResource("Fabrication History", table: "History",
        comment: "Window title of the list of packages inspected before.")

    static let noFabricationHistory = LocalizedStringResource("No Fabrication History", table: "History",
        comment: "Placeholder title shown when no package has been inspected yet.")

    static let packagesAppearAfterInspection = LocalizedStringResource("Packages appear here after they have been inspected.", table: "History",
        comment: "Placeholder explanation shown when no package has been inspected yet.")

    static let selectAPackage = LocalizedStringResource("Select a Package", table: "History",
        comment: "Placeholder shown in the detail panel when no history entry is selected.")

    static let searchPrompt = LocalizedStringResource("Package, format, or path", table: "History",
        comment: "Placeholder text in the history search field, naming what can be searched for.")

    static let relinkSource = LocalizedStringResource("Relink Source…", table: "History",
        comment: "Context menu command that shows the file picker so the user can choose the package again. Ends with an ellipsis because a dialog follows.")

    static let removeFromHistory = LocalizedStringResource("Remove from History", table: "History",
        comment: "Command that deletes one entry from the history list (the package's files are not touched).")

    static let clearHistory = LocalizedStringResource("Clear History", table: "History",
        comment: "Button that deletes every entry from the history list; also the confirming button in the dialog that follows.")

    static let clearAllConfirmation = LocalizedStringResource("Clear all fabrication history?", table: "History",
        comment: "Title of the confirmation dialog before deleting every history entry.")

    static let clearAllMessage = LocalizedStringResource("This removes the recent-package list. It does not delete any fabrication files.", table: "History",
        comment: "Explanation in the confirmation dialog before deleting every history entry.")

    static func rowSummary(format: String, width: String, height: String) -> LocalizedStringResource {
        LocalizedStringResource("\(format) · \(width) × \(height) mm", table: "History",
            comment: "Second line of a history list row. %1$@ is the package format (for example 'KiCad'), %2$@ and %3$@ are the board's width and height as formatted numbers; 'mm' is millimeters. Keep the multiplication sign; the middle dot is a separator.")
    }

    static func modified(_ relativeAge: String) -> LocalizedStringResource {
        LocalizedStringResource("Modified \(relativeAge)", table: "History",
            comment: "Third line of a history list row. %@ is a relative time such as '2 days ago'.")
    }

    static func openedTimes(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("×\(count)", table: "History",
            comment: "Small badge at the right of a history list row showing how many times the package was opened. %lld is the count; the multiplication sign means 'times'.")
    }

    // MARK: Detail panel

    static let openPackage = LocalizedStringResource("Open Package", table: "History",
        comment: "Large button in the history detail panel that opens the selected package.")

    static let packageSection = LocalizedStringResource("Package", table: "History",
        comment: "Heading of the detail panel section describing the package; displayed in capital letters.")

    static let format = LocalizedStringResource("Format", table: "History",
        comment: "Detail row label: the package format, for example 'KiCad'.")

    static let source = LocalizedStringResource("Source", table: "History",
        comment: "Detail row label: what kind of source the package was opened from (ZIP, folder, or single layer).")

    static let board = LocalizedStringResource("Board", table: "History",
        comment: "Detail row label: the board's width and height.")

    static let layers = LocalizedStringResource("Layers", table: "History",
        comment: "Detail row label: the number of Gerber layer files.")

    static let drills = LocalizedStringResource("Drills", table: "History",
        comment: "Detail row label: the number of drilled holes and slots.")

    static let objects = LocalizedStringResource("Objects", table: "History",
        comment: "Detail row label: the number of drawn shapes across all layers.")

    static let colorSilkscreen = LocalizedStringResource("Color silkscreen", table: "History",
        comment: "Detail row label: how many board faces carry full-color silkscreen artwork.")

    static func sideCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) sides", table: "History",
            comment: "Detail row value for color silkscreen. %lld is the number of board faces (1 or 2) that carry it (plural forms are provided).")
    }

    static let reviewSet = LocalizedStringResource("Review set", table: "History",
        comment: "Detail row label shown for JLCPCB reviewed packages.")

    static let jlcpcbEngineerOutput = LocalizedStringResource("JLCPCB engineer output (OK)", table: "History",
        comment: "Detail row value: the package is production data reviewed by JLCPCB's engineers, taken from their folder named 'ok'. Keep 'JLCPCB' and 'OK' as written.")

    static let container = LocalizedStringResource("Container", table: "History",
        comment: "Detail row label shown when the board was found inside a nested archive.")

    static let nestedZip = LocalizedStringResource("Nested ZIP", table: "History",
        comment: "Detail row value: the board was found inside a ZIP archive that was itself inside the opened package.")

    static let originalUploads = LocalizedStringResource("Original uploads", table: "History",
        comment: "Detail row label for JLCPCB reviewed packages: the designer's original ZIP files enclosed with the review.")

    static let enclosedArchives = LocalizedStringResource("Enclosed archives", table: "History",
        comment: "Detail row label: ZIP archives found inside the opened package.")

    static func enclosedCount(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource("\(count) enclosed", table: "History",
            comment: "Detail row value: how many archives are enclosed in the package. %lld is the count.")
    }

    static let packageSize = LocalizedStringResource("Package size", table: "History",
        comment: "Detail row label: the size of the package file on disk.")

    static let reviewWarnings = LocalizedStringResource("Review warnings", table: "History",
        comment: "Detail row label: how many warnings the import produced.")

    static let ageAndActivity = LocalizedStringResource("Age & activity", table: "History",
        comment: "Heading of the detail panel section with dates; displayed in capital letters.")

    static let sourceAge = LocalizedStringResource("Source age", table: "History",
        comment: "Detail row label: how long ago the package files were last changed, as a relative time.")

    static let modifiedLabel = LocalizedStringResource("Modified", table: "History",
        comment: "Detail row label: the date the package files were last changed.")

    static let created = LocalizedStringResource("Created", table: "History",
        comment: "Detail row label: the date the package file was created.")

    static let firstInspected = LocalizedStringResource("First inspected", table: "History",
        comment: "Detail row label: the date the package was first opened in this app.")

    static let lastInspected = LocalizedStringResource("Last inspected", table: "History",
        comment: "Detail row label: the date the package was most recently opened in this app.")

    static let timesOpened = LocalizedStringResource("Times opened", table: "History",
        comment: "Detail row label: how many times the package has been opened in this app.")

    static let generator = LocalizedStringResource("Generator", table: "History",
        comment: "Heading of the detail panel section showing the name of the program that wrote the Gerber files; displayed in capital letters.")

    static let location = LocalizedStringResource("Location", table: "History",
        comment: "Heading of the detail panel section showing the package's path on disk; displayed in capital letters.")
}
