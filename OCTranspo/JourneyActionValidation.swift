import Foundation

enum JourneyActionValidation {
    static func accepts(sessionID: String, expectedSessionID: UUID, legIndex: Int, currentLegIndex: Int,
                        actionToken: String, expectedToken: UUID, alighting: Bool, onBoard: Bool,
                        legCount: Int, finished: Bool, expiresAt: Date, now: Date) -> Bool {
        UUID(uuidString: sessionID) == expectedSessionID && UUID(uuidString: actionToken) == expectedToken
            && legIndex == currentLegIndex && legIndex >= 0 && legIndex < legCount
            && alighting == onBoard && !finished && expiresAt > now
    }
}
