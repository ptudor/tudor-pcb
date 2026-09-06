import Foundation
import GerberKit
import Observation

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
    var fileSystemIdentity: String? = nil

    var ageDate: Date { modifiedAt ?? createdAt ?? firstOpenedAt }
    var ageDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: ageDate, relativeTo: .now)
    }

    static func capture(url: URL, document: BoardDocument, now: Date = .now, bookmarkData: Data? = nil) -> Self {
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
            bookmarkData: bookmarkData,
            sourceSelection: document.sourceSelection,
            fileSystemIdentity: fileSystemIdentity(for: url)
        )
    }

    static func fileSystemIdentity(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return "\(device.stringValue):\(inode.stringValue)"
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
    static let defaultsKey = "TudorPCB.packageHistory.v1"
    private static let maximumEntries = 100

    static func load(defaults: UserDefaults = .standard) -> PackageHistoryLoad {
        guard let data = defaults.data(forKey: defaultsKey) else { return PackageHistoryLoad(entries: [], recovery: nil) }
        do {
            guard let records = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw HistoryStorageError.invalid("Unsupported history format/version.")
            }
            var entries: [PackageHistoryEntry] = [], invalid = 0
            var identities: Set<UUID> = []
            for record in records {
                do {
                    let bytes = try JSONSerialization.data(withJSONObject: record, options: .fragmentsAllowed)
                    let entry = try JSONDecoder().decode(PackageHistoryEntry.self, from: bytes)
                    try validate(entry)
                    guard identities.insert(entry.id).inserted else { throw HistoryStorageError.invalid("Duplicate history identity.") }
                    entries.append(entry)
                } catch { invalid += 1 }
            }
            entries = ordered(entries)
            return PackageHistoryLoad(entries: entries, recovery: invalid == 0 ? nil : HistoryRecovery(original: data,
                message: "\(invalid) history record(s) could not be read. \(entries.count) valid record(s) are recoverable. Original data is preserved; saving is paused until you choose recovery."))
        } catch {
            return PackageHistoryLoad(entries: [], recovery: HistoryRecovery(original: data,
                message: "History could not be read: \(error.localizedDescription) Original data is preserved; saving is paused until you choose recovery."))
        }
    }

    static func save(_ entries: [PackageHistoryEntry], defaults: UserDefaults = .standard) throws {
        if let recovery = load(defaults: defaults).recovery { throw HistoryStorageError.invalid(recovery.message) }
        let data = try encoded(entries)
        defaults.set(data, forKey: defaultsKey)
    }

    @discardableResult
    static func recover(_ entries: [PackageHistoryEntry], original: Data, defaults: UserDefaults = .standard) throws -> String {
        guard defaults.data(forKey: defaultsKey) == original else {
            throw HistoryStorageError.invalid("History changed during recovery. Reload it before choosing recovery again.")
        }
        let data = try encoded(entries)
        let backupKey = defaultsKey + ".recovery." + UUID().uuidString
        defaults.set(original, forKey: backupKey)
        defaults.set(data, forKey: defaultsKey)
        return backupKey
    }

    private static func ordered(_ entries: [PackageHistoryEntry]) -> [PackageHistoryEntry] {
        Array(entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.prefix(maximumEntries))
    }

    private static func encoded(_ entries: [PackageHistoryEntry]) throws -> Data {
        for entry in entries { try validate(entry) }
        return try JSONEncoder().encode(ordered(entries))
    }

    private static func validate(_ entry: PackageHistoryEntry) throws {
        guard entry.boardWidth.isFinite, entry.boardHeight.isFinite,
              entry.boardWidth >= 0, entry.boardHeight >= 0,
              entry.firstOpenedAt.timeIntervalSince1970.isFinite,
              entry.lastOpenedAt.timeIntervalSince1970.isFinite,
              entry.openedCount > 0, entry.layerCount >= 0, entry.drillCount >= 0,
              entry.primitiveCount >= 0, entry.warningCount >= 0 else {
            throw HistoryStorageError.invalid("History contains invalid activity or board statistics.")
        }
    }

    static func merging(_ entry: PackageHistoryEntry, into entries: [PackageHistoryEntry], reopening original: PackageHistoryEntry? = nil) -> [PackageHistoryEntry] {
        var updated = entries
        let index: Int?
        if let original { index = updated.firstIndex { $0.id == original.id } }
        else {
            index = updated.firstIndex {
                $0.sourcePath == entry.sourcePath && $0.sourceSelection == entry.sourceSelection &&
                $0.fileSystemIdentity == entry.fileSystemIdentity
            }
        }
        var replacement = entry
        if let previous = index.map({ updated[$0] }) ?? original {
            replacement.id = previous.id
            replacement.firstOpenedAt = previous.firstOpenedAt
            replacement.openedCount = previous.openedCount + 1
        }
        if let index { updated[index] = replacement }
        else { updated.append(replacement) }
        return ordered(updated)
    }

    static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func availability(_ entry: PackageHistoryEntry,
        resolver: @escaping @Sendable (PackageHistoryEntry) throws -> HistoryResolvedSource = { try resolved($0) },
        startAccess: @escaping @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) async -> HistorySourceAvailability {
        await Task.detached {
            do {
                let source = try resolver(entry)
                guard startAccess(source.url) else { return .inaccessible }
                defer { stopAccess(source.url) }
                guard try source.url.checkResourceIsReachable() else { return .missing }
                try validateResolvedIdentity(entry, at: source.url)
                return source.url.resolvingSymlinksInPath().path == URL(fileURLWithPath: entry.sourcePath).resolvingSymlinksInPath().path ? .available : .moved
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return .missing
            } catch { return .inaccessible }
        }.value
    }

    static func validateResolvedIdentity(_ entry: PackageHistoryEntry, at url: URL) throws {
        if let expected = entry.fileSystemIdentity,
           PackageHistoryEntry.fileSystemIdentity(for: url) != expected {
            throw HistoryAccessError.reselectRequired("\(url.path) (the file identity changed)")
        }
    }

    static func resolve(_ entry: PackageHistoryEntry) throws -> URL { try resolved(entry).url }

    static func resolved(_ entry: PackageHistoryEntry) throws -> HistoryResolvedSource {
        if let bookmarkData = entry.bookmarkData {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return HistoryResolvedSource(url: url, stale: stale)
        }
        throw HistoryAccessError.reselectRequired(entry.sourcePath)
    }
}

