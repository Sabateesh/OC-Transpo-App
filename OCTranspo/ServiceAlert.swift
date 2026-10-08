import Foundation

struct ServiceAlert: Identifiable, Codable {
    static let feed = URL(string: "https://www.octranspo.com/en/feeds/updates-en/")!

    var id: String { link.absoluteString + "|" + title }
    var title = ""
    var link = URL(string: "https://www.octranspo.com/en/alerts")!
    var date: Date?
    var category = ""
    var routes: Set<String> = []
    var stops: Set<String> = []
    var closedStops: Set<String>? = nil
    var alternativeStops: Set<String>? = nil
    var publishedMap: URL? = nil
    var details: String? = nil
    var activeFrom: Date?
    var activeThrough: Date?
    var dailyHours: AlertHours?
    var directions: Set<String>? = nil
}

final class AlertFeedParser: NSObject, XMLParserDelegate {
    private var alerts: [ServiceAlert] = []
    private var current: ServiceAlert?
    private var text = ""
    private var isRSS = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func parse(_ data: Data) -> [ServiceAlert]? {
        let delegate = AlertFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.isRSS else { return nil }
        return delegate.alerts
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "rss" { isRSS = true }
        if element == "item" { current = ServiceAlert() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "title":
            current?.title = value
        case "link":
            if let url = URL(string: value) { current?.link = url }
        case "pubDate":
            current?.date = Self.dateFormatter.date(from: value)
        case "category":
            if value.lowercased().hasPrefix("affectedroutes-") {
                let names = value.dropFirst("affectedroutes-".count)
                for match in names.matches(of: #/\b(\d{1,3}[A-Za-z]?)\b/#) {
                    current?.routes.insert(String(match.1).uppercased())
                }
            } else if current?.category.isEmpty == true {
                current?.category = value
            }
        case "description":
            let affected = AlertScope.affectedStops(in: value)
            current?.closedStops = affected.closed
            current?.alternativeStops = affected.alternative
            current?.publishedMap = AlertScope.publishedMap(in: value)
            let plain = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&rsquo;", with: "’")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            current?.details = plain
            for match in value.matches(of: #/[#(](\d{4})\b/#) { current?.stops.insert(String(match.1)) }
        case "item":
            if var current, !current.title.isEmpty, ["https", "http"].contains(current.link.scheme ?? "") {
                current.directions = AlertScope.directions(in: current.title)
                let window = AlertScope.window(in: current.details ?? "", published: current.date)
                current.activeFrom = window?.lowerBound ?? AlertScope.openEndedStart(in: current.details ?? "", published: current.date)
                current.activeThrough = window?.upperBound
                current.dailyHours = AlertScope.dailyHours(in: current.details ?? "")
                alerts.append(current)
            }
            current = nil
        default:
            break
        }
    }
}

struct ServiceAlertSnapshot: Codable {
    let alerts: [ServiceAlert]
    let updatedAt: Date
    private static var url: URL { URL.applicationSupportDirectory.appending(path: "service-alerts.json") }
    static func load() -> Self? {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data),
              value.updatedAt <= Date.now.addingTimeInterval(60) else { return nil }
        return value
    }
    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }
}

enum AlertMatch: Equatable { case confirmed, possible }

struct AlertHours: Codable {
    let startMinute: Int
    let endMinute: Int
    func contains(_ date: Date, startingAt first: Date?) -> Bool {
        let calendar = PreparedTransitFeed.calendar
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if startMinute > endMinute {
            if minute >= startMinute { return true }
            if minute <= endMinute {
                guard let first else { return true }
                return calendar.startOfDay(for: date) > calendar.startOfDay(for: first)
            }
            return false
        }
        return minute >= startMinute && minute <= endMinute
    }
}

