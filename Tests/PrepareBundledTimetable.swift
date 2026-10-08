import Foundation

@main struct PrepareBundledTimetable {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: prepare-timetable <GTFS folder> <output.transit>") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        var files: [String: Data] = [:]
        for name in ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "calendar.txt", "calendar_dates.txt"] {
            files[name] = try? Data(contentsOf: folder.appending(path: name), options: .mappedIfSafe)
        }
        let feed = try PreparedTransitFeed(files: files)
        let encoded = try feed.encoded()
        let restored = try PreparedTransitFeed.decode(encoded)
        guard restored.trips.count == feed.trips.count else { fatalError("Prepared feed failed verification") }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: output, options: .atomic)
        print("Prepared", feed.trips.count, "trip templates; service", feed.validFrom, "through", feed.validThrough, "bytes", encoded.count)
    }
}