nonisolated enum HistoryAccessError: Error, LocalizedError {
    case reselectRequired(String)
    var errorDescription: String? {
        switch self { case let .reselectRequired(path): "Persistent access to \(path) is unavailable. Reselect the original file or folder to relink it." }
    }
}

nonisolated struct PackageHistoryLoad {
    var entries: [PackageHistoryEntry]
    var recovery: HistoryRecovery?
}
nonisolated struct HistoryRecovery {
    var original: Data
    var message: String
}
nonisolated enum HistoryStorageError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case let .invalid(message): message } }
}

/// One main-actor owner serializes mutations for every window in this process.
@MainActor
@Observable
final class PackageHistoryOwner {
    static let shared = PackageHistoryOwner()
    private(set) var entries: [PackageHistoryEntry]
    private(set) var recovery: HistoryRecovery?
    var error: String?
    private let defaults: UserDefaults
    private let writer: ([PackageHistoryEntry]) throws -> Void

    init(defaults: UserDefaults = .standard, writer: (([PackageHistoryEntry]) throws -> Void)? = nil) {
        self.defaults = defaults
        self.writer = writer ?? { try PackageHistoryStore.save($0, defaults: defaults) }
        let loaded = writer == nil ? PackageHistoryStore.load(defaults: defaults) : PackageHistoryLoad(entries: [], recovery: nil)
        entries = loaded.entries
        recovery = loaded.recovery
        error = loaded.recovery?.message
    }

    func record(_ entry: PackageHistoryEntry, reopening original: PackageHistoryEntry? = nil) {
        entries = PackageHistoryStore.merging(entry, into: entries, reopening: original)
        persist()
    }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; persist() }
    func clear() { entries.removeAll(); persist() }

    private func persist() {
        do {
            if let recovery { throw HistoryStorageError.invalid(recovery.message) }
            try writer(entries)
            error = nil
        } catch { self.error = "History was not saved: \(error.localizedDescription)" }
    }

    func recover() {
        guard let recovery else { return }
        do {
            try PackageHistoryStore.recover(entries, original: recovery.original, defaults: defaults)
            self.recovery = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

nonisolated struct HistoryResolvedSource: Sendable {
    var url: URL
    var stale: Bool
}
nonisolated enum HistorySourceAvailability: Sendable {
    case checking, available, moved, missing, inaccessible
    var accessible: Bool { self == .available || self == .moved }
    var label: String {
        switch self {
        case .checking: "Checking source access…"
        case .available: "Source available"
        case .moved: "Source moved · bookmark resolves"
        case .missing: "Source missing"
        case .inaccessible: "Source inaccessible · relink required"
        }
    }
}
