import XCTest

/// Guards the String Catalogs against the ways they drift from the code and
/// from the translation pipeline's rules, without an Xcode extraction build
/// (extraction is deliberately off; see README.md, "Localization").
///
/// - Every `table:` named in code has a committed catalog and vice versa.
/// - Every key in a catalog is written in code with that table, and every
///   key written in code is in its catalog. Interpolations are compared by
///   position only, so `\(count)` matches `%lld` and `\(name)` matches `%@`.
/// - Every key carries a translator comment.
/// - No catalog is named `Localizable`, which is where Xcode's extractor puts
///   a key whose table it cannot see.
/// - No catalog carries the app's name (`CFBundleDisplayName`/`CFBundleName`),
///   which ships from the build settings and is never translated.
/// - No table holds a `%@` twin of a `%lld` key, and no untranslated key
///   duplicates a key already translated in a sibling table.
final class LocalizationCatalogTests: XCTestCase {
    private struct CatalogSet {
        let name: String
        /// Directory holding the `.xcstrings` files.
        let catalogs: URL
        /// Root of the Swift sources that reference those tables.
        let sources: URL
        /// Tables that are localized from the Info.plist rather than code.
        let plistTables: Set<String>
    }

    private struct Catalog {
        let table: String
        let url: URL
        let strings: [String: [String: Any]]
    }

    private static let swiftRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TudorPCBTests
        .deletingLastPathComponent()  // swift

    private static let sets = [
        CatalogSet(name: "TudorPCB",
                   catalogs: swiftRoot.appending(path: "TudorPCB/Localization"),
                   sources: swiftRoot.appending(path: "TudorPCB"),
                   plistTables: ["InfoPlist"]),
        CatalogSet(name: "GerberKit",
                   catalogs: swiftRoot.appending(path: "GerberKit/Sources/GerberKit/Resources"),
                   sources: swiftRoot.appending(path: "GerberKit/Sources/GerberKit"),
                   plistTables: []),
    ]

    private static let skippedDirectories: Set<String> = ["build", ".build", "DerivedData", "xcuserdata"]

    func testNoCatalogIsNamedLocalizable() throws {
        let stray = try Self.files(under: Self.swiftRoot, suffix: ".xcstrings")
            .filter { $0.lastPathComponent == "Localizable.xcstrings" }
        XCTAssertTrue(stray.isEmpty, "Xcode's extractor created a default-table catalog; give the key a table instead: \(stray.map(\.path))")
    }

    func testEveryTableIsDeclaredOnBothSides() throws {
        for set in Self.sets {
            let catalogs = try Self.catalogs(in: set)
            let onDisk = Set(catalogs.map(\.table))
            let referenced = try Self.referencedTables(in: set.sources)
            XCTAssertEqual(referenced.subtracting(onDisk), [], "\(set.name): tables named in code without a catalog")
            XCTAssertEqual(onDisk.subtracting(referenced).subtracting(set.plistTables), [], "\(set.name): catalogs no code refers to")
        }
    }

    func testCatalogKeysMatchTheKeysWrittenInCode() throws {
        for set in Self.sets {
            let inCode = try Self.keysInCode(under: set.sources)
            for catalog in try Self.catalogs(in: set) where !set.plistTables.contains(catalog.table) {
                let expected = Set((inCode[catalog.table] ?? []).map(Self.normalized))
                let actual = Set(catalog.strings.keys.map(Self.normalized))
                XCTAssertEqual(actual.subtracting(expected), [], "\(set.name)/\(catalog.table): catalog keys no code writes (remove them, or mark them stale for the pipeline)")
                XCTAssertEqual(expected.subtracting(actual), [], "\(set.name)/\(catalog.table): keys written in code that the catalog lacks (insert them by hand)")
            }
        }
    }

    func testEveryKeyHasATranslatorComment() throws {
        for set in Self.sets {
            for catalog in try Self.catalogs(in: set) {
                XCTAssertFalse(catalog.strings.isEmpty, "\(set.name)/\(catalog.table) is empty")
                for (key, entry) in catalog.strings {
                    let comment = entry["comment"] as? String ?? ""
                    XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(set.name)/\(catalog.table): \(key.debugDescription) has no translator comment")
                }
            }
        }
    }

