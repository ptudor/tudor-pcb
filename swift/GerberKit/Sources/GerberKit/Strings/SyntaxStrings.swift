import Foundation

/// English source text for syntax problems found inside Gerber (RS-274X) board
/// layer files and Excellon drill files. Each is shown after the file name and
/// the offending command, for example
/// `board.gtl: %ADD10C,-1*%: Circle requires a nonnegative diameter…`.
///
/// Every key lives in `Resources/Syntax.xcstrings` together with the comment
/// written here, which the translation pipeline shows to translators. Keys are
/// inserted into the catalog by hand; Xcode's extraction build stays off (see
/// the Localization section of README.md).
///
/// Vocabulary for translators: an *aperture* is a drawing tool shape (the pen
/// a Gerber file draws with); a *macro* is a user-defined aperture built from
/// smaller shapes; a *D-code* selects an aperture; *flash* stamps an aperture
/// at one point; a *region* is a filled area; *step-and-repeat* copies a block
/// in a grid; a *tool* in a drill file is one drill bit size.
enum SyntaxStrings {
    // MARK: Aperture macros

    static var invalidMacroInteger: String {
        String(localized: "Invalid macro integer/count.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro parameter that must be a whole number (such as a vertex count) is not one, or is out of range.")
    }

    static var invalidMacroDimension: String {
        String(localized: "Invalid macro dimension.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro size (diameter, width, or height) is negative, not a number, or too large.")
    }

    static var invalidMacroVariable: String {
        String(localized: "Invalid or redefined macro variable.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro assigns a variable that is malformed or has already been given a value.")
    }

    static var malformedMacroPrimitive: String {
        String(localized: "Malformed macro primitive.", table: "Syntax", bundle: Bundle.module,
               comment: "A line inside an aperture macro does not start with a valid shape code number.")
    }

    static var circleMacroFields: String {
        String(localized: "Circle macro requires exposure, diameter, center and optional rotation.", table: "Syntax", bundle: Bundle.module,
               comment: "A circle inside an aperture macro has the wrong number of parameters. The listed words name the expected parameters in order.")
    }

    static var incompleteOutlineMacro: String {
        String(localized: "Incomplete outline macro.", table: "Syntax", bundle: Bundle.module,
               comment: "An outline (polygon drawn point by point) inside an aperture macro is missing its parameters.")
    }

    static var incompleteOutlineCoordinates: String {
        String(localized: "Incomplete outline coordinates/rotation.", table: "Syntax", bundle: Bundle.module,
               comment: "An outline inside an aperture macro declares more points than it lists, or is missing its rotation.")
    }

    static var macroOutlineNotClosed: String {
        String(localized: "Macro outline is not closed.", table: "Syntax", bundle: Bundle.module,
               comment: "An outline inside an aperture macro must end at the point where it started, and does not.")
    }

    static var incompletePolygonMacro: String {
        String(localized: "Incomplete polygon macro.", table: "Syntax", bundle: Bundle.module,
               comment: "A regular polygon inside an aperture macro has the wrong number of parameters.")
    }

    static var incompleteVectorLineMacro: String {
        String(localized: "Incomplete vector-line macro.", table: "Syntax", bundle: Bundle.module,
               comment: "A vector line (a straight line with width, drawn between two points) inside an aperture macro has the wrong number of parameters.")
    }

    static var invalidVectorLineEndpoints: String {
        String(localized: "Invalid vector-line endpoints.", table: "Syntax", bundle: Bundle.module,
               comment: "The two end points of a vector line inside an aperture macro are not valid numbers.")
    }

    static var incompleteRectangleMacro: String {
        String(localized: "Incomplete rectangle macro.", table: "Syntax", bundle: Bundle.module,
               comment: "A rectangle inside an aperture macro has the wrong number of parameters.")
    }

    static var invalidThermalDimensions: String {
        String(localized: "Invalid thermal dimensions/gap.", table: "Syntax", bundle: Bundle.module,
               comment: "A thermal relief (a ring with gaps, used around pads connected to large copper areas) inside an aperture macro has an impossible size or gap.")
    }

    static func unsupportedMacroPrimitive(_ code: Int) -> String {
        String(localized: "Unsupported macro primitive \(code); layer rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro uses a shape code the app does not implement, so the whole layer is skipped. %lld is the numeric shape code from the file.")
    }