struct AlertScope {
    static func affectedStops(in html: String) -> (closed: Set<String>, alternative: Set<String>) {
        let rows = (try? NSRegularExpression(pattern: #"<tr\b[^>]*>(.*?)</tr>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]))?
            .matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
        let cells = try? NSRegularExpression(pattern: #"<t[dh]\b[^>]*>(.*?)</t[dh]>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let codes = try? NSRegularExpression(pattern: #"(?:#|\()(\d{4})\b"#)
        func numbers(_ value: String) -> Set<String> {
            Set((codes?.matches(in: value, range: NSRange(value.startIndex..., in: value)) ?? []).compactMap { match in
                Range(match.range(at: 1), in: value).map { String(value[$0]) }
            })
        }
        var closed: Set<String> = [], alternative: Set<String> = []
        for row in rows {
            guard let range = Range(row.range(at: 1), in: html) else { continue }
            let value = String(html[range])
            let columns = (cells?.matches(in: value, range: NSRange(value.startIndex..., in: value)) ?? []).compactMap { match in
                Range(match.range(at: 1), in: value).map { String(value[$0]) }
            }
            if columns.count >= 3 {
                closed.formUnion(numbers(columns[0]))
                alternative.formUnion(numbers(columns[2]))
            }
        }
        let plain = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let missed = plain.range(of: "Stops missed", options: .caseInsensitive) {
            let suffix = plain[missed.upperBound...]
            let end = ["Alternative Stops", "Alternate Stops", "Detour routing", "Detour map"].compactMap { suffix.range(of: $0, options: .caseInsensitive)?.lowerBound }.min() ?? suffix.endIndex
            closed.formUnion(numbers(String(suffix[..<end])))
        }
        return (closed, alternative)
    }
    static func publishedMap(in html: String) -> URL? {
        let pattern = #"(?:href|src)\s*=\s*['\"]([^'\"]+\.(?:png|jpe?g|pdf)(?:\?[^'\"]*)?)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[range]), relativeTo: ServiceAlert.feed)?.absoluteURL,
                  url.host == "www.octranspo.com", url.lastPathComponent.count > 5,
                  url.path.localizedCaseInsensitiveContains("detour") else { continue }
            return url
        }
        return nil
    }
    static func openEndedStart(in details: String, published: Date?) -> Date? {
        guard details.localizedCaseInsensitiveContains("until further notice") else { return nil }
        let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        let pattern = #"(?i)\bfrom\b.{0,100}?\b("# + months + #")\s+(\d{1,2})(?:,?\s+(\d{4}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
              let monthRange = Range(match.range(at: 1), in: details),
              let dayRange = Range(match.range(at: 2), in: details),
              let month = ["january","february","march","april","may","june","july","august","september","october","november","december"].firstIndex(of: details[monthRange].lowercased()).map({ $0 + 1 }),
              let day = Int(details[dayRange]) else { return nil }
        let calendar = PreparedTransitFeed.calendar
        let year = Range(match.range(at: 3), in: details).flatMap({ Int(details[$0]) })
            ?? calendar.component(.year, from: published ?? .now)
        guard let date = calendar.date(from: .init(year: year, month: month, day: day)),
              let entire = Range(match.range, in: details) else { return nil }
        return date.addingTimeInterval(Double(minute(String(details[entire.lowerBound..<monthRange.lowerBound])) ?? 0) * 60)
    }
    static func minute(_ input: String) -> Int? {
        let pattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).last,
              let hourRange = Range(match.range(at: 1), in: input),
              let suffixRange = Range(match.range(at: 3), in: input),
              let hour = Int(input[hourRange]), (1...12).contains(hour) else { return nil }
        let minute = Range(match.range(at: 2), in: input).flatMap { Int(input[$0]) } ?? 0
        guard (0...59).contains(minute) else { return nil }
        return (hour % 12 + (input[suffixRange].lowercased() == "pm" ? 12 : 0)) * 60 + minute
    }
    static func dailyHours(in details: String) -> AlertHours? {
        guard details.range(of: #"\bnightly\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let pattern = #"(?i)\bbetween\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm))\s+and\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: details, range: NSRange(details.startIndex..., in: details)),
              let first = Range(match.range(at: 1), in: details).flatMap({ minute(String(details[$0])) }),
              let last = Range(match.range(at: 2), in: details).flatMap({ minute(String(details[$0])) }) else { return nil }
        return AlertHours(startMinute: first, endMinute: last)
    }
    static func directions(in title: String) -> Set<String> {
        let source = title.lowercased()
        var values: Set<String> = []
        for (code, pattern) in [("E", #"\b(?:eb|eastbound)\b"#), ("W", #"\b(?:wb|westbound)\b"#),
                                ("N", #"\b(?:nb|northbound)\b"#), ("S", #"\b(?:sb|southbound)\b"#)] {
            if source.range(of: pattern, options: .regularExpression) != nil { values.insert(code) }
        }
        return values
    }
    static func direction(of leg: JourneyLeg) -> String? {
        let dx = (leg.alight.longitude - leg.board.longitude) * 0.71
        let dy = leg.alight.latitude - leg.board.latitude
        if abs(dx) > 0.002 && abs(dx) > abs(dy) * 1.5 { return dx > 0 ? "E" : "W" }
        if abs(dy) > 0.002 && abs(dy) > abs(dx) * 1.5 { return dy > 0 ? "N" : "S" }
        return nil
    }
    static func window(in details: String, published: Date?) -> ClosedRange<Date>? {
        let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        let pattern = #"\b(?:from|between)\b.{0,160}?\b("# + months + #")\s+(\d{1,2})(?:,?\s+(\d{4}))?.{0,180}?\b(?:until|through|to|and)\b.{0,100}?\b("# + months + #")\s+(\d{1,2})(?:,?\s+(\d{4}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: details, range: NSRange(details.startIndex..., in: details)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let range = Range(match.range(at: i), in: details) else { return nil }
            return String(details[range])
        }
        func month(_ value: String?) -> Int? {
            guard let value else { return nil }
            return ["january","february","march","april","may","june","july","august","september","october","november","december"].firstIndex(of: value.lowercased()).map { $0 + 1 }
        }
        guard let firstMonth = month(group(1)), let firstDay = group(2).flatMap(Int.init),
              let lastMonth = month(group(4)), let lastDay = group(5).flatMap(Int.init) else { return nil }
        let calendar = PreparedTransitFeed.calendar
        let year = group(3).flatMap(Int.init) ?? calendar.component(.year, from: published ?? .now)
        let endYear = group(6).flatMap(Int.init) ?? (lastMonth < firstMonth ? year + 1 : year)
        guard let first = calendar.date(from: .init(year: year, month: firstMonth, day: firstDay)),
              let last = calendar.date(from: .init(year: endYear, month: lastMonth, day: lastDay)),
              let afterLast = calendar.date(byAdding: .day, value: 1, to: last), first < afterLast,
              let firstMonthRange = Range(match.range(at: 1), in: details),
              let lastMonthRange = Range(match.range(at: 4), in: details),
              let wholeRange = Range(match.range, in: details) else { return nil }
        let startPrefix = String(details[wholeRange.lowerBound..<firstMonthRange.lowerBound])
        let endPrefix = String(details[firstMonthRange.upperBound..<lastMonthRange.lowerBound])
        let nightly = dailyHours(in: details)
        let start = nightly == nil ? first.addingTimeInterval(Double(minute(startPrefix) ?? 0) * 60) : first
        var end = afterLast.addingTimeInterval(-1)
        if let nightly, endPrefix.range(of: #"\bmorning\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            end = last.addingTimeInterval(Double(nightly.endMinute) * 60)
        } else if nightly == nil, let minute = minute(endPrefix) {
            end = last.addingTimeInterval(Double(minute) * 60)
        }
        guard start <= end else { return nil }
        return start...end
    }
}

extension ServiceAlert {
    func closesJourneyStop(_ journey: Journey, startingAt index: Int = 0, onBoard: Bool = false) -> Bool {
        guard match(journey, startingAt: index) == .confirmed, let closedStops, !closedStops.isEmpty else { return false }
        for (offset, leg) in journey.legs.enumerated() where offset >= index {
            if closedStops.contains(leg.alight.code) || (offset != index || !onBoard) && closedStops.contains(leg.board.code) { return true }
        }
        return false
    }
    func match(_ journey: Journey, startingAt index: Int = 0) -> AlertMatch? {
        for leg in journey.legs.dropFirst(max(0, index)) {
            let routeMatches = routes.contains(leg.route.name)
            let stopMatches = ([leg.board, leg.alight] + leg.callingPoints.map(\.stop)).contains { stop in
                stops.contains(stop.code) || !stops.isDisjoint(with: stop.ids)
            }
            guard (routes.isEmpty || routeMatches) && (stops.isEmpty || stopMatches),
                  !routes.isEmpty || !stops.isEmpty else { continue }
            if let activeFrom, leg.departure < activeFrom { continue }
            if let activeThrough, leg.departure > activeThrough { continue }
            if let dailyHours, !dailyHours.contains(leg.departure, startingAt: activeFrom) { continue }
            let directions = directions ?? []
            let travelDirection = AlertScope.direction(of: leg)
            if !directions.isEmpty, let travelDirection, !directions.contains(travelDirection) { continue }
            let verifiedDates = activeFrom != nil && (activeThrough != nil || details?.localizedCaseInsensitiveContains("until further notice") == true)
            return !verifiedDates || stops.isEmpty || (!directions.isEmpty && travelDirection == nil) ? .possible : .confirmed
        }
        return nil
    }
    func affects(_ journey: Journey, startingAt index: Int = 0) -> Bool { match(journey, startingAt: index) != nil }
}
