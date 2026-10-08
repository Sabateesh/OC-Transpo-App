import AppIntents
import Foundation

struct JourneyActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update journey progress"
    static var description = IntentDescription("Confirm boarding or getting off your active journey.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var isDiscoverable = false
    @Parameter(title: "Journey") var sessionID: String
    @Parameter(title: "Step") var legIndex: Int
    @Parameter(title: "Action token") var actionToken: String
    @Parameter(title: "Getting off") var alighting: Bool

    init() {}
    init(sessionID: UUID, legIndex: Int, actionToken: String, alighting: Bool) {
        self.sessionID = sessionID.uuidString; self.legIndex = legIndex
        self.actionToken = actionToken; self.alighting = alighting
    }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await JourneySession.shared.restoreIfNeeded()
        guard await JourneySession.shared.performActivityAction(sessionID: sessionID, legIndex: legIndex,
                                                                actionToken: actionToken, alighting: alighting) else {
            throw JourneyActionError.stepChanged
        }
        #else
        try requireAppProcess()
        #endif
        return .result()
    }
    private func requireAppProcess() throws { throw JourneyActionError.stepChanged }
}

enum JourneyActionError: LocalizedError {
    case stepChanged
    var errorDescription: String? { "This journey step has changed. Open your journey to see the current step." }
}