    static var macroWithoutGeometry: String {
        String(localized: "Macro contains no geometry.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro defines no shapes at all.")
    }

    static var invalidMacroExpression: String {
        String(localized: "Invalid, nonfinite, or division-by-zero macro expression.", table: "Syntax", bundle: Bundle.module,
               comment: "An arithmetic expression inside an aperture macro could not be evaluated: it is malformed, produces an infinite or undefined number, or divides by zero.")
    }

    // MARK: Excellon coordinate format

    static var unsupportedCoordinatePrecision: String {
        String(localized: "Unsupported coordinate precision.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file declares more integer or decimal digits per coordinate than the app supports.")
    }

    static var conflictingFormatDeclarations: String {
        String(localized: "Conflicting coordinate format declarations.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file declares its coordinate digit format twice with different values.")
    }

    static var malformedFileFormat: String {
        String(localized: "Malformed FILE_FORMAT declaration.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's FILE_FORMAT comment (which states digits before and after the decimal point) is not in the expected form. Keep 'FILE_FORMAT' as written.")
    }

    static var malformedFormatComment: String {
        String(localized: "Malformed FORMAT comment.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's FORMAT comment (which states precision, units, and zero handling) is not in the expected form. Keep 'FORMAT' as written.")
    }

    static var malformedFormatPrecision: String {
        String(localized: "Malformed FORMAT precision.", table: "Syntax", bundle: Bundle.module,
               comment: "The digit-count part of a drill file's FORMAT comment is not two numbers separated by a colon. Keep 'FORMAT' as written.")
    }

    static var unsupportedFormatModeUnits: String {
        String(localized: "Unsupported FORMAT mode/units.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's FORMAT comment names a coordinate mode or unit the app does not recognize (expected absolute or incremental, and metric or inch). Keep 'FORMAT' as written.")
    }

    static var unsupportedFormatZeroConvention: String {
        String(localized: "Unsupported FORMAT zero convention.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's FORMAT comment names a way of omitting zeros from numbers that the app does not recognize. Keep 'FORMAT' as written.")
    }

    static var conflictingZeroConventions: String {
        String(localized: "Conflicting zero conventions.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file says both that leading zeros and that trailing zeros are omitted from numbers.")
    }

    static var unsupportedUnitsFormat: String {
        String(localized: "Unsupported units/format declaration.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's units line (METRIC or INCH) carries a digit-format field the app cannot read.")
    }

    static var malformedIncrementalMode: String {
        String(localized: "Malformed incremental mode declaration.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's ICI command (which switches between absolute and incremental coordinates) is not in the expected form.")
    }

    static var unitsBeforeCoordinates: String {
        String(localized: "Declare drill units before coordinates/tools.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file uses coordinates or defines tools before saying whether its numbers are metric or inch.")
    }

    static var malformedCoordinate: String {
        String(localized: "Malformed coordinate.", table: "Syntax", bundle: Bundle.module,
               comment: "A coordinate value is not a valid number. Used for both Gerber and drill files.")
    }

    static var ambiguousIntegerCoordinates: String {
        String(localized: "Ambiguous integer coordinates: declare precision using FILE_FORMAT or a units format, or export explicit decimals.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file writes coordinates without decimal points and never says how many decimal digits they have, so they cannot be read. Keep 'FILE_FORMAT' as written; it is a comment keyword in the file.")
    }

    static var coordinateExceedsPrecision: String {
        String(localized: "Coordinate exceeds declared precision.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file coordinate has more digits than the file's declared digit format allows.")
    }

    static var ambiguousZeroConvention: String {
        String(localized: "Ambiguous zero convention: declare retained LZ/TZ or export explicit decimals.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file writes shortened coordinates without saying whether leading or trailing zeros were dropped. 'LZ' and 'TZ' are the file keywords for leading zeros and trailing zeros; keep them as written.")
    }

    static var coordinateOutOfRange: String {
        String(localized: "Nonfinite or out-of-range coordinate.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file coordinate is infinite, not a number, or beyond the supported range.")
    }

    // MARK: Excellon drill commands

    static var missingEndOfProgram: String {
        String(localized: "Missing drill end-of-program command.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file ends without the M30 command that marks the end of the program, so it may be truncated.")
    }

    static var dataAfterEndOfProgram: String {
        String(localized: "Data after drill end-of-program.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file contains commands after the end-of-program command.")
    }

