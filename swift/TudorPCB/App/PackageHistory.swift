import Foundation
import GerberKit

nonisolated enum FabricationSourceKind: String, Codable, Sendable {
    case archive
    case folder
    case layer

    var displayName: String {
        switch self {
        case .archive: "Gerber ZIP"
        case .folder: "Fabrication folder"
        case .layer: "Gerber layer"
        }
    }

    var systemImage: String {
        switch self {
        case .archive: "shippingbox.fill"
        case .folder: "folder.fill"
        case .layer: "doc.text.fill"
        }
    }
}

nonisolated struct PackageHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sourcePath: String
    var sourceKind: FabricationSourceKind
    var name: String
    var firstOpenedAt: Date
    var lastOpenedAt: Date
    var openedCount: Int
    var createdAt: Date?
    var modifiedAt: Date?
    var byteCount: Int64?
    var boardWidth: Double
    var boardHeight: Double
    var layerCount: Int
    var drillCount: Int
    var primitiveCount: Int
    var warningCount: Int
    var formatName: String
    var generator: String?
    var colorSilkscreenSides: Int
    var packageRole: FabricationPackageRole?
    var enclosedSourceCount: Int?
    var bookmarkData: Data?
    var sourceSelection: FabricationSelection? = nil

    var ageDate: Date { modifiedAt ?? createdAt ?? firstOpenedAt }
    var isAvailable: Bool { FileManager.default.fileExists(atPath: sourcePath) }
    var ageDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: ageDate, relativeTo: .now)
    }

    static func capture(url: URL, document: BoardDocument, now: Date = .now) -> Self {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .creationDateKey, .contentModificationDateKey,
            .fileSizeKey, .totalFileAllocatedSizeKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory == true
        let sourceKind: FabricationSourceKind = isDirectory
            ? .folder
            : (url.pathExtension.lowercased() == "zip" ? .archive : .layer)
        let generator = document.layers.compactMap(\.sourceGenerator).first
        let formatName: String
        if document.packageRole == .jlcpcbProduction {
            formatName = "JLCPCB production"
        } else if document.isEasyEDA {
            formatName = "EasyEDA Pro"
        } else if generator?.localizedCaseInsensitiveContains("EAGLE") == true {
            formatName = "Autodesk Eagle"
        } else if generator?.localizedCaseInsensitiveContains("KiCad") == true {
            formatName = "KiCad"
        } else if generator?.localizedCaseInsensitiveContains("Altium") == true {
            formatName = "Altium"
        } else {
            formatName = "RS-274X"
        }

        return PackageHistoryEntry(
            id: UUID(),
            sourcePath: url.standardizedFileURL.path,
            sourceKind: sourceKind,
            name: document.name,
            firstOpenedAt: now,
            lastOpenedAt: now,
            openedCount: 1,
            createdAt: values?.creationDate,
            modifiedAt: latestModificationDate(for: url, isDirectory: isDirectory)
                ?? values?.contentModificationDate,
            byteCount: values?.fileSize.map(Int64.init) ?? values?.totalFileAllocatedSize.map(Int64.init),
            boardWidth: document.bounds.width,
            boardHeight: document.bounds.height,
            layerCount: document.layers.count,
            drillCount: document.drills.count,
            primitiveCount: document.primitiveCount,
            warningCount: document.warnings.count,
            formatName: formatName,
            generator: generator,
            colorSilkscreenSides: Set(document.colorSilkscreens.map(\.side)).count,
            packageRole: document.packageRole,
            enclosedSourceCount: document.enclosedSourceArchives.count,
            bookmarkData: PackageHistoryStore.makeBookmark(for: url),
            sourceSelection: document.sourceSelection
        )
    }

    private static func latestModificationDate(for url: URL, isDirectory: Bool) -> Date? {
        guard isDirectory,
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return nil }
        var latest: Date?
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ), values.isRegularFile == true, let date = values.contentModificationDate else { continue }
            if latest == nil || date > latest! { latest = date }
        }
        return latest
    }
}

nonisolated enum PackageHistoryStore {
    private static let defaultsKey = "TudorPCB.packageHistory.v1"
    private static let maximumEntries = 100

    static func load() -> [PackageHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([PackageHistoryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    static func save(_ entries: [PackageHistoryEntry]) {
        let trimmed = Array(entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.prefix(maximumEntries))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func merging(_ entry: PackageHistoryEntry, into entries: [PackageHistoryEntry]) -> [PackageHistoryEntry] {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.sourcePath == entry.sourcePath && $0.sourceSelection == entry.sourceSelection }) {
            var replacement = entry
            replacement.id = updated[index].id
            replacement.firstOpenedAt = updated[index].firstOpenedAt
            replacement.openedCount = updated[index].openedCount + 1
            if replacement.bookmarkData == nil { replacement.bookmarkData = updated[index].bookmarkData }
            updated[index] = replacement
        } else {
            updated.append(entry)
        }
        return Array(updated.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.prefix(maximumEntries))
    }

    static func makeBookmark(for url: URL) -> Data? {
        #if os(macOS)
        return try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func resolve(_ entry: PackageHistoryEntry) throws -> URL {
        if let bookmarkData = entry.bookmarkData {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        }
        guard FileManager.default.fileExists(atPath: entry.sourcePath) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return URL(fileURLWithPath: entry.sourcePath)
    }
}
