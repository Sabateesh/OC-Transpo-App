import ActivityKit
import Foundation

actor JourneyActivityController {
    static let shared = JourneyActivityController()
    private var activity: Activity<JourneyActivityAttributes>?
    private var revision = 0
    private var ended: Set<UUID> = []

    func update(sessionID: UUID, destination: String, state: JourneyActivityAttributes.ContentState, allowStart: Bool) async {
        guard !ended.contains(sessionID) else { return }
        revision += 1
        let version = revision
        if activity?.attributes.sessionID != sessionID { activity = Activity<JourneyActivityAttributes>.activities.first { $0.attributes.sessionID == sessionID } }
        for old in Activity<JourneyActivityAttributes>.activities where old.attributes.sessionID != sessionID {
            await old.end(nil, dismissalPolicy: .immediate)
            guard version == revision else { return }
        }
        let content = ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(120))
        if let activity {
            await activity.update(content)
        } else if allowStart && ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: JourneyActivityAttributes(sessionID: sessionID, destination: destination), content: content, pushType: nil)
        }
    }
    func end(sessionID: UUID) async {
        ended.insert(sessionID)
        revision += 1
        for item in Activity<JourneyActivityAttributes>.activities where item.attributes.sessionID == sessionID {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        if activity?.attributes.sessionID == sessionID { activity = nil }
    }
    func removeOrphans(keeping sessionID: UUID?) async {
        for item in Activity<JourneyActivityAttributes>.activities where item.attributes.sessionID != sessionID {
            await item.end(nil, dismissalPolicy: .immediate)
        }
    }
}
