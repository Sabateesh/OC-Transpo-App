import Foundation

extension Notification.Name {
    static let transitTimetableChanged = Notification.Name("transitTimetableChanged")
}

struct TransitFeedSnapshot {
    let feed: PreparedTransitFeed
    let version: String
    let checkedAt: Date
    let bundled: Bool
}

actor TransitFeedStore {
    struct Download {
        let feed: PreparedTransitFeed?
        let version: String
    }
    private struct Disk: Codable {
        let version: String
        let checkedAt: Date
        let payload: Data
    }
    static let shared = TransitFeedStore()
    static let folder = AppGroup.folder.appending(path: "timetable-v3", directoryHint: .isDirectory)
    private let folder: URL
    private let bundleURL: URL?
    private let legacyFolders: [URL]
    private let downloader: @Sendable (String?) async throws -> Download
    private var snapshot: TransitFeedSnapshot?
    private var local: Task<TransitFeedSnapshot?, Never>?
    private var loadedLocal = false
    private var triedBundleDates: Set<String> = []
    private var refreshTask: Task<TransitFeedSnapshot, Error>?
    private var lastAttempt = Date.distantPast
    private var writing: Task<Void, Never>?

    init(folder: URL? = nil, bundleURL: URL? = Bundle.main.url(forResource: "BundledTimetable", withExtension: "transit"), downloader: (@Sendable (String?) async throws -> Download)? = nil) {
        self.folder = folder ?? Self.folder; self.bundleURL = bundleURL
        legacyFolders = folder.map { [$0] } ?? [AppGroup.folder.appending(path: "routing-v2")]
        self.downloader = downloader ?? { version in try await Self.download(version) }
    }
    func load(for date: Date? = nil, refresh: Bool = false) async throws -> TransitFeedSnapshot {
        if !loadedLocal {
            if local == nil {
                let folder = folder, legacy = legacyFolders, bundle = bundleURL
                local = Task.detached(priority: .userInitiated) { Self.readLocal(folder: folder, legacy: legacy, bundle: bundle) }
            }
            let value = await local!.value
            if !loadedLocal {
                snapshot = value; loadedLocal = true; local = nil
                if let value, !FileManager.default.fileExists(atPath: folder.appending(path: "prepared.plist").path) { persist(value) }
            }
        }
        if !refresh, let date, snapshot?.feed.covers(date) != true, let bundleURL,
           triedBundleDates.insert(PreparedTransitFeed.dayKey(date)).inserted {
            let bundled = await Task.detached(priority: .userInitiated) { Self.readLocal(folder: self.folder.appending(path: "unused"), legacy: [], bundle: bundleURL) }.value
            if let bundled, bundled.feed.covers(date), bundled.feed.validThrough > (snapshot?.feed.validThrough ?? "") {
                snapshot = bundled; persist(bundled)
            }
        }
        if !refresh, let snapshot, date.map(snapshot.feed.covers) ?? true {
            if Date.now.timeIntervalSince(snapshot.checkedAt) >= 6 * 3600 { refreshInBackground() }
            return snapshot
        }
        do {
            let value = try await refreshNow()
            guard date.map(value.feed.covers) ?? true else { throw TransitTimetableError.unavailableDate(latest: value.feed.validThrough) }
            return value
        } catch {
            if let snapshot, date.map(snapshot.feed.covers) ?? true { return snapshot }
            if let snapshot, date != nil { throw TransitTimetableError.unavailableDate(latest: snapshot.feed.validThrough) }
            throw error
        }
    }
    private func refreshInBackground() {
        guard refreshTask == nil, Date.now.timeIntervalSince(lastAttempt) > 60 else { return }
        Task { _ = try? await refreshNow() }
    }
    private func refreshNow() async throws -> TransitFeedSnapshot {
        if let refreshTask { return try await refreshTask.value }
        lastAttempt = .now
        let previous = snapshot, downloader = downloader
        let task = Task.detached(priority: .utility) {
            let result = try await downloader(previous?.version)
            guard let feed = result.feed ?? previous?.feed else { throw URLError(.cannotParseResponse) }
            return TransitFeedSnapshot(feed: feed, version: result.version, checkedAt: .now, bundled: false)
        }
        refreshTask = task
        do {
            let value = try await task.value
            snapshot = value; refreshTask = nil
            persist(value)
            if previous?.version != value.version { NotificationCenter.default.post(name: .transitTimetableChanged, object: nil) }
            return value
        } catch { refreshTask = nil; throw error }
    }
    func flushCache() async { await writing?.value }
    func waitForRefresh() async { _ = try? await refreshTask?.value }
    private func persist(_ value: TransitFeedSnapshot) {
        let folder = folder, previousWrite = writing
        writing = Task.detached(priority: .utility) {
            await previousWrite?.value
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
                let disk = Disk(version: value.version, checkedAt: value.checkedAt, payload: try value.feed.encoded())
                try encoder.encode(disk).write(to: folder.appending(path: "prepared.plist"), options: .atomic)
                try encoder.encode(Schedule(value.feed)).write(to: folder.appending(path: "summary.plist"), options: .atomic)
            } catch { }
        }
    }
    nonisolated static func cachedSummary() -> Schedule? {
        guard let data = try? Data(contentsOf: folder.appending(path: "summary.plist"), options: .mappedIfSafe) else { return nil }
        return try? PropertyListDecoder().decode(Schedule.self, from: data)
    }
    private nonisolated static func readLocal(folder: URL, legacy: [URL], bundle: URL?) -> TransitFeedSnapshot? {
        if let data = try? Data(contentsOf: folder.appending(path: "prepared.plist"), options: .mappedIfSafe),
           let disk = try? PropertyListDecoder().decode(Disk.self, from: data), let feed = try? PreparedTransitFeed.decode(disk.payload) {
            return .init(feed: feed, version: disk.version, checkedAt: disk.checkedAt, bundled: false)
        }
        for old in legacy {
            guard let version = try? String(contentsOf: old.appending(path: "version"), encoding: .utf8) else { continue }
            let checked = (try? String(contentsOf: old.appending(path: "checked"), encoding: .utf8)).flatMap(Double.init) ?? 0
            if let bundle, version == (try? String(contentsOf: bundle.deletingPathExtension().appendingPathExtension("version"), encoding: .utf8)),
               let data = try? Data(contentsOf: bundle, options: .mappedIfSafe), let feed = try? PreparedTransitFeed.decode(data) {
                return .init(feed: feed, version: version, checkedAt: Date(timeIntervalSince1970: checked), bundled: false)
            }
            let files = Dictionary(uniqueKeysWithValues: ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "calendar.txt", "calendar_dates.txt"].compactMap { name in
                (try? Data(contentsOf: old.appending(path: name), options: .mappedIfSafe)).map { (name, $0) }
            })
            if let feed = try? PreparedTransitFeed(files: files) {
                return .init(feed: feed, version: version, checkedAt: Date(timeIntervalSince1970: checked), bundled: false)
            }
        }
        if let bundle, let data = try? Data(contentsOf: bundle, options: .mappedIfSafe), let feed = try? PreparedTransitFeed.decode(data) {
            let version = (try? String(contentsOf: bundle.deletingPathExtension().appendingPathExtension("version"), encoding: .utf8)) ?? "bundled-\(feed.validFrom)-\(feed.validThrough)"
            return .init(feed: feed, version: version, checkedAt: .distantPast, bundled: true)
        }
        return nil
    }
    private nonisolated static func download(_ previous: String?) async throws -> Download {
        let zip = try await RemoteZip(StaticFeed.url)
        let names = ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt"] + ["calendar.txt", "calendar_dates.txt"].filter { zip.entries[$0] != nil }
        let version = try names.map { name in
            guard let entry = zip.entries[name] else { throw URLError(.cannotParseResponse) }
            return "\(name):\(entry.crc)"
        }.joined(separator: "|")
        if previous == version { return .init(feed: nil, version: version) }
        let files = try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for name in names { group.addTask { (name, try await zip.read(zip.entries[name]!)) } }
            var values: [String: Data] = [:]
            for try await (name, data) in group { values[name] = data }
            return values
        }
        return .init(feed: try PreparedTransitFeed(files: files), version: version)
    }
}

enum TransitTimetableError: LocalizedError {
    case unavailableDate(latest: String)
    var errorDescription: String? {
        switch self {
        case .unavailableDate(let latest):
            let input = DateFormatter(); input.dateFormat = "yyyyMMdd"; input.timeZone = PreparedTransitFeed.calendar.timeZone
            let last = input.date(from: latest)?.formatted(date: .abbreviated, time: .omitted) ?? latest
            return "Published service is available through \(last). Connect to download a newer timetable, then retry, or choose an earlier date."
        }
    }
}
