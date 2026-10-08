import Foundation

enum WheelchairAccess: Int, Codable, Hashable {
    case unknown = 0, accessible = 1, inaccessible = 2
    init(feedValue: String) { self = Self(rawValue: Int(feedValue) ?? 0) ?? .unknown }
}

struct Stop: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    var ids: [String] = []
    var wheelchairBoarding: WheelchairAccess? = nil

    var id: String { code }
}

struct Route: Hashable, Codable {
    let name: String
    let color: String
    let textColor: String
}

struct Upcoming: Identifiable {
    let route: Route
    let headsign: String
    var times: [Date] = []
    var tripIDs: [String] = []
    var live = false

    var id: String { route.name + "|" + headsign }
}

struct Favourite: Codable, Hashable {
    var code: String
    var nickname: String?
}

struct PinnedStop: Codable {
    let title: String
    let stop: Stop
}

enum AppGroup {
    static let id = "group.Sabateesh.OCTranspoBusSchedule"
    static let defaults = UserDefaults(suiteName: id) ?? .standard
    static let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) ?? URL.cachesDirectory

    static var pinnedStops: [PinnedStop] {
        get {
            guard let data = defaults.data(forKey: "pinnedStops") else { return [] }
            return (try? JSONDecoder().decode([PinnedStop].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "pinnedStops")
        }
    }
}

func arrivalLabel(_ time: Date, now: Date = .now) -> String {
    let minutes = Int(time.timeIntervalSince(now) / 60)
    if minutes < 1 { return "Due" }
    if minutes < 60 { return "\(minutes) min" }
    return time.formatted(date: .omitted, time: .shortened)
}
