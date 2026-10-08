#if DEBUG
import CoreLocation
import Foundation
import UIKit

@MainActor
final class JourneyReliabilityRecorder {
    static let shared = JourneyReliabilityRecorder()
    private(set) var running = false
    private let folder = URL.documentsDirectory.appending(path: "journey-measurement", directoryHint: .isDirectory)
    private var handle: FileHandle?
    private var lastSample = Date.distantPast
    private var originalBatteryMonitoring = false
    private var startedAt = Date.now
    var reportURL: URL? {
        let file = folder.appending(path: "summary.json")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
    var eventsURL: URL? {
        let file = folder.appending(path: "events.jsonl")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func start(sessionID: UUID) {
        guard !running else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "events.jsonl")
        try? FileManager.default.removeItem(at: file)
        FileManager.default.createFile(atPath: file.path, contents: Data())
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        handle = try? FileHandle(forWritingTo: file)
        originalBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        startedAt = .now
        running = true
        UserDefaults.standard.set(true, forKey: "journeyMeasurementRunning")
        record("started", ["session": sessionID.uuidString, "battery": UIDevice.current.batteryLevel])
    }
    func resume(sessionID: UUID) {
        guard !running, UserDefaults.standard.bool(forKey: "journeyMeasurementRunning") else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "events.jsonl")
        handle = try? FileHandle(forWritingTo: file)
        _ = try? handle?.seekToEnd()
        originalBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        startedAt = .now; running = true
        record("restored", ["session": sessionID.uuidString, "battery": UIDevice.current.batteryLevel])
    }
    func stop(reason: String) {
        guard running else { return }
        record("ended", ["reason": reason])
        let file = folder.appending(path: "events.jsonl")
        let events: [[String: Any]] = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } ?? []
        let beginning = events.first(where: { $0["event"] as? String == "started" })
        let initialBattery = beginning?["battery"] as? Float ?? -1
        let endingBattery = UIDevice.current.batteryLevel
        let summary: [String: Any] = ["endedAt": Date.now.timeIntervalSince1970,
            "durationSeconds": Date.now.timeIntervalSince1970 - (beginning?["time"] as? Double ?? startedAt.timeIntervalSince1970),
            "locationUpdates": events.filter { $0["event"] as? String == "location" }.count,
            "backgroundLocationUpdates": events.filter { $0["event"] as? String == "location" && $0["active"] as? Bool == false }.count,
            "liveRefreshSuccesses": events.filter { $0["event"] as? String == "feed" && $0["success"] as? Bool == true }.count,
            "liveRefreshFailures": events.filter { $0["event"] as? String == "feed" && $0["success"] as? Bool == false }.count,
            "batteryAtStart": initialBattery, "batteryAtEnd": endingBattery,
            "batteryAvailable": initialBattery >= 0 && endingBattery >= 0,
            "relaunches": events.filter { $0["event"] as? String == "restored" }.count]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appending(path: "summary.json"), options: .atomic)
        }
        try? handle?.close(); handle = nil; running = false
        UserDefaults.standard.set(false, forKey: "journeyMeasurementRunning")
        UIDevice.current.isBatteryMonitoringEnabled = originalBatteryMonitoring
    }
    func location(_ fix: CLLocation, active: Bool) {
        guard running else { return }
        record("location", ["active": active, "accuracyMeters": fix.horizontalAccuracy,
                            "ageSeconds": Date.now.timeIntervalSince(fix.timestamp), "speedMetersPerSecond": fix.speed])
    }
    func feed(success: Bool, age: TimeInterval?) {
        guard running else { return }
        record("feed", ["success": success, "ageSeconds": age ?? -1])
    }
    func sample(active: Bool) {
        guard running, Date.now.timeIntervalSince(lastSample) >= 30 else { return }
        lastSample = .now
        record("sample", ["active": active, "battery": UIDevice.current.batteryLevel,
                          "batteryState": UIDevice.current.batteryState.rawValue,
                          "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled])
    }
    func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard running, let handle else { return }
        var values = fields
        values["event"] = event
        values["time"] = Date.now.timeIntervalSince1970
        values["uptime"] = ProcessInfo.processInfo.systemUptime
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let newline = "\n".data(using: .utf8) else { return }
        do { try handle.write(contentsOf: data); try handle.write(contentsOf: newline) } catch { }
    }
}
#endif