    func testCatalogsFollowThePipelineRules() throws {
        for set in Self.sets {
            let catalogs = try Self.catalogs(in: set)
            for catalog in catalogs {
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.url)) as? [String: Any]
                XCTAssertEqual(json?["sourceLanguage"] as? String, "en", "\(set.name)/\(catalog.table): source language")
                XCTAssertEqual(json?["version"] as? String, "1.0", "\(set.name)/\(catalog.table): catalog version")
                for forbidden in ["CFBundleDisplayName", "CFBundleName"] {
                    XCTAssertNil(catalog.strings[forbidden], "\(set.name)/\(catalog.table): the app name ships from INFOPLIST_KEY_CFBundleDisplayName, never a catalog")
                }
                let typed = catalog.strings.keys.filter { $0.contains("%lld") }
                for key in typed {
                    let twin = key.replacingOccurrences(of: "%lld", with: "%@")
                    XCTAssertNil(catalog.strings[twin], "\(set.name)/\(catalog.table): \(twin.debugDescription) is a type-erased twin of \(key.debugDescription)")
                }
                for (key, entry) in catalog.strings {
                    let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
                    if let variations = english?["variations"] as? [String: Any], variations["plural"] != nil {
                        XCTAssertTrue(key.contains("%lld"), "\(set.name)/\(catalog.table): \(key.debugDescription) has plural forms but no integer argument")
                    }
                }
            }
            // A shadow key: untranslated in one table, already translated in another.
            for catalog in catalogs {
                for (key, entry) in catalog.strings where Self.localeCount(entry) == 0 {
                    for other in catalogs where other.table != catalog.table {
                        if let elsewhere = other.strings[key], Self.localeCount(elsewhere) > 0 {
                            XCTFail("\(set.name)/\(catalog.table): \(key.debugDescription) is untranslated here but translated in \(other.table)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func catalogs(in set: CatalogSet) throws -> [Catalog] {
        try files(under: set.catalogs, suffix: ".xcstrings").map { url in
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = try XCTUnwrap(json?["strings"] as? [String: [String: Any]], "\(url.lastPathComponent) has no strings object")
            return Catalog(table: url.deletingPathExtension().lastPathComponent, url: url, strings: strings)
        }
    }

    private static func localeCount(_ entry: [String: Any]) -> Int {
        ((entry["localizations"] as? [String: Any]) ?? [:]).count
    }

    private static func files(under root: URL, suffix: String) throws -> [URL] {
        var result: [URL] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj" { enumerator.skipDescendants() }
                continue
            }
            if url.lastPathComponent.hasSuffix(suffix) { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    private static let tableReference = try! NSRegularExpression(pattern: #"\btable(?:Name)?:\s*"([A-Za-z0-9_]+)""#)

    private static func referencedTables(in root: URL) throws -> Set<String> {
        var tables = Set<String>()
        for file in try files(under: root, suffix: ".swift") {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in tableReference.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                tables.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        return tables
    }

    /// Every `LocalizedStringResource("…", table: "T"` and
    /// `String(localized: "…", table: "T"` literal, keyed by table, with the
    /// literal text exactly as written (interpolations included).
    private static func keysInCode(under root: URL) throws -> [String: [String]] {
        var keys: [String: [String]] = [:]
        for file in try files(under: root, suffix: ".swift") {
            let text = try String(contentsOf: file, encoding: .utf8)
            var scanner = text[...]
            while true {
                let candidates = ["LocalizedStringResource(\"", "String(localized: \""].compactMap { scanner.range(of: $0) }
                guard let earliest = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else { break }
                scanner = scanner[earliest.upperBound...]
                let (literal, rest) = try XCTUnwrap(stringLiteral(startingAt: scanner), "unterminated literal in \(file.lastPathComponent)")
                scanner = rest
                let tail = scanner.prefix(80)
                guard let table = tableReference.firstMatch(in: String(tail), range: NSRange(tail.startIndex..., in: tail)),
                      table.range.location < 40 else {
                    XCTFail("\(file.lastPathComponent): localized literal without a table: \(literal.prefix(60).debugDescription)")
                    continue
                }
                let name = String(String(tail)[Range(table.range(at: 1), in: String(tail))!])
                keys[name, default: []].append(literal)
            }
        }
        return keys
    }

    /// Reads a Swift string literal body, honoring escapes and balanced
    /// parentheses inside `\(…)` interpolations, and returns it with the
    /// remainder after the closing quote.
    private static func stringLiteral(startingAt input: Substring) -> (String, Substring)? {
        var body = ""
        var index = input.startIndex
        var depth = 0
        while index < input.endIndex {
            let character = input[index]
            if depth == 0 {
                if character == "\"" { return (body, input[input.index(after: index)...]) }
                if character == "\\" {
                    let next = input.index(after: index)
                    guard next < input.endIndex else { return nil }
                    if input[next] == "(" { depth = 1; body += "\\("; index = input.index(after: next); continue }
                    body.append(character); body.append(input[next]); index = input.index(after: next); continue
                }
            } else {
                if character == "(" { depth += 1 } else if character == ")" { depth -= 1 }
            }
            body.append(character)
            index = input.index(after: index)
        }
        return nil
    }

    /// Replaces every interpolation or format specifier with a bare `%` so a
    /// key written in code compares equal to the key Xcode's extractor would
    /// emit for it, whatever the argument's type.
    private static func normalized(_ key: String) -> String {
        var result = ""
        var scanner = key[...]
        while !scanner.isEmpty {
            if scanner.hasPrefix("\\(") {
                var depth = 0
                var index = scanner.index(scanner.startIndex, offsetBy: 1)
                repeat {
                    if scanner[index] == "(" { depth += 1 } else if scanner[index] == ")" { depth -= 1 }
                    index = scanner.index(after: index)
                } while depth > 0 && index < scanner.endIndex
                result += "%"
                scanner = scanner[index...]
            } else if scanner.hasPrefix("%") {
                var index = scanner.index(after: scanner.startIndex)
                while index < scanner.endIndex, "0123456789$".contains(scanner[index]) { index = scanner.index(after: index) }
                while index < scanner.endIndex, "@dilfsux".contains(scanner[index]) { index = scanner.index(after: index) }
                result += "%"
                scanner = scanner[index...]
            } else {
                result.append(scanner.removeFirst())
            }
        }
        return result.replacingOccurrences(of: "\\\"", with: "\"")
    }
}
