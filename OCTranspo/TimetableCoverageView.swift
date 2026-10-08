import SwiftUI

struct TimetableCoverageView: View {
    let through: String
    let retry: () -> Void
    var body: some View {
        let expired = through < PreparedTransitFeed.dayKey(.now)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
            VStack(alignment: .leading, spacing: 5) {
                Text(expired ? "Timetable needs an update" : "Timetable ending soon").font(.subheadline.bold())
                Text("Published service through \(displayDate). Newer dates need a timetable download.")
                    .font(.caption)
                Button("Check for newer timetable", action: retry).font(.caption.bold())
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
    private var displayDate: String {
        let parser = DateFormatter(); parser.dateFormat = "yyyyMMdd"; parser.timeZone = PreparedTransitFeed.calendar.timeZone
        return parser.date(from: through)?.formatted(date: .abbreviated, time: .omitted) ?? through
    }
}
