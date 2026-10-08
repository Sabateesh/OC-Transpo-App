#if DEBUG
import ActivityKit
import Foundation
import CoreLocation

@MainActor enum JourneyDiagnostics {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--journey-diagnostics") }
    static func run() async {
        let arguments = ProcessInfo.processInfo.arguments
        let session = JourneySession.shared
        if arguments.contains("--measure-start") {
            JourneyPreview.start(track: true)
            if let saved = JourneyArchiveStore(url: URL.documentsDirectory.appending(path: "journey-diagnostics/active.json")).load() {
                JourneyReliabilityRecorder.shared.start(sessionID: saved.sessionID)
            }
            return
        }
        if arguments.contains("--measure-stop") {
            await JourneySession.shared.restoreIfNeeded()
            JourneyReliabilityRecorder.shared.stop(reason: "diagnostic")
            JourneySession.shared.end()
            return
        }
        if arguments.contains("--measure") {
            JourneyPreview.start(track: true)
            let recorder = JourneyReliabilityRecorder.shared
            if let saved = JourneyArchiveStore(url: URL.documentsDirectory.appending(path: "journey-diagnostics/active.json")).load() {
                recorder.start(sessionID: saved.sessionID)
                recorder.record("scene", ["active": false])
                recorder.location(CLLocation(latitude: 45.4255, longitude: -75.6901), active: false)
                recorder.feed(success: true, age: 0)
                recorder.sample(active: false)
                recorder.stop(reason: "diagnostic")
            }
            JourneySession.shared.end()
            return
        }
        if arguments.contains("--location-retry") { await checkLocationRetry(); return }
        if arguments.contains("--resume-action") { await checkRestoredAction(); return }
        if arguments.contains("--actions") { await checkActions(); return }
        if arguments.contains("--location") { await checkLocation(); return }
        if arguments.contains("--start") {
            JourneyPreview.start(track: true)
            session.board()
        } else {
            await session.restoreIfNeeded()
        }
        let restored = session.progress.onBoard && session.isRunning
        if arguments.contains("--end") { session.end() }
        else { session.openRequested = true }
        try? await Task.sleep(for: .seconds(3))
        let root = URL.documentsDirectory.appending(path: "journey-diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshot = JourneyArchiveStore(url: root.appending(path: "active.json")).load()
        let report: [String: Any] = ["restoredOrStartedOnBoard": restored, "isRunning": session.isRunning, "onBoard": session.progress.onBoard, "legIndex": session.progress.legIndex, "savedOnBoard": snapshot?.progress.onBoard ?? false, "archiveExists": snapshot != nil, "activities": Activity<JourneyActivityAttributes>.activities.count, "destination": session.destination?.title ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appending(path: "results.json"), options: .atomic)
        }
    }
    private static func checkActions() async {
        let session = JourneySession.shared
        JourneyPreview.start(track: true)
        let store = JourneyArchiveStore(url: URL.documentsDirectory.appending(path: "journey-diagnostics/active.json"))
        var report: [String: Bool] = [:]
        func tap(_ saved: JourneyArchive, alighting: Bool) async -> Bool {
            let intent = JourneyActionIntent(sessionID: saved.sessionID, legIndex: saved.progress.legIndex,
                                             actionToken: saved.actionToken!.uuidString, alighting: alighting)
            do { _ = try await intent.perform(); return true } catch { return false }
        }
        if let initial = store.load() {
            report["boardIntent"] = await tap(initial, alighting: false)
            report["boardSaved"] = store.load()?.progress.onBoard == true
            report["duplicateBoardRejected"] = !(await tap(initial, alighting: false))
            if let riding = store.load() {
                report["alightIntent"] = await tap(riding, alighting: true)
                report["alightSaved"] = store.load()?.progress.legIndex == 1 && store.load()?.progress.onBoard == false
                report["duplicateAlightRejected"] = !(await tap(riding, alighting: true))
            }
            if let transfer = store.load() {
                report["transferBoardIntent"] = await tap(transfer, alighting: false)
                if let riding = store.load() {
                    report["finalAlightIntent"] = await tap(riding, alighting: true)
                    report["finalWalkSaved"] = store.load()?.progress.legIndex == 2
                }
            }
            session.end()
            report["endedJourneyRejected"] = !(await tap(initial, alighting: false))
        }
        writeReport(report, name: "actions.json")
    }
    private static func checkRestoredAction() async {
        let session = JourneySession.shared
        await session.restoreIfNeeded()
        let store = JourneyArchiveStore(url: URL.documentsDirectory.appending(path: "journey-diagnostics/active.json"))
        var report: [String: Any] = [:]
        if let saved = store.load(), let token = saved.actionToken {
            report["restoredOnBoard"] = session.progress.onBoard
            report["savedWalkingSteps"] = session.journey?.walks.reduce(0) { $0 + $1.instructions.count } ?? 0
            let intent = JourneyActionIntent(sessionID: saved.sessionID, legIndex: saved.progress.legIndex, actionToken: token.uuidString, alighting: true)
            do { _ = try await intent.perform(); report["restoredIntentWorked"] = true }
            catch { report["restoredIntentWorked"] = false }
            report["advancedOneLeg"] = store.load()?.progress.legIndex == saved.progress.legIndex + 1
        }
        session.openRequested = true
        writeReport(report, name: "restored-action.json")
    }
    private static func checkLocationRetry() async {
        let manager = DiagnosticLocationManager()
        let location = Location(manager: manager, timeoutSeconds: 0.1)
        await location.update()
        var report: [String: Bool] = ["locating": location.status == .locating]
        try? await Task.sleep(for: .seconds(0.3))
        report["timeoutUnavailable"] = location.status == .unavailable && location.current == nil
        location.retry()
        report["retryLocating"] = location.status == .locating
        location.locationManager(manager, didUpdateLocations: [CLLocation(coordinate: .init(latitude: 45.4215, longitude: -75.6972), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: .now.addingTimeInterval(-300))])
        report["staleFixRejected"] = location.current == nil
        location.locationManager(manager, didUpdateLocations: [CLLocation(coordinate: .init(latitude: 45.4215, longitude: -75.6972), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: .now)])
        report["retryRecovered"] = location.status == .ready && location.current != nil
        try? await Task.sleep(for: .seconds(0.3))
        report["timeoutCancelledAfterSuccess"] = location.status == .ready
        writeReport(report, name: "location-retry.json")
    }
    private static func checkLocation() async {
        let location = Location()
        await location.update()
        try? await Task.sleep(for: .seconds(17))
        writeReport(["status": String(describing: location.status), "hasLocation": location.current != nil], name: "location.json")
    }
    private static func writeReport(_ report: [String: Any], name: String) {
        let root = URL.documentsDirectory.appending(path: "journey-diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appending(path: name), options: .atomic)
        }
    }

}
private final class DiagnosticLocationManager: CLLocationManager {
    override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
    override func startUpdatingLocation() {}
    override func stopUpdatingLocation() {}
}
#endif