    static var unterminatedToolDownRoute: String {
        String(localized: "Unterminated tool-down route.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file ends while the drill bit is still lowered in the middle of cutting a slot.")
    }

    static var invalidRouteToolDownState: String {
        String(localized: "Invalid route tool-down state.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file lowers the drill bit to cut a slot while it is in drilling mode or already lowered.")
    }

    static var toolChangeWhileRouting: String {
        String(localized: "Tool change while routing.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file switches to another drill bit while the current bit is lowered and cutting.")
    }

    static var invalidToolNumber: String {
        String(localized: "Invalid tool number.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's tool command (T followed by a number) has a number that cannot be read.")
    }

    static func undefinedTool(_ tool: Int) -> String {
        String(localized: "Undefined tool T\(tool).", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file selects a drill bit that was never defined. %lld is the tool number; keep the letter T before it as written.")
    }

    static var invalidToolDefinition: String {
        String(localized: "Invalid tool definition or undeclared units.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file defines a drill bit without a valid positive diameter, or before saying whether its numbers are metric or inch.")
    }

    static func redefinedTool(_ tool: Int) -> String {
        String(localized: "Redefined tool T\(tool).", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file defines the same drill bit twice. %lld is the tool number; keep the letter T before it as written.")
    }

    static var malformedGCommand: String {
        String(localized: "Malformed G command.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's G command (a machine mode command, written as G followed by a number) has no readable number. Keep 'G' as written.")
    }

    static var rapidWithToolDown: String {
        String(localized: "Rapid positioning with tool down is unsupported.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file asks the machine to move quickly to a new position while the drill bit is still lowered.")
    }

    static var drillModeWhileRouting: String {
        String(localized: "Drill mode while routing.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file switches back to drilling mode while the drill bit is still lowered and cutting a slot.")
    }

    static var unsupportedArcRoute: String {
        String(localized: "Unsupported arc route; drill layer rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file cuts a curved slot, which the app does not implement, so the whole drill layer is skipped.")
    }

    static var unsupportedExcellonGCommand: String {
        String(localized: "Unsupported Excellon G command.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file uses a G command (a machine mode command) the app does not implement. 'Excellon' is the drill file format; keep it and 'G' as written.")
    }

    static var g85DuringToolDown: String {
        String(localized: "G85 during a tool-down route.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file starts a G85 slot (a straight slot given by its two ends) while the drill bit is already lowered. Keep 'G85' as written.")
    }

    static var malformedG85Slot: String {
        String(localized: "Malformed G85 slot.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's G85 slot command does not give a valid end point. Keep 'G85' as written.")
    }

    static var invalidDrillRepeat: String {
        String(localized: "Invalid or unsupported drill repeat.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file's repeat command (R followed by a count, which drills a row of holes) has an unusable count or appears where it is not allowed.")
    }

    static var machiningRequiresTool: String {
        String(localized: "Machining requires a defined selected tool.", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file drills or cuts before any drill bit has been selected.")
    }

    static var malformedExcellonCommand: String {
        String(localized: "Malformed coordinates or unsupported Excellon command.", table: "Syntax", bundle: Bundle.module,
               comment: "A line in a drill file is neither readable coordinates nor a command the app knows. 'Excellon' is the drill file format; keep it as written.")
    }

    static func repeatedModifier(_ key: String) -> String {
        String(localized: "Repeated coordinate/modifier \(key).", table: "Syntax", bundle: Bundle.module,
               comment: "A drill file line gives the same coordinate letter twice, for example two X values. %@ is the repeated letter.")
    }

    // MARK: Gerber files used as drill layers

    static var invalidDrillLayerSpan: String {
        String(localized: "Invalid or conflicting drill layer span.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file's FileFunction attribute names the copper layers a hole passes through, and the numbers are missing, out of range, equal, or declared twice.")
    }

    static var blindBuriedSpanUnsupported: String {
        String(localized: "Blind/buried or unknown drill spans cannot be rendered as through holes.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file describes holes that do not go all the way through the board (blind or buried holes), which the app cannot show.")
    }

    static var unsupportedMachiningLabel: String {
        String(localized: "Unsupported machining label.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file's FileFunction attribute ends with a label the app does not recognize (expected drill, rout, or mixed).")
    }

    static var clearMachiningUnsupported: String {
        String(localized: "Clear machining operations are unsupported; the entire drill layer was rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file uses 'clear' polarity (erasing) for a hole, which has no meaning for drilling, so the whole layer is skipped.")
    }

    static var unsupportedMachiningShape: String {
        String(localized: "Unsupported machining shape or curved route; the entire drill layer was rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file draws a hole or slot with a shape the app cannot turn into a drill operation (only round holes and straight slots are supported), so the whole layer is skipped.")
    }

    static var machiningDiameterNotPositive: String {
        String(localized: "Machining diameter must be positive.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber drill file gives a hole or slot a zero or negative diameter.")
    }

    static var unrecognizedDrillSyntax: String {
        String(localized: "Unrecognized drill syntax.", table: "Syntax", bundle: Bundle.module,
               comment: "A file named like a drill file is neither Gerber nor Excellon drill data.")
    }

    // MARK: Gerber structure

    static var missingDelimiterBeforeExtended: String {
        String(localized: "Missing command delimiter before extended block.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file starts an extended command (one enclosed in percent signs) without finishing the previous command with an asterisk.")
    }

    static var unterminatedCommand: String {
        String(localized: "Unterminated command or extended block.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file ends in the middle of a command or of an extended command block (one enclosed in percent signs).")
    }

    static var unterminatedRegionOrRepeat: String {
        String(localized: "Unterminated region or repeat block.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file ends, or starts an extended command, while a filled region or a step-and-repeat block is still open.")
    }

    static var missingM02: String {
        String(localized: "Missing M02 end-of-file command.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file ends without the M02 command that marks the end of the file, so it may be truncated. Keep 'M02' as written.")
    }

    static var dataAfterEndOfFile: String {
        String(localized: "Data after end-of-file.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file contains commands after the end-of-file command.")
    }

    static var missingExtendedDelimiter: String {
        String(localized: "Missing extended-command delimiter.", table: "Syntax", bundle: Bundle.module,
               comment: "An extended command block in a Gerber file (one enclosed in percent signs) does not end with an asterisk.")
    }

    static var emptyExtendedBlock: String {
        String(localized: "Empty extended block.", table: "Syntax", bundle: Bundle.module,
               comment: "An extended command block in a Gerber file (one enclosed in percent signs) contains nothing.")
    }

    static var unsupportedGeometryCommand: String {
        String(localized: "Unsupported or malformed geometry command; layer rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file uses a drawing command the app does not implement or cannot read (for example a deprecated command), so the whole layer is skipped.")
    }

    static var unsupportedCoordinateFormat: String {
        String(localized: "Unsupported or malformed coordinate format.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file's FS command (which declares how coordinates are written) cannot be read or asks for an unsupported form.")
    }

    static var precisionMismatch: String {
        String(localized: "X/Y precision must match and contain digits.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file's FS command declares different digit counts for X and Y coordinates, or none at all.")
    }

    static var emptyOrOversizedMacro: String {
        String(localized: "Empty or oversized macro definition.", table: "Syntax", bundle: Bundle.module,
               comment: "An aperture macro definition in a Gerber file has no name, no body, redefines an existing name, or is far too long.")
    }

    static var invalidMacroVertexCount: String {
        String(localized: "Invalid literal macro vertex count.", table: "Syntax", bundle: Bundle.module,
               comment: "An outline inside an aperture macro states a number of points that is not a whole number or is out of range.")
    }

    static var invalidApertureNumber: String {
        String(localized: "Invalid aperture number.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file defines an aperture with a D-code number that is out of range (D-codes 10 and above are allowed).")
    }

    static var missingApertureTemplate: String {
        String(localized: "Missing aperture template.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file defines an aperture without naming its shape (circle, rectangle, obround, polygon, or a macro).")
    }

    static var malformedModifier: String {
        String(localized: "Malformed, nonfinite, or out-of-range modifier.", table: "Syntax", bundle: Bundle.module,
               comment: "A size parameter in a Gerber aperture definition is not a valid number or is too large.")
    }

    static var circleTemplateInvalid: String {
        String(localized: "Circle requires a nonnegative diameter and optional round hole; legacy rectangular holes are unsupported.", table: "Syntax", bundle: Bundle.module,
               comment: "A circle aperture in a Gerber file has a negative diameter, or uses the old-style rectangular center hole the app does not implement.")
    }

    static var rectangleTemplateInvalid: String {
        String(localized: "Rectangle/obround requires positive width and height and optional round hole; legacy rectangular holes are unsupported.", table: "Syntax", bundle: Bundle.module,
               comment: "A rectangle or obround (rounded-end rectangle) aperture in a Gerber file has a zero or negative side, or uses the old-style rectangular center hole the app does not implement.")
    }

    static var polygonTemplateInvalid: String {
        String(localized: "Polygon requires a positive diameter, 3...12 integer vertices, finite rotation and optional round hole; legacy rectangular holes are unsupported.", table: "Syntax", bundle: Bundle.module,
               comment: "A regular polygon aperture in a Gerber file has an invalid diameter, a vertex count outside 3 to 12, a bad rotation, or uses the old-style rectangular center hole the app does not implement.")
    }

    static func undefinedApertureMacro(_ name: String) -> String {
        String(localized: "Undefined aperture macro \(name).", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file defines an aperture from a macro that was never defined. %@ is the macro name quoted from the file.")
    }

    static var repeatCloseWithoutOpen: String {
        String(localized: "Repeat close without an open block.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file ends a step-and-repeat block that was never started.")
    }

    static var nestedStepRepeat: String {
        String(localized: "Nested step-repeat is not supported; layer rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file starts a step-and-repeat block inside another one, which the app does not implement, so the whole layer is skipped.")
    }

    static var malformedStandardCommand: String {
        String(localized: "Malformed coordinate or unsupported standard command.", table: "Syntax", bundle: Bundle.module,
               comment: "A line in a Gerber file is neither readable coordinates nor a command the app knows.")
    }

    static func repeatedField(_ key: String) -> String {
        String(localized: "Repeated field \(key).", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber command gives the same letter field twice, for example two X coordinates. %@ is the repeated letter.")
    }

    static var outOfRangeCommandNumber: String {
        String(localized: "Out-of-range command number.", table: "Syntax", bundle: Bundle.module,
               comment: "A number after a command letter in a Gerber file is too large to read.")
    }

    static var nestedRegion: String {
        String(localized: "Nested region.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file starts a filled region while another region is still open.")
    }

    static var regionEndWithoutStart: String {
        String(localized: "Region end without start.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file ends a filled region that was never started.")
    }

    static var unsupportedGCommand: String {
        String(localized: "Unsupported G command.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file uses a G command (a drawing mode command, written as G followed by a number) the app does not implement. Keep 'G' as written.")
    }

    static var invalidDOperation: String {
        String(localized: "Invalid D operation.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file uses a D-code between 4 and 9, which the format does not define (1 to 3 are drawing operations, 10 and above select apertures). Keep 'D' as written.")
    }

    static func undefinedAperture(_ code: Int) -> String {
        String(localized: "Undefined aperture D\(code).", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file selects an aperture (drawing tool shape) that was never defined. %lld is the D-code number; keep the letter D before it as written.")
    }

    static var formatAndUnitsBeforeOperations: String {
        String(localized: "Declare coordinate format and units before operations.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file draws something before declaring how its coordinates are written and whether they are metric or inch.")
    }

    static var flashInsideRegion: String {
        String(localized: "Flash inside region.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file stamps an aperture (a flash) while a filled region is open, which the format does not allow.")
    }

    static var unsupportedG74Arc: String {
        String(localized: "Unsupported G74 arc; layer rejected.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file draws an arc in single-quadrant mode (the deprecated G74 command), which the app does not implement, so the whole layer is skipped. Keep 'G74' as written.")
    }

    static var drawWithoutAperture: String {
        String(localized: "Draw without a selected aperture.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file draws a line or arc before any aperture (drawing tool shape) has been selected.")
    }

    static var unsupportedDrawAperture: String {
        String(localized: "Unsupported draw aperture; only solid circles and linear legacy rectangle sweeps are supported.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file draws a line with an aperture (drawing tool shape) that cannot be used as a pen: only round pens, and rectangular pens on straight lines, are supported.")
    }

    static var regionContourIncomplete: String {
        String(localized: "Region has an empty or incomplete contour.", table: "Syntax", bundle: Bundle.module,
               comment: "A filled region in a Gerber file has an outline with too few points to enclose an area.")
    }

    static var flashWithoutAperture: String {
        String(localized: "Flash without a selected aperture.", table: "Syntax", bundle: Bundle.module,
               comment: "A Gerber file stamps an aperture (a flash) before any aperture has been selected.")
    }
}
